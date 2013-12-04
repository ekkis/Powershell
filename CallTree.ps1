#
# - Synopsis -
#
# This script allows generation of a call tree on one or more 
# assemblies and may optionally store said information in database 
# tables
#
# - Syntax -
# -assemblies {list}
#    a list of comma-delimited paths. If not provided 
#    as a parameter, values can also be piped into the utility. the parameter 
#    is positional and thus need not be named
# -t {FQN}
#    the fully-qualified name of a SQL Server table prefix where 
#    to store the information (please see the Results section below for further 
#    information). When this parameter is not provided the utility returns
#    its information to the caller as a list of objects.
# -clean {drop|del}
#    drop: requests the table family be dropped and recreated
#	del: requests the table family be wiped
# -SQL
#    returns the SQL that is being executed
# -NoExec
#    prevents actual execution
# -type {name}
#    a filter specification that returns information for only the
#    given class from the list of assemblies
# -method {name}
#    like -type, this parameter narrows the results to
#    a given method
#
# - Requirements -
#
# For analysis of 3E objects, Powershell 3.0 or greater is required 
# since 3E DLLs are compiled against the .Net 4.0 runtime which cannot 
# load in Powershell 2.0
#
# - Marginalia -
#
# Author: Erick Calder <e@arix.com>
# Dept: IT/Systems Engineering
# Last Modified: 11/10/2013
# Docs URL: http://la-elitedocs.elitecorp.com/wiki/index.php?title=CallTree
#

param(
    [string[]] $assemblies, $t,
    $type, $method, 
	$clean = "", 
	[switch] $SQL = $false,
	[switch] $NoExec = $false
	)

begin {
	$scriptpath = split-path $script:MyInvocation.MyCommand.Path
    . $scriptpath\db

    function main() {
	    # if no assemblies were passed on the command line
	    # then grab all assemblies in the current directory

	    if ($assemblies.count -eq 0) { $assemblies = ls "*.dll" |%{ $_.FullName } }

        # if assemblies passed on the command line do not contain
        # full paths, the current directory is prepended

        $assemblies = $assemblies |%{
            if ($_.contains("\")) { $_ } else { "{0}\$_" -f $(pwd).Path }
        }

	    # process assemblies, writing results to the database
	    # when requested or to the caller otherwise

		$ret = @()
        write-host "Parsing assemblies..."
		$assemblies |%{
			write-host (gci $_).Name
			$ret += $ct.ParseAssembly($_)
		}
		if (!$t) {
			return $ret
		}

        write-host "Saving to database..."
		$ret |%{
			$assembly = $_.Assembly
			write-host "*`n* $assembly`n*"
			if ($clean -eq "del") { DropAssembly $assembly }
            $_.Types |%{
                write-host ("{0}.{1}" -f $_.Namespace, $_.Name)
				$s = @"
					declare @tid int, @mid int
					,		@ctid int, @cmid int
					,		@iid int, @imid int
"@
			    $s += InsType $_ "@tid"
			    $_.Methods |%{ $s += InsMethod $_ }
				$_.Interfaces |%{ $s += InsInterface "@tid" $_ }

				SQLExec $s
				if ($script:sql) { 
					echo ($script:sql -join "`n")
					$script:sql = @() 
				}
            }
		}
		#get-job |receive-job -Wait -AutoRemoveJob
		write-host "Done"
    }

	function DropAssembly($name) {
		write-host "Deleting tables..."
		if ($name -match "(.*)\\") {
			$dir = $matches[1]
			$name = $name.replace($matches[0], "")
		}
		SQLExec @"
		delete [CallTree.Calls] where CallerId in (
			select Id from [CallTree.Methods] where TypeId in (
				select Id
				from [CallTree.Types] 
				where [Assembly] = '$name' 
				and [AssemblyPath] = '$dir'
				)
			)
		delete [CallTree.Methods] where TypeId in (
			select Id
			from [CallTree.Types] 
			where [Assembly] = '$name' 
			and [AssemblyPath] = '$dir'
			)
		delete [CallTree.Types] 
		where [Assembly] = '$name' 
		and [AssemblyPath] = '$dir'
"@
	}
	function InsType($t, $id) {
		$assembly = $t.assembly
	    $hash = md5($assembly + $t.namespace + $t.name)
		$dir = $assembly.split("\")[-2]
		if ($dir -eq "Application") {
			$category = $assembly.split(".")[1]
			}
		elseif ($dir -eq "bin") {
			$category = "Framework"
			}
		else {
			$category = "System"
		}
		if ($assembly -match "(.*)\\") {
			$dir = $matches[1]
			$assembly = $assembly.replace($matches[0], "")
		}
		if ($t.isinterface) { $isinterface = 1 } else { $isinterface = 0 }
		return @"
			select $id = null
			select $id = id 
			from [$owner].[${tabroot}.Types] 
			where Hash = '$hash'
			
			if $id is null
				begin
				insert [$owner].[${tabroot}.Types] (
					[Category], [Namespace], [Name], 
					[IsInterface], 
					[Assembly], [AssemblyPath], 
					[Hash]
					)
				select '$category', '$($t.namespace)', '$($t.name)', $isinterface, '$assembly', '$dir', '$hash'
				select $id = scope_identity()
				end
"@
	}
	function InsMethod ($m, $tid = "@tid", $mid = "@mid") {
		#write-host (" - {0}.{1}" -f $m.Type.Name, $m.Name)
		$s = "
			select @imid = null
		"
		if ($m.Implements) {
			$s += InsType $m.Implements.Type "@iid"
			$s += InsMethod $m.Implements "@iid" "@imid"
		}
			
		$s += @"
			select $mid = null
			select $mid = id 
			from   [$owner].[${tabroot}.Methods] 
			where  TypeId = $tid 
			and    Name = '$name' 
			and	   Args = '$params'
			
			if $mid is null
				begin
				insert [$owner].[${tabroot}.Methods]
				select $tid, '$($m.name)', '$($m.args)', '$($bool[$m.IsInherited])', $($m.LOC), @imid
				select $mid = scope_identity()
				end
"@
		$m.Calls |%{
			$s += InsType $_.Type "@ctid"
			$s += InsMethod $_ "@ctid" "@cmid"
			$s += InsCall "@mid" "@cmid"
		}
		
		return $s
    }
    function InsCall($CallerId, $CalledId) {
		return @"
			if not exists (
				select	*
				from	[$owner].[${tabroot}.Calls]
				where	CallerId = $CallerId
				and		CalledId = $CalledId
				)
				insert [$owner].[${tabroot}.Calls] 
				select $CallerId, $CalledId
"@
    }
	function InsInterface($typeid, $s) {
		return @"
			if not exists (
				select	*
				from	[$owner].[${tabroot}.Interfaces]
				where	TypeId = $typeid
				and 	Name = '$s'
				)
				insert [$owner].[${tabroot}.Interfaces]
				select	$typeid, '$s'
"@
	}
    function init() {
	    write-host "Initializing..."
		$script:bool = @{ $true = 1; $false = 0 }
		if ($SQL) { 
			remove-variable "sql" -scope "script"
			$script:SQL = @()
		} else { remove-variable "sql" -scope "script" }
		if ($NoExec) { $script:NoExec = $true }
		
	    # load the CallTree library from the location
	    # where this script resides

	    $ctp = Split-Path $script:MyInvocation.MyCommand.Path
	    add-type -path $ctp\Elite.Utils.CallTree.dll

	    # initialise a call-tree object and set
	    # the namespaces to filter out

	    $ct = new-object Elite.Utils.CallTree
	    $ct.FilterNamespaces = @("System.")
	    if ($type) { $ct.FilterType = $type }
	    if ($method) { $ct.FilterMethod = $method }
	    $script:ct = $ct

	    if ($t) {
		    write-host "- database"
		    $script:md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
		    $script:utf8 = new-object -TypeName System.Text.UTF8Encoding
			
		    $script:srv, $script:db, $script:owner, $script:tabroot = $t.split(".")
		    $script:ss = SQLConnect $srv $db
		    TableSetup
	    }
    }
    function TableSetup() {
		write-host "Recreating tables..."
	    if ($clean -eq "drop") {
			"Calls", "Interfaces", "Methods", "Types" |%{
				SQLExec @"
					if object_id('[${tabroot}.$_]') is not null 
						drop table [$owner].[${tabroot}.$_]
"@
			}
		    write-host "- tables dropped"
	    }
		
	    SQLExec @"
	    if object_id('[$owner].[${tabroot}.Types]') is null
			begin
			create table [$owner].[${tabroot}.Types] (
				id int identity(1,1) not null primary key
			,	[Category] varchar(64)
			,	[Namespace] nvarchar(900)
			,	[Name] nvarchar(900)
			,	[IsInterface] bit
			,	[Assembly] nvarchar(128)
			,	[AssemblyPath] nvarchar(900)
			,	[Hash] char(47)
			,	constraint ${tabroot}TypeHashUnq unique clustered (Hash)
			)
			create nonclustered index ${tabroot}TypesCategory on [${tabroot}.Types] ([Category])
			create nonclustered index ${tabroot}TypesAssembly on [${tabroot}.Types] ([Assembly])
			create nonclustered index ${tabroot}TypesNamespace on [${tabroot}.Types] ([Namespace])
			create nonclustered index ${tabroot}TypesType on [${tabroot}.Types] ([Name])
			end
			
	    if object_id('[$owner].[${tabroot}.Methods]') is null
			begin
			create table [$owner].[${tabroot}.Methods] (
				id int identity(1,1) not null primary key
			,   [TypeId] int references [${tabroot}.Types] on delete cascade
			,	[Name] nvarchar(128)
			,	[Args] nvarchar(2048)
			,	[IsInherited] bit
			,	[LOC] int
			,	[Implements] int NULL references [${tabroot}.Methods]
			)
			create nonclustered index ${tabroot}Methods on [${tabroot}.Methods] ([TypeId], [Name])
			end
			
	    if object_id('[$owner].[${tabroot}.Calls]') is null
			begin
		    create table [$owner].[${tabroot}.Calls] (
			    CallerId int references [$owner].[${tabroot}.Methods] -- on delete cascade
		    ,	CalledId int references [$owner].[${tabroot}.Methods] on delete cascade
		    ,	constraint ${tabroot}CallsUnq unique clustered (CallerId, CalledId)
		    )
			end

	    if object_id('[$owner].[${tabroot}.Interfaces]') is null
			begin
		    create table [$owner].[${tabroot}.Interfaces] (
			    TypeId int references [$owner].[${tabroot}.Types] on delete cascade
		    ,	Name nvarchar(1024)
		    )
			create nonclustered index ${tabroot}InterfacesTypeId 
			on [$owner].[${tabroot}.Interfaces] (TypeId, Name)
			end
"@
    	write-host "- tables set up"
    }
	function DBIns($table, $cols) {
		$sql = "insert [$owner].[${tabroot}.$table] select " + (sqlq $cols.count)
		$sql += " select scope_identity()"
		$sql = $sql -f $cols
		try {
			$ret = SQLExec $sql
		}
	    catch [System.Data.SqlClient.SqlException] {
            write-error $sql
	    }

		return $ret
	}
    function md5($s) {
	    [System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($s)))
    }
	function sqlq($n) {
		$ret = @()
		for ($i = 0; $i -lt $n; $i++) { $ret += "'{$i}'" }
		return $ret -join ","
	}
}

process {
    if ($_) { $assemblies += $_.FullName }
}

end {
    init
    main
}

# &$ctp\calltree -table "la-dl580g7.AngelaDB.dbo.CallTree" > c:\temp\out.txt 2> c:\temp\err.txt

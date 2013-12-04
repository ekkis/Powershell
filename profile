# load with: n++ $profile

set-alias grep select-string
set-alias "^" select-object

$ENV:PATH += ";C:\Program Files (x86)\Notepad++"

function Prompt
{
	$tmp = $(Get-Location).Path.Split("\")
	$myPrompt = "PS: " + $tmp[($tmp.count-2)] + "\" + $tmp[($tmp.count-1)] + ">"
	Write-Host ($myPrompt) -NoNewLine
	Return " "
}

# generates SQL to create and populate a table
# with the file names passed in the pipeline
# e.g. dir * |dir2tb

function dir2tb($tnm = "#x")
{
	begin {
		$i = 0
		"create table $tnm (s varchar(255))"
	}
	process { 
		$fmt = ", ('{0}')";
		if ($i++ % 1000 -eq 0) { $fmt = "insert $tnm values ('{0}')" }
		$fmt -f $_.name
	}
}

function vsp
{
	cd "\users\ecalder\documents\Visual Studio 2012\Projects\"
}

#
# Elite-specific functionality
#

function grepjmlog($s) {
	grep $s $dev\logs\JM.txt |%{$_ -replace ".*\(journalmanager\)\t\w+\t", "" -replace "N/A.*", ""}
}
function jmlog($id) {
	grep "PostIndex: $id\]" $dev\logs\JM.txt |%{
		$_ -replace ".*2013-", "" -replace ",.*\[", " [" -replace "N/A.*", ""
	}
}
function JMDropTTs() {	
	(SQLRead "select name from tempdb.sys.tables where name like 'JM%'").Tables[0] | %{
		SQLExec "drop table tempdb..$($_.name)" > $null
		}
	write-host "JM permanent temp-tables dropped"
	}
function deadlockspids() {
	$x = grepjmlog "deadlock" |%{ if ($_ -match ": (\d+)\]") { $matches[1] } } |sort |unique
	grepjmlog ("\[PostIndex: ({0})\] spid" -f ($x -join "|")) |%{
		if ($_ -match "spid: (\d+),") { $matches[1] }
	} |sort |unique
}
function FmkSearch($s) {
	gci "C:\NextGen_2.7.1.0" *.vb -recurse |%{
		$x = gc $_.FullName | grep $s
		if ($x) { $_.FullName; $x }
		}
	}

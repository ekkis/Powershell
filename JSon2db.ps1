Param($fn, [switch] $show = $false, $srv = "la-dl580g7", $db = "robhill", $tb = "ListDictionary")

#
#	- synopsis -
#	receives a file of jason objects listed one per line, flattens
#	the structure such that arrays and embedded hashes get promoted
#	to the top, and generates SQL or runs the SQL to insert the
#	records into the given database
#
#	- syntax -
#	$show: specifies that the commands to be executed should only be shown
#	$srv: the name of the SQL Server to log into
#	$db: the name of the database in which to operate
#	$tb: the table name to write to
#
#	- metadata -
#	author: erick calder <e@arix.com>
#	department: systems engineering
#	creation date: 5 VIII 13
#

[System.Reflection.Assembly]::LoadWithPartialName("System.Web.Extensions") > $null
$js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
. db; $ss = SQLConnect $srv $db

function q([string] $s) { "'{0}'" -f $s.replace("'", "''") }
function FlattenJSon($o) {
	$ret = @{}
	$o.keys |%{
		$k = $_
		$t = $o[$k].GetType()
		if ($t.IsValueType -or $t.Name -eq "String") {
			$sk = $k; if ($sk -eq "Keys") { $sk = "!Keys" }
			$ret += @{ $sk = $($o[$k]) }
			}
		elseif ($t.IsArray) {
			$i = 1
			$o[$k] |%{ $ret[$k + ($i++)] = $_ }
			}
		else {
			$ret += FlattenJSon($o[$k])
			}
		}
		
	$ret
	}
			
cat $fn |%{
	$cols = $vals = @()
	$h = FlattenJSon($js.DeserializeObject($_))
	$h.keys |%{ $_ = $_.replace("!", ""); $cols += "[$_]"; $vals += $(q $h[$_]) }
	$sql = "insert $tb ({0}) values ({1})" -f ($cols -join ","), ($vals -join ",")
	if ($show) { $sql }
	else { SQLExec $sql > $null }
	}
	


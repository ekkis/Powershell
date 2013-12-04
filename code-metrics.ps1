# For documentation please refer to:
#	http://la-elitedocs.elitecorp.com/wiki/index.php?title=Metrics.ps1
# Needs the Visual Studio Code Metrics PowerTool 10.0 installed
# 	http://www.microsoft.com/en-us/download/details.aspx?id=9422

param([switch] $lib = $false, $filter = "*", $inst = "PMQJMDEV", [switch] $debug = $false, [switch] $sql = $false)
$global:M = "C:\Program Files (x86)\Microsoft Visual Studio 10.0\Team Tools\Static Analysis Tools\FxCop\Metrics.exe"
$global:WebUIBin = "\\la-se-wapi-test\TE_3E_Share\TE_3E_$inst\Inetpub\WebUI\bin"

function global:GetMetrics($f) {
	if ($f.GetType().Name -eq "String") { $f = dir $f }
	$mx = "$($f.BaseName).metrics.xml"
	$cmd = "&'$M' /f:$f /directory:$global:WebUIBin /o:$mx"
	if ($script:debug) { echo $cmd }
	iex $cmd
	
	[xml] $x = cat $mx
	$x.CodeMetricsReport.Targets.Target.Modules.Module.Metrics.Metric
	}
if ($lib) { return }

$rpt = @{}
dir "$WebUIBin\Application\$filter.dll" | %{
	$bn = $_.BaseName
	$x = GetMetrics $_
	if ($bn -match "NextGen\.(\w+)\.") { $objType = $matches[1] }
	else { $objType = "Unknown" }
	[xml] $xot = "<root name='ObjectType' value='$objType' />"
	$x += $xot.root
	$rpt[$bn -replace '.*\.', ''] = $x
	}

$ins = "insert TC..CodeMetrics (Objname, MaintainabilityIndex, CyclomaticComplexity, ClassCoupling, DepthOfInheritance, LOC, ObjType) select "
$dc = "`t"
$fmt = "{0}"
if ($sql) {
	$fmt = "'$fmt'"
	$dc = ","
	}
$rpt.keys |%{
	$s = ($rpt[$_] |?{ $_.Value } |%{ $fmt -f $_.Value }) -join $dc
	$s = ($fmt -f $_ -replace "Base", "") + $dc + $s
	if ($sql) { $s = $ins + $s }
	$s
	}
	


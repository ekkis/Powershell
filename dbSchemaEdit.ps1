param($fn)
$fn = $fn -replace "^\.\\", ""

. .\db.ps1 # include connectivity

[int] $n = 0
$bak = "bak\" + ($fn  -replace "\.([^\.]*?)$", ".*.`$1")
if ((ls $bak |sort LastWriteTime |select -last 1) -match "\.(\d+)\.") {
	$n = $matches[1]
	}
$bak = $bak -replace "\*", ++$n
mv $fn $bak

function GetFlags($prod) {
	$sql = "
		select	TableName
		,		Setup = isnull(IsSetupTablePerSE, 'No')
		,		ConvScript = isnull(IsRefdByConvScripts, 'No')
		,		ConvSetup = isnull(IsRefdByConvSetups, 'No')
		from	main
		where	Product = '$prod'
		"
		
	$t = @{}
	(SQLRead $sql).Tables[0] |%{
		$t[$_.TableName] = @{
			Setup = $_.Setup; 
			ConvScript = $_.ConvScript; 
			ConvSetup = $_.ConvSetup
			}
		}
	return $t
	}

$flags = @{}
$schema2prod = @{}
$db2prod = @{ son_schema = "Ent39"; te_3e_schema = "3E26" }
$prodColour = @{ "Ent39" = "ccccff"; "3E26" = "ccffcc" }
$ss = SQLConnect "la-dl580g7" "TC"

[xml] $x = cat $bak
$x.PreserveWhitespace = $true
$x.Project.Schema |%{
	$prod = $db2prod[$_.CatalogName]
	$schema2prod[$_.name] = $prod
	if (!$flags[$prod]) { $flags[$prod] = GetFlags $prod }
	$_.Table |%{
		if (!$_) { return } # skip empty schemas
		#echo "$prod/$($_.Name)"
		$_.SelectNodes("comment") |% {
			$_.ParentNode.RemoveChild($_) > $null
			}
		if ($flags[$prod][$_.Name].Setup -eq "Yes") {
			$e = $x.CreateElement("comment")
			$e.Set_InnerText(" Setup ")
			$_.AppendChild($e) > $null
			}
		}
	}

$x.Project.Layout |%{
	$_.Entity |%{
		$prod = $schema2prod[$_.Schema]
		$f = $flags[$prod][$_.Name]
		$_.color = switch($true) {
			($f.ConvScript -eq "No" -and $f.ConvSetup -eq "No") { "cccccc" }
			($f.ConvScript -eq "No" -and $f.ConvSetup -eq "Yes") { "ff9999" }
			($f.ConvScript -eq "Yes") { "ff0000" }
			default { "ccCCcc" }
			}
		$_.SelectNodes("callout") |% {
			$_.ParentNode.RemoveChild($_) > $null
			}
		if ($flags[$prod][$_.Name].Setup -eq "yes") {
			$e = $x.CreateElement("callout")
			$e.SetAttribute("x", $_.x - 22)
			$e.SetAttribute("y", $_.y - 28)
			$e.SetAttribute("pointer", "SE")
			$_.AppendChild($e) > $null
			}
		}
	$_.Group |%{
		$_.color = $prodColour[$schema2prod[@($_.Entity)[0].schema]]
		}
	}

$sw = New-Object System.Io.StringWriter 
$xw = New-Object System.Xml.XmlTextWriter($sw) 
$xw.Formatting = [System.Xml.Formatting]::Indented 
$x.WriteContentTo($xw) 
$sw.ToString() |out-file -encoding ascii $fn


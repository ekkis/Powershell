param($Filename = "log.txt", [switch] $Tabs = $true)

$TH = 0; # total hours
$Start = "";
# $Excel = "C:\Program Files (x86)\Microsoft Office\Office12\Excel.exe";

function Pause ($Message="Press any key to continue...") {
	Write-Host -NoNewLine $Message
	$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
	Write-Host ""
	}

echo "" > log.csv
forEach ($s in (Get-Content $Filename)) {
	if ($s -match "\d{1,2}:\d\d (A|P)M") {
		$s = get-date $s
		if ($Start) {
			$d = ((Get-Date $s) - $Start)
			$h = $d.TotalHours;
			$from = get-date -format "t" $Start
			$to = get-date -format "t" $s
			
			if ($Tabs) { $s = "{0}`t{1}`t{2}`t{3}`t{4}" }
			else { $s = "{0} {1} [{2}] = {3}" }
			$s = $s -f $Start.DayOfWeek.toString().Substring(0,3),
				(get-date -format "d" $Start),
				("{0:N2}" -f $h),
				("{0}:{1}" -f $d.Hours, $d.Minutes),
				"$from - $to"

			if ($Tabs) { echo $s >> log.csv }
			else { echo $s }

			$TH += $h;
			$Start = "";
			}
		else {
			$Start = Get-Date $s;
			}
		}
	}

if ($Tabs -and $Excel) { &$Excel log.csv }
else	{
	cat log.csv
	Write-Host "Total hours:" ("{0:N2}" -f $TH)
	#pause
	}


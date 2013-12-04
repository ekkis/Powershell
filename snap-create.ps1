param($env = "dev", $srv = "la-dl580g7", [switch] $force = $false, $db = "")

. db
$ss = SQLConnect $srv "master"
write-host "Connection created [$srv]"
if ($env -ne "dev") { $env = "_$env" }
if ($db -eq "") { $db = "te_3e_pmqjm" + $env }
if ($force) {
	SQLExec @"
		if exists (select * from master.sys.databases where name = '${db}_SNAP')
			DROP DATABASE ${db}_SNAP
"@ > $null
	write-host "Existing snapshot dropped"
	}

write-host "Creating snapshot [$db]..."
SQLExec "exec sp_create_snapshot '$db'" > $null
write-host "Done"


param($db = "te_3e_pmqjmdev", $srv = "la-dl580g7")

. db.ps1
$ss = SQLConnect $srv
echo ("Restoring [{0}.{1}]..." -f $srv, $db)
SQLExec @"
	ALTER DATABASE $db SET SINGLE_USER WITH ROLLBACK IMMEDIATE
	RESTORE DATABASE $db FROM DATABASE_SNAPSHOT = '${db}_snap'
	ALTER DATABASE $db SET MULTI_USER
	use $db
	exec sp_changedbowner 'NT AUTHORITY\SYSTEM'
"@ > $null
echo "Done"
# -- RESTORE DATABASE [TE_3E_NEWPMQ] FROM  DISK = N'L:\Backup\UseCase-10k-Clean.bak' WITH  FILE = 1,  NOUNLOAD,  STATS = 10
#	-- exec sp_dbkill '$db', @restrict = 1


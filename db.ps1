$script:dsn = @{
	"Data Source" = "{0}";
	"Initial Catalog" = "{1}";
	"Integrated Security" = "SSPI";
	"Application Name" = "PSH Client"
	}

function SQLDSN($srv, $db, $dsn = @{}) {
	$script:dsn.Keys |%{ if (!$dsn[$_]) { $dsn[$_] = $script:dsn[$_] } }
	$dsn = $dsn.Keys |%{ "{0}={1}" -f $_, $dsn[$_] }
	$script:dsn.Full = ($dsn -join ";") -f $srv, $db
	return $script:dsn.Full
	}
function SQLConnect($srv, $db = "master", $dsn = @{}) {
	return new-object Data.SqlClient.SqlConnection(SQLDSN $srv $db $dsn)
	}
function SQLConnAgain() {
	return new-object Data.SqlClient.SqlConnection($script:dsn.Full)
	}
function SQLRead($sql, $ss = $script:ss) {
	if (!$ss) { throw "Please initialise a connection" }
	if (test-path variable:script:SQL) { $script:SQL += "$sql`ngo" }
	if ($script:NoExec) { return; }
	try {
		$da = new-object Data.SqlClient.SqlDataAdapter($sql, $ss)
		$set = new-object Data.DataSet
		$da.fill($set) > $null
		return $set
		}
	catch {
		if  ($error[0].Exception.Message -match "closed by the remote host") { # just try it again
			write-warning "Retrying read..."
			return SQLRead $sql $ss
			}
		}
	}
function SQLScalar($sql, $ss = $script:ss) {
	if ($sql -notmatch "select") { $sql = "select $sql" }
	if (test-path variable:script:SQL) { $script:SQL += "$sql`ngo" }
	if ($script:NoExec) { return; }
	$ret = SQLRead $sql $ss
	if ($ret) { $ret = $ret.Tables[0].Rows[0] }
	if ($ret) { $ret = $ret[0] }
	return $ret
	}
function Get-ThreadId {
	[Threading.Thread]::CurrentThread.ManagedThreadId
	}
function SQLExec($sql, $ss = $script:ss, $err = "") {
	#write-warning $ss.ConnectionString
	if (test-path variable:script:SQL) { $script:SQL += "$sql`ngo" }
	if ($script:NoExec) { return; }
	try {
		$cmd = new-object Data.SqlClient.SqlCommand($sql, $ss)
		$cmd.Connection.Open()
		$cmd.CommandTimeout = 0
		$cmd.ExecuteScalar() > $null
		}
	catch [System.Data.SqlClient.SqlException] {
		if ($err) { echo $sql >> $err}
		Throw
		}
	finally {
		$cmd.Connection.Close()
		}
	}
function SQLExecAsync($sql, $dsn) {
	return start-job -ScriptBlock {
		$ss = new-object Data.SqlClient.SqlConnection($args[0])
		$cmd = new-object Data.SqlClient.SqlCommand($args[1], $ss)
		$cmd.Connection.Open()
		# $cmd.BeginExecuteNonQuery() > $null
		return $cmd.ExecuteScalar()
		} -ArgumentList $dsn,$sql
	}

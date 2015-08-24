#
#	Microsoft Translator (Azure)
#	Powershell Script for Visual Studio
#
#	- Synopsis -
#
#	This script uses the Azure translator service to
#	translate resource files within a Visual Studio project
#
#	- Syntax -
#
#	text: accepts a string to translate.  this parameter
#		supercedes all others
#
#	prj: the path of the project root.  if left unspecified,
#		assumes the present working directory
#
#	fn: a file name, array of file names, or directory name
#
#	recurse: a switch that allows the script to recurse through
#		child directories when $fn is given a directory
#
#	lang: allows specifying a language to translate to.  the
#		source language is hard-coded in the configuration
#		section of the script ($SRCLANG).  if not provided
#		the project's web.config file is searched for the
#		[configuration/appSettings/SupportedLanguages] key
#		which consists of a list of space-separated
#		language-locality codes
#
#	force: the script will only generate a translation when
#		either the target language file does not exist, or
#		it exists but its timestamp is older than that of
#		the source file.  this parameter forces a translation
#		regardless of the aforementioned logic
#
#	debug: allows logging; when used in a Visual Studio
#		project, leaves information in the Output log indicating
#		whether a file was translated or was found to be
#		up to date
#
#	quiet: suppresses all non-essential output
#
#	- Exempli Gratia -
#
#	To tranlate the word "whatever" into Danish:
#
#		> MT -text "whatever" -lang "da-DK"
#
#	To translate it into Danish and German:
#
#		> MT -text "whatever" -lang "da-DK de-DE"
#
#	To translate into all the languages specified in the
#	web.config file:
#
#		> MT -text "whatever"
#
#	To translate a given file into Danish:
#
#		> MT [...]\MyFile.resx -lang "da-DK"
#
#	To translate a given file into all the languages
#	specified in the project web.config:
#
#		> MT [...]\MyFile.resx
#
#	Translate an entire directory (ResX) into all
#	languages specified for the project:
#
#		> MT ResX
#
#	Translate a directory and all subdirectories:
#
#		> MT -r ResX
#
#	To show logging output:
#
#		> MT -d -r ResX
#
#	- Integration -
#
#	To use this script:
#
#	1) place it in a given location within
#	your system and add the line below to your project's
#	pre-build event command line (Project/Properties/Build
#	Events).  In the example below, the script has been placed
#	on the root directory of your project.  Please note the
#	command should be entered as a single line.
#
#		Powershell -File "$(ProjectDir)MT.ps1"
#			-r -d "$(ProjectDir)\" ResX
#
#	the last parameter (ResX) specifies the directory that
#	contains your resource files.
#
#	2) Modify the configuration section to contain your
#	Azure client id and secret token
#
#	3) To specify a set of languages to translate into when
#	building your project, include the following in the
#	Web.config file:
#
#	<configuration>
#	  <appSettings>
#	    <add key="SupportedLanguages" value="da-DK de-DE" />
#
#	- Notes -
#
#	The script will traverse the directories requested and
#	compare target file timestamps with the source file e.g.
#	ResX\Index.resx vs. ResX\Index.de-DE.resx; if the target
#	file does not exist or its timestamp is older than the
#	source, it will be translated
#
#	- Marginalia -
#
#	Author: Erick Calder <e@arix.com>
#	Date:	22-VIII-15
#	
#	- Support -
#
#	For support post on the github Issues section.  Patches
#	welcome.
#

Param(
	[switch] $recurse = $false,
	[switch] $debug = $false,
	[switch] $quiet = $false,
	[switch] $force = $false,
	$prj, $fn, $lang,
	[string] $text
)

# --- configuration -----------------------------------------------

$SRCLANG = "en"
$AUTH = @{
	id = '';
	secret = ''
}

# --- support functionality ---------------------------------------

$version = "0.31"

function Coalesce($a, $b) { if ($a -ne $null) { $a } else { $b } }
New-Alias "??" Coalesce -Force

function IfElse($cond, $t, $f) { if ($cond) { $t } else { $b } }
New-Alias "?:" IfElse -Force

Add-Type -AssemblyName System.Web
function urlenc([string] $s) {
	return [System.Web.HttpUtility]::UrlEncode($s)
}

New-Alias "-f" Test-Path -Force

function token() {
	# If ClientId or Client_Secret has special characters,
	# UrlEncode before sending request

	$id = urlenc $AUTH.id
	$secret = urlenc $AUTH.secret

	#Define uri for Azure Data Market

	$Uri = "https://datamarket.accesscontrol.windows.net/v2/OAuth2-13"

	#Define the body of the request

	$body = @(
		"grant_type=client_credentials",
		"client_id=$id",
		"client_secret=$secret",
		"scope=http://api.microsofttranslator.com"
	)
		
	$body = $body -join "&"

	#Define the content type for the request

	$ContentType = "application/x-www-form-urlencoded"

	#Invoke REST method.  This handles the deserialization
	# of the JSON result.  Less effort than invoke-webrequest

	$admAuth = Invoke-RestMethod `
		-Uri $Uri `
		-Body $Body `
		-ContentType $ContentType `
		-Method Post

	#Construct the header value with the access_token just recieved

	return "Bearer " + $admauth.access_token
}

function appSettings() {
	[xml] $x = cat "Web.config"
	return $x.configuration.appSettings.add
}

function lang() {
	if ($lang) { return $lang -split " " }

	$key = "SupportedLanguages"
	return (appSettings |?{ $_.key -eq $key }).Value -split " "
}

function str_chunk([string] $s, $size = 8000) {
	$ret = @()
	while ($s.length -gt 0) {
		if ($s.length -lt $size) { $size = $s.length}
		$ret += $s.substring(0, $size)
		$s = $s.substring($size)
	}
	$ret
}

function tx($text, $to) {
	$ret = ""
	$tx = "http://api.microsofttranslator.com/v2/Http.svc/Translate"
	$auth = @{Authorization = $(token)}

	# the api has a 10241 character limit so we must chunk
	str_chunk $text |%{
		$args = @(
			"text=" + (urlenc $_);
			"from=$SRCLANG";
			"to=$to"
		)
		$uri = $tx + "?" + ($args -join "&")
		try {
			$res = Invoke-RestMethod -Uri $uri -Headers $auth
			$ret += $res.string.'#text'
		}
		catch {
			write-error $_.Exception
			return ""
		}
	}
	$ret
}

function log($s) {
	if ($debug) { write-host $s }
}

function title($s) {
	echo "*`n* $s`n*"
}

$xmldelim = "{MT}"
function xmlget([xml] $x) {
	$ret = @()
	for ($i = 0; $i -lt $x.root.data.length; $i++) {
		$ret += $x.root.data[$i].value
	}
	$ret -join $xmldelim
}

function xmlset([xml] $x, $values) {
	$values = $values -split $xmldelim
	for ($i = 0; $i -lt $x.root.data.length; $i++) {
		$val = $values[$i].trim()
		if (!$val) { $val = "* " + $x.root.data[$i].value + " *" }
		$x.root.data[$i].value = $val
	}
}

# --- main workflow -----------------------------------------------

if (!$quiet) {
	title "Microsoft Translator for Visual Studio (v$version)"
}
if ($debug) {
	if (!$text) {
		echo "[Recurse=ON]"
		echo "[prj=$prj]"
		echo "[dir=$fn]"
	}
}

if (!$prj) { $prj = pwd }
if ($prj) { cd $prj }

if ($text) {
	lang |%{ "${_}: " + (tx $text $_) }
	return
}

# if the path given points to a directory
# expand into an array of the files within
# recursing when requested

if (-f $fn -pathType container) {
	log "expanding directory"
	$r = ?: $recurse "-r" ""
	$fn = iex "dir $r '$fn\*.resx'" |?{
		$_ -notmatch "\...-..\.resx"
	}
}

# translate each file

$fn |%{
	$fn = $_
	if ($fn -is [string]) { $fn = dir $fn }
	[xml] $x = cat -raw $fn
	$values = xmlget $x
	lang |%{
		$xfn = $fn.FullName.replace(".resx", ".${_}.resx")
		$xok = !(-f $xfn)
		if (!$xok) {
			$fnt = $fn.LastWriteTime
			$xft = (dir $xfn)[0].LastWriteTime
			$xok = $fnt -gt $xft
		}
		if (!$xok) { $xok = $force }
		if ($xok) {
			log "Translating: $($xfn.replace($prj, """))"
			xmlset $x (tx $values $_)
			$x.Save($xfn)
		}
		else {
			log "$xfn is up to date"
		}
	}
}

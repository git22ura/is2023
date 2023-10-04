# создает пустую структуру для потока
function EmptyThread() {
	[hashtable]$thread = @{
		feature_path=$null;
		result_path="";
		start_time="";
		stop_time="";
		json_path="";
		id_feature="";
		name_sborka="";
		pid=0;
		failed_pid=0;
		thread_number=0;
		connection_string="";
		connection_string_manager="";
		workspace="";
		va_libraries="";
		url_server1c_debug="";
		node_name="";
		tags="";
		vanessa_epf="";
		ports_range="";
		basename="";
	}
	return $thread
}
function SetThread() {
	Param(
		$feature_path,
		$result_path,
		$json_path,
		$thread,
		$name_sborka,
		$connection_string,
		$connection_string_manager,
		$workspace,
		$va_libraries,
		$url_server1c_debug,
		$node_name,
		$vanessa_epf,
		$ports_range,
		$tags,
		$Optional
	)
	
	$feature_name = Split-Path -Path $feature_path -Leaf
	$thread.id_feature = $feature_name
	$thread.feature_path = $feature_path
	$thread.name_sborka = $name_sborka

	$temp = replacement -text $result_path -var $thread
	$thread.result_path = $temp

	$temp = replacement -text $json_path -var $thread
	$temp = change_doubleslashes -text $temp
	$temp = change_slashes -text $temp
	$thread.json_path = $temp

	$thread.pid=0;
	$thread.failed_pid=0;
	$thread.ports_range=$ports_range
	$thread.workspace=$workspace
	$thread.vanessa_epf=$vanessa_epf
	$thread.url_server1c_debug = $url_server1c_debug
	$thread.node_name = $node_name

	$temp = replacement -text $connection_string -var $thread
	$thread.connection_string = $temp

	if ($connection_string_manager -ne "") {
		$temp = replacement -text $connection_string_manager -var $thread
	} else {
		$temp = ""
	}
	$thread.connection_string_manager = $temp

	$thread.va_libraries = ""
	$arr = $va_libraries -split ","
	foreach ($item in $arr) {
		if ($thread.va_libraries -ne "") {
			$thread.va_libraries = $thread.va_libraries + ","
		}
		$temp = change_doubleslashes -text ($item.trim())
		$thread.va_libraries= $thread.va_libraries + '"' + $temp + '"'
	}

	$thread.tags = ""
	if ($tags -ne "") {
		$arr = $tags -split ","
		$tags = "[]" | ConvertFrom-Json
		foreach ($item in $arr) {

			$temp = change_doubleslashes -text ($item.trim())
			$tags += $temp

		}
		$thread.tags= $tags
	}

	$thread.start_time = Get-Date

}

function SetConstantPropertiesThread() {
	Param(
		$thread,
		$basename,
		$thread_number,
		$Optional
	)
	$thread.basename=$basename
	$thread.thread_number=$thread_number
}
function GetPortsRange() {
	Param(
		$thread_number,
		$CountOfThreads,
		$start_port = 48000,
		$Optional
	)
	if ($CountOfThreads -le 20) {
		$base=100
	} else {
		$base=200
	}
	$ports_per_thread = [math]::Floor($base/$CountOfThreads)
	if ($ports_per_thread -lt 3) {
		$ports_per_thread = 3 # не менее портов на поток
	}
	
	$begin_port = $start_port + ($thread_number-1)*$ports_per_thread
	$end_port = $begin_port + $ports_per_thread - 1
	$ports_range = "$begin_port-$end_port"

	return $ports_range
}


function ResetThread() {
	Param(
		$thread
	)
	$thread.feature_path = ""
}
function IsWorkingThread {
	Param(
		$thread
	)

	if ($thread.feature_path -eq "") {
		return $false
	} else {
		return $true
	}
}

function generate_id() {
	return $id=(Get-Random -Maximum 99).ToString('00')
}

### подстановка в текст, размеченных {variable} соответствующих значений переменных. 
### Например "user: {domain}\{username}" -> "user: HQ\Ivanov"
function replacement() {
	Param(
		[Parameter(Mandatory=$true)]
			[string]$text,
		[Parameter(Mandatory=$true)]
			$var
	)
	$all_matches = ([regex]"\{(.*?)\}").Matches($text)
	Foreach ($match in $all_matches) {
		$temp = $match.ToString()
		$name = ($temp).substring(1, $temp.length-2)
		$text = $text -replace $temp, $var[$name]
	}
	return $text
}

function change_slashes  {
	param (
		[string]$text
	)

	$text = $text -Replace "\\","/"
	return $text
}

function change_doubleslashes  {
	param (
		[string]$text
	)
	$regexA = "(\/+)"
	$text = $text -replace $regexA, '/'
	return $text
}
function CreateReportsFolders {
	param (
		$ReportsPath
	)
	$cat = $ReportsPath + "/log"
	CreateDirIfNotExists -path $cat
	
	$cat = $ReportsPath + "/allure"
	CreateDirIfNotExists -path $cat

	$cat = $ReportsPath + "/cucumber"
	CreateDirIfNotExists -path $cat

	$cat = $ReportsPath + "/junit"
	CreateDirIfNotExists -path $cat

	$cat = $ReportsPath + "/json"
	CreateDirIfNotExists -path $cat

	$cat = $ReportsPath + "/BuildStatus"
	CreateDirIfNotExists -path $cat
}
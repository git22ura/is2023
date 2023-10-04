#requires -Version 2.0
param(
	$PathLog='', # путь к папке лог-файлов
	$EnableLog=$True, # включить или выключить ведение лога
	$LibraryPath="c:\libs\powershell", # откуда подключать общие библиотеки powershell
	$JsonTemplatePath="C:\va\powershell\va_template.json", # шаблон заполнения файла json для va
	$delete_old_log_seconds=1000000, # через сколько секунд удалять старые логи
	$program1C = "C:/Program Files/1cv8/8.3.15.1830/bin/1cv8c.exe", # путь к запускающему файлу 1С
	#$JsonResultTemplatePath="D:/RegressionTests/va/json/{id_feature}", 
	$JsonResultTemplatePath="C:/json/{id_feature}.json", # путь, куда записывается json для запуска очередного потока
	$ResultTemplatePath="C:/reports/BuildStatus/{id_feature}.log", # путь с результатом выполнения билда (используется для обнаружения факта, что поток завершил работу)
	$ReportsPath="C:/reports", # каталог для всех отчетов. Указывается, чтобы создать папки заранее
	
	$vanessa_epf= "c:\va\1.2.034\vanessa-automation.epf", # путь к ванессе
	$ConnectionString = "/S server1:1641/{basename} /NАдминистратор", # строка соединения с базой, с указанием логина-пароля
	$ConnectionStringForClients = "/S server1:1641/{basename} ", # строка соединения с базой для клиентов тестирования
	$workspace = "", # каталог сборки дженкинс
	$va_libraries = "C:\va\1.2.034\features\Libraries", # через запятую список подключаемых библиотек VA
	$url_server1c_debug = "", # урл сервера отладки, требуется для подключения отладчика
	$tags = "", # теги фич через запятую, которые будут запущены (если в фиче нет такого тега - не запускаются). Например, "fast,price"
	$name_sborka = "", # имя сборки для параметра внутрь json VA
	$start_delay1C = 20, # количество секунд между стартом потоков (чтобы успевали TestClient разобраться с портами)
	$failed_pid_attempt = 5, # количество неудачных попыток получить pid процесса (среди всех запущенных процессов процесса потока не обнаружен), после которого процесс считается завершенным с ошибкой
	$kill_client_seanses = $true, # удалять зависшие сеансы TestClient, если таковые остались после запуска

	# каталоги, в которых все найденные фичи будут запущены последовательно в отдельном потоке перед всеми остальными
	# Каждая запись в этом массиве (каталог или фича) будет последовательно запущена в одном потоке
	$DirsWithFeaturesNoDefragmentationOneThread = @(), 

	# каталоги, в которых все найденные фичи (первого уровня) будут запущены в отдельных потоках
	$DirsWithFeatures = @(), 

	# каталоги, для которых НЕ требуется деление на фичи (как правило фич не очень много). 
	# Для каждой записи в этом массиве (каталог или фича) будет запущен один поток
	$DirsWithFeaturesNoDefragmentation = @(),

	# каталоги, которые содержат подкаталоги с фичами. Для каждого подкаталоги будет запущен отдельный поток
	$DirsWithSubcats = @(),

	# имена баз данных, на которых будет проходить тестирование. Первые БД идут на однопоточное тестирование, остальные на многопоточное.
	$DataBasesString = @(),

	# количество баз под однопоточный прогон
	$CountOfOneClientBase = 1,
	
	# количество баз под многопоточный прогон
	$CountOfMultiClientBase = 2, 
	
	# количество потоков на одной многопоточной базе (сколько менеджеров тестирования работают одновременно на одной базе)
	# максимальное количество работающих сеансов вычисляется как (CountOfOneClientBase + CountOfMultiClientBase*ThreadsPerBase)*2. Умножение на 2 - менеджер тетсирования и клиент тетсирования.
	$ThreadsPerBase = 5,

	# после окончания работы потока результат должен быть скопирован в эту папку (на случай падения всего пайплайна)
	$AllureTotalPath = "", 

	# имя узла сборки, на котором происходит запуск (используется для создания индивидуальных папок фич)
	$NodeName = "_local",

	# имя файл (без пути), в который записывается временная диаграмма
	$PlantUmlFilename = "TimingDiagram.puml",

	# путь к запускающему файлу Coverage41C
	$Coverage41Path = "", # c:/sonar/Coverage41C-2.4/bin/Coverage41C
	# путь к файлу покрытия, который формирует Coverage41C
	$GenericCoveragePath = "coverage/genericCoverage.xml",

	# уровень логирования, 0 - ничего не делать, 1 - только в лог, 2 - в лог и write-host
	$loglevel = 1
)



Set-StrictMode -Version 2

$version_script = "1.0"
$global:ScriptDirectory = Split-Path $MyInvocation.MyCommand.Path
$global:job_name = $MyInvocation.MyCommand.Name
$global:PathLog = $PathLog
$global:EnableLog = $EnableLog
$global:date_start = ""
$global:working_threads = 0
$global:Working = $true
$global:running_proc1C = $null
$global:PlantUmlFilename = $PlantUmlFilename

Import-Module "$LibraryPath\file_operations" -force
Import-Module "$LibraryPath\process_operations" -force
Import-Module "$LibraryPath\show_message" -force
Import-Module "$LibraryPath\threads" -force


function DumpCoverage {
	param(
		$thread, # поток
		$ToolPath, # Coverage41Path
		$xmlfile, # путь к файлу сохранения GenericCoveragePath
		$debugurl = "", # url_server1c_debug
		$seconds = 0 # количество секунд на работу сценария
	)
	if (($debugurl -eq "") -and ($ToolPath -eq "")) {
		return 
	}

	# сохранение и обнуленение покрытия
	$ArgumentList = "dump -i " + $thread.basename + " -u " + $debugurl
	$res,$exit_code = StartProcessWithLog -program $ToolPath -ArgumentList $ArgumentList -kodirovka "" -loglevel $loglevel
	if ($exit_code -ne 0) {
		show_message("Не удалось сохранить в файл покрытия <$xmlfile>, код выхода <$exit_code>, лог: $res")
	}
	$ArgumentList = "clean -i " + $thread.basename + " -u " + $debugurl
	$res,$exit_code = StartProcessWithLog -program $ToolPath -ArgumentList $ArgumentList -kodirovka "" -loglevel $loglevel
	if ($exit_code -ne 0) {
		show_message("Не удалось сбросить в ноль файл покрытия <$xmlfile>, код выхода <$exit_code>, лог: $res")
	}
	
	# создать визуализацию для файла покрытия
	$temp = $xmlfile + "_temp"
	Copy-Item -Path $xmlfile -Destination $temp
	
	visualization_coverage -total_file $temp -seconds $seconds -thread $thread

	# обновить общий файл покрытия 
	$total_file = TotalCoverageFileName -filename $xmlfile
	merge_coverage_files -total_file $total_file -new_file $temp

}

# создает xml для визуализации покрытия по файлу покрытия
function visualization_coverage() {
	param(
		$total_file, # оригинальный исходный файл покрытия
		$seconds, # время работы сценария
		$thread # данные потока
	)

	$result_file = [io.path]::GetDirectoryName($thread.json_path) + "/coverage_" + [io.path]::GetFileNameWithoutExtension($thread.json_path) + ".xml"

	if (Test-Path -Path $result_file) { Remove-Item $result_file}
	[System.IO.StreamReader]$tf = [System.IO.File]::Open($total_file, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
	[System.IO.StreamWriter]$rf = [System.IO.File]::Open($result_file, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)


	$begin_file = ""
	$counter = 0 # счетчик покрытых
	$LinesCounter = 0 # счетчик строк кода внутри модуля
	$global_counter = 0 # всего покрыто
	while (-not $tf.EndOfStream){
		$old_line = $tf.ReadLine() 
		if (!(Select-String -SimpleMatch -Pattern 'covered="false"' -InputObject $old_line -Quiet)) {

			if ((Select-String -SimpleMatch -Pattern '<?xml' -InputObject $old_line -Quiet)) {
				# добавляем строку со стилями
				$rf.WriteLine($old_line)
				$rf.WriteLine('<?xml-stylesheet type="text/xsl" href="style.xslt"?>')
				continue
			}

			if ((Select-String -SimpleMatch -Pattern '<file path="' -InputObject $old_line -Quiet)) {
				# сохраним заголовок обрабатываемого модуля и его путь, сброс счетчика
				$begin_file = $old_line
				$counter = 0
				$LinesCounter = 0
				continue
			}
			if ((Select-String -SimpleMatch -Pattern '</coverage>' -InputObject $old_line -Quiet)) {
				# добавим общее количество покрытых и время работы
				$rf.WriteLine("<coveredLines>$global_counter</coveredLines>")
				$rf.WriteLine("<durationSeconds>$seconds</durationSeconds>")
				# и еще данные потока
				$rf.WriteLine("<feature_path>$($thread.feature_path)</feature_path>")
				$rf.WriteLine("<id_feature>$($thread.id_feature)</id_feature>")
			}
			if ((Select-String -SimpleMatch -Pattern 'file>' -InputObject $old_line -Quiet)) {
				if ($begin_file -ne "") {
					# сбрасываем заголовок , не записываем пустое покрытие
					$begin_file = ""
					continue
				} else {
					# добавим строку покрытия
					$rf.WriteLine("	<coveredLines>$counter</coveredLines>")
					$rf.WriteLine("	<totalLines>$LinesCounter</totalLines>")
					$percent = [math]::ceiling($counter/$LinesCounter*100)
					$rf.WriteLine("	<percentCoverage>$percent</percentCoverage>")
					$global_counter = $global_counter + $counter
				}
			}
			if (Select-String -SimpleMatch -Pattern 'covered="true"' -InputObject $old_line -Quiet) {
				# записываем заголовок, если еще не записали
				if ($begin_file -ne "") {
					$rf.WriteLine($begin_file)
					$begin_file = ""
				}
				# инкремент счетчика покрытых и всего
				$counter++
				$LinesCounter++
				# continue # не записываем саму строку покрытия
			}
			$rf.WriteLine($old_line)
		} else {
			# непокрытая строка
			$LinesCounter++
		}
		
	}
	$tf.Close() 
	$rf.Close() 
}

function TotalCoverageFileName() {
	param(
		$filename
	)
	return $filename + "_total"
}

# соединение файлов покрытий (логическое ИЛИ для строк с covered="true")
function merge_coverage_files() {
	param(
		$total_file, # файл c покрытием
		$new_file # добавляемый
	)

	if (!(Test-Path -Path $total_file)) { 
		# если нет файла покрытия, то добавляемый им и становится
		Copy-Item -Path $new_file -Destination $total_file
		return
	}

	$result_file = $total_file + "_temp" # бывший файл

	if (Test-Path -Path $result_file) { Remove-Item $result_file}
	[System.IO.StreamReader]$nf = [System.IO.File]::Open($new_file, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
	[System.IO.StreamReader]$tf = [System.IO.File]::Open($total_file, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
	[System.IO.StreamWriter]$rf = [System.IO.File]::Open($result_file, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)

	while (-not $nf.EndOfStream){
		$new_line = $nf.ReadLine() 
		$old_line = $tf.ReadLine() 
		if (Select-String -SimpleMatch -Pattern 'covered="true"' -InputObject $new_line -Quiet	) {
			$rf.WriteLine($new_line)
		} else {
			$rf.WriteLine($old_line)
		}
	}

	$nf.Close() 
	$tf.Close() 
	$rf.Close()

	Remove-Item $total_file
	rename-item -path $result_file -newname $total_file

}

function add_plantuml_event {
	param(
		$track, # номер потока
		$feature = "" # имя фичи/путь фичи
	)
	# $dt = [datetime]::parseexact($time_start, 'yyyy-MM-dd_HH-mm-ss', $null)
	$dt = [datetime]::parseexact($global:date_start, 'yyyy-MM-dd_HH-mm-ss', $null)
	$now = Get-Date
	$hms = $now.ToString("HH:mm:ss")
	$seconds = [int](New-TimeSpan -Start $dt -End $now).TotalSeconds
	$result_file = $global:PathLog + "/" + $global:PlantUmlFilename
	[System.IO.StreamWriter]$rf = [System.IO.File]::Open($result_file, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
	$rf.WriteLine("@$seconds")
	if ($feature -eq "") {
		$rf.WriteLine("T$track is {hidden}")
		$rf.WriteLine("note top of T$track : $hms")
	} else {
		$safe_feature = safe_text -text $feature
		$rf.WriteLine("T$track is $safe_feature")
		$rf.WriteLine("note top of T$track : $hms")
	}
	$rf.Close() 
}

function safe_text {
	param(
		$text # текст
	)
	$text = $text -Replace ";","_"
	return $text
}
function save_footer_plantuml {
	param(
	)
	$result_file = $global:PathLog + "/" + $global:PlantUmlFilename
	[System.IO.StreamWriter]$rf = [System.IO.File]::Open($result_file, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
	$rf.WriteLine("@enduml")
	$rf.Close() 
}
function save_header_plantuml {
	param(
		$ar_threads, # массив с потоками
		$ar_threads_oneclient # массив с потоками
	)
	$result_file = $global:PathLog + "/" + $global:PlantUmlFilename
	if (Test-Path -Path $result_file) { Remove-Item $result_file}
	[System.IO.StreamWriter]$rf = [System.IO.File]::Open($result_file, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)

	$rf.WriteLine("@startuml")
	# стили для дорожек
	$rf.WriteLine("<style>")
	$rf.WriteLine("timingDiagram {")
	for ($i = 0; $i -lt ($ar_threads_oneclient.count + $ar_threads.count); $i++) {
		$color = colors -number $i
		$rf.WriteLine(".C$($i+1) { BackGroundColor $color }")
	}
	$rf.WriteLine("}")
	$rf.WriteLine("</style>")
	# scale дефолтный
	$rf.WriteLine("scale 60 as 50 pixels")
	# вывод дорожек. сначала однопоточные
	for ($i = 0; $i -lt $ar_threads_oneclient.count; $i++) {
		$base = $ar_threads_oneclient[$i].basename
		$postfix = $base.Substring($base.Length - 4)
		$colorindex = colors -number $postfix -onlyindex $true
		$new_line = "concise ""$base, O$($i+1)"" as T$($i+1) <<C$colorindex>>"
		$rf.WriteLine($new_line)
	}

	# вывод дорожек будет "сгруппирован" по базам, а не по номерам потоков
	$arr = New-Object System.Collections.Generic.List[System.Object]
	for ($i = 0; $i -lt $ar_threads.count; $i++) {
		$base = $ar_threads[$i].basename
		$postfix = $base.Substring($base.Length - 4)
		$colorindex = colors -number $postfix -onlyindex $true
		$new_line = "concise ""$base, M$($i+1)"" as T$($i+1 + $ar_threads_oneclient.count) <<C$colorindex>>"
		$arr.Add($new_line)
	}
	$arr = $arr | Sort-Object
	for ($i = 0; $i -lt $arr.count; $i++) {
		$rf.WriteLine($arr[$i])
	}

	# время отсчета один раз явно укажем
	$dt = [datetime]::parseexact($global:date_start, 'yyyy-MM-dd_HH-mm-ss', $null)
	$hms = $dt.ToString("HH:mm:ss")
	$rf.WriteLine("@0")
	$rf.WriteLine("T1 is {hidden}")
	$rf.WriteLine("note top of T1: $hms")
	$rf.Close() 
}

function colors {
	param(
		[string]$number,
		[bool]$onlyindex
	)
	$arr = @("#CCE5FF", "#FFB266", "#FFCCE5", "#FFFF66", "#B2FF66", "#99FFFF",  "#FFE5CC", "#CCFFCC", "#E5CCFF", "#66FFB2" )
	
	$index = [int]($number.Substring($number.Length - 1, 1))
	if ($onlyindex) {
		return $index
	} else {
		return $arr[$index]
	}
}
function total_duration {
	$time_start = $date_start
	$dt = [datetime]::parseexact($time_start, 'yyyy-MM-dd_HH-mm-ss', $null)
	$now = Get-Date
	return (New-TimeSpan -Start $dt -End $now)
}
function total_minutes {
	return [int](total_duration).TotalMinutes
}
function total_seconds {
	return [int](total_duration).TotalSeconds
}
# проверяет фичи каталога на наличие тега. 
# Если такой тег есть функция возвращает список файлов-фич, но только у которых нет тега @ExportScenarios
# Если тегов в фичах не найдено (или они не заполнены) - возвращается false
function files_or_folder_with_tag() {
	param(
		$subcatalog_local, # путь к папке или путь к конкретной фиче
		$tag = "" # искомый тег или теги, например "@one_thread", "fast,price". Теги могут быть без @, но поиск осуществляется с @
	)
	if ($tag -eq "") {
		return $false # нет тегов - нечего искать
	}
	$arr_tags = $tag -split "," # если теги через запятую переданы

	if (Test-Path -Path $subcatalog_local -PathType Container) {
		$features_local = Get-ChildItem -Path $subcatalog_local -Filter "*.feature"
	} else {
		$features_local = New-Object System.Collections.Generic.List[System.Object]
		$temp = Get-Item -Path $subcatalog_local
		$features_local.Add($temp)
	}
	
	$tag_finded=$false
	$files_w_onethread = New-Object System.Collections.Generic.List[System.Object]

	
	foreach ($file in $features_local) {
		
		$myOptions = [System.Text.RegularExpressions.RegexOptions]'MultiLine, IgnoreCase'
		$text = Get-Content -Path $file.FullName -Encoding UTF8 -Raw

		foreach ($item in $arr_tags) {
			$temp = $item.trim()
			if ($temp.substring(0,1) -ne "@") {
				$temp = "@"+$temp
			}
			if ([regex]::IsMatch($text,"^$temp",$myOptions)) {
				$tag_finded = $true
			}
		}


		if (![regex]::IsMatch($text,"^@ExportScenario",$myOptions)) {
			$filename = change_slashes -text $file.FullName
			$files_w_onethread.Add($filename)
		}
	}
	
	if ($tag_finded) {
		return $files_w_onethread
	} else {
		return $false
	}
}

function check_work {
	param (
		$CurrentThread,
		$files_to_check,
		$start_new_thread
	)
	$was_remove = $false
	$busy = $false

	# проверить, что поток свободен, нагрузить его работой
	if ($CurrentThread.feature_path) {
		# занят
		$global:Working = $true
		$global:working_threads++
		$busy = $true
	} else {
		# пустой
		if ($files_to_check -eq $true) {
			$dlina = 0
		} else {
			$dlina = $files_to_check.Count
		}
		
		if ($dlina -gt 0) {
			
			# задержка между потоками, если за этот обход уже стартовали поток
			if ($start_new_thread) {
				Start-Sleep $start_delay1C
			}

			# получение диапазона портов для данного потока
			$ports_range = GetPortsRange -thread_number $CurrentThread.thread_number -CountOfThreads $CountOfThreads

			# начальные настройки потока
			SetThread -thread $CurrentThread -feature_path $files_to_check[0] -json_path $JsonResultTemplatePath -result_path $ResultTemplatePath -name_sborka $name_sborka -workspace $workspace -va_libraries $va_libraries -ports_range $ports_range -url_server1c_debug $url_server1c_debug -connection_string $ConnectionStringForClients -connection_string_manager $ConnectionString -tags $tags -node_name $NodeName
			$was_remove = $true

			# сформировать файл vbparams.json для конкретной фичи, подменить все подстановки
			$filename = $CurrentThread.json_path
			$content = get-content -path $JsonTemplatePath -Encoding UTF8 -Raw
			$content = replacement -text $content -var $CurrentThread
			if ($CurrentThread.tags -ne "") {
				$settings = $content | ConvertFrom-Json
				# теги есть, значит нужна настройка с тегами
				$settings | Add-Member -Type NoteProperty -Name 'СписокТеговОтбор' -value $CurrentThread.tags
				$content = $settings | ConvertTo-Json -depth 32
			}
			save_file -filename $filename -content $content

			
			# запустить поток

			$FeaturePath = $CurrentThread.feature_path
			show_message("Запускаем фичу <$FeaturePath>, $($CurrentThread.id_feature)")

			$ArgumentList = "ENTERPRISE " + $CurrentThread.connection_string_manager + " /Execute " + '"'+$vanessa_epf + '"  /TESTMANAGER /C"StartFeaturePlayer;ClearStepsCache;VBParams='+ $CurrentThread.JSON_path+'"' 


			$pid_process,$stdout_path,$stderr_path = StartProcessNoWait -program $program1C -ArgumentList $ArgumentList 
			show_message("Запущен поток №$($CurrentThread.thread_number), pid <$pid_process>, для <$FeaturePath> ")
			$CurrentThread.pid = $pid_process
			add_plantuml_event -track $CurrentThread.thread_number -feature $CurrentThread.id_feature

			$global:working_threads++
			$start_new_thread = $true
			$busy = $true
			
			$global:Working = $true

		}
	}

	# проверить, что поток закончил работу, освободить его
	if (!$start_new_thread -and (IsWorkingThread -thread $CurrentThread)) {
		if ($CurrentThread.start_time -ne "") {
			$now = Get-Date
			$difftime = New-TimeSpan -Start $CurrentThread.start_time -End $now
			$worktime = [int]($difftime.TotalMinutes)
			$seconds = [int]($difftime.TotalSeconds)
		} else {
			$worktime = "-"
			$seconds = 0
		}
		if ($CurrentThread.feature_path -and (Test-Path -Path $CurrentThread.result_path)) {
			show_message("Поток №$($CurrentThread.thread_number) для <$($CurrentThread.feature_path)> закончил работу. Время работы <$worktime> минут")
			add_plantuml_event -track $CurrentThread.thread_number
			
			# todo/ этот путь еще есть в .json - надо забирать из одного места
			
			DumpCoverage -thread $CurrentThread -ToolPath $Coverage41Path -xmlfile $GenericCoveragePath -debugurl $url_server1c_debug -seconds $seconds

			ResetThread -thread $CurrentThread

			$busy = $false
		}

		# проверить, что поток 1С все еще работает
		$proc = $global:running_proc1C | Where-Object {$_.IDProcess -eq $($CurrentThread.pid)}
		if (!$proc) {
			$CurrentThread.failed_pid++
		} else {
			$CurrentThread.failed_pid=0
		}
		if ($CurrentThread.failed_pid -ge $failed_pid_attempt) {
			show_message("Поток №$($CurrentThread.thread_number) для <$($CurrentThread.feature_path)> не обнаружен. Похоже, что он завершен аварийно (pid $($CurrentThread.pid)). Время работы <$worktime> минут")
			add_plantuml_event -track $CurrentThread.thread_number
			
			DumpCoverage -thread $CurrentThread -ToolPath $Coverage41Path -xmlfile $GenericCoveragePath -debugurl $url_server1c_debug -seconds $seconds

			ResetThread -thread $CurrentThread
			$busy = $false
		}
	}
	return  $start_new_thread, $busy, $was_remove
}






init_logs -tPathLog $PathLog -tScriptDirectory $ScriptDirectory

$params = ($PSBoundParameters | out-string) 
show_message("Параметры запуска: <$params>") 
show_message("Версия скрипта:<$version_script>")
show_message("job_name:<$job_name>")
show_message("EnableLog:<$EnableLog>")
show_message("delete_old_log_seconds:<$delete_old_log_seconds>")
show_message("PathLog:<$PathLog>")

DeleteOldLogs

$workspace = change_slashes -text $workspace
$ResultTemplatePath = change_slashes -text $ResultTemplatePath

show_message("Создание каталогов под отчеты")
CreateReportsFolders -ReportsPath $ReportsPath

$DataBases = New-Object System.Collections.Generic.List[System.Object]
$arr = $DataBasesString -split ","
foreach ($db in $arr) {
	if ($db -eq "") { continue	}
	$DataBases.Add($db)
}

# проверка соответствия заданных параметров потоков и общего числа баз
if ($DataBases.Count -ne ($CountOfOneClientBase + $CountOfMultiClientBase)) {
	show_message("Количество имен баз <$($DataBases.Count)> не соответствует количеству однопоточных <$CountOfOneClientBase> + многопоточных баз <$CountOfMultiClientBase>, требуется корректировка параметров запуска скрипта.")
	exit_with_code 1 $loglevel
}

# общее количество потоков
$CountOfThreads = $CountOfOneClientBase + $CountOfMultiClientBase*$ThreadsPerBase



# фичи для однопоточного прогона
$files_to_checkOneThread = New-Object System.Collections.Generic.List[System.Object]
foreach ($catalog in $DirsWithFeaturesNoDefragmentationOneThread)
{
	$catalog = $catalog -replace "'",""
	if ($catalog -eq "") { continue	}

	# добавление подкаталогов
	if (Test-Path -path $catalog -PathType Container) {

		$featuresCat = Get-ChildItem -Path $catalog
		foreach ($subcatalog in $featuresCat) {
	
			# проверяет фичи каталога на наличие тега @one_thread. (тег, означающий необходимость отдельного запуска фичи, в отдельном потоке)
			# Если такой тег есть хотя бы в одном файле, то все фичи папки будут рассматриваться как требующие отдельного запуска
			# В этом случае функция возвращает список файлов-фич, но только у которых нет тега @ExportScenarios
			# Если тегов не найдено - возвращается изначальное имя папки
			$ret = files_or_folder_with_tag -subcatalog $subcatalog.FullName -tag "@one_thread"
			if ($ret -eq $false) {
				# можно всю папку целиком, но надо учесть теги
				$filename = change_slashes -text $subcatalog.FullName
				if ($tags -eq "") {
					# тегов нет - берем все
					$files_to_checkOneThread.Add($filename)
				} else {
					$ret = files_or_folder_with_tag -subcatalog $filename -tag $tags
					if ($ret -eq $false) {
						# в подкаталоге нет фич с такими тегами - не добавляем
					} else {
						$files_to_checkOneThread.Add($filename)
					}
				}

			} else {
				# есть однопотоковые фичи, учтем теги
				foreach ($one_feature in $ret) {
					if ($tags -eq "") {
						# тегов нет - берем все
						$files_to_checkOneThread.Add($one_feature)
					} else {
						$ret = files_or_folder_with_tag -subcatalog $one_feature -tag $tags
						if ($ret -eq $false) {
							# фича не содержит тега - не добавляем
						} else {
							$files_to_checkOneThread.Add($one_feature)
						}
					}
					
				}
			}
		}
	}
	# получение отдельной фичи, если указывает на файл
	if (Test-Path -path $catalog -PathType Leaf) {
		$filename = change_slashes -text $catalog
		$files_to_checkOneThread.Add($filename)
	}
	
}

$files_to_check = New-Object System.Collections.Generic.List[System.Object]
foreach ($catalog in $DirsWithSubcats)
{
	if ($catalog -eq "") { continue	}
	# получение подкаталогов
	if (Test-Path -path $catalog -PathType Container) {
		$featuresCat = Get-ChildItem -Path $catalog -Directory
		foreach ($subcat in $featuresCat) {
			$filename = change_slashes -text $subcat.FullName
			if ($tags -eq "") {
				# тегов нет - берем все
				$files_to_check.Add($filename)
			} else {
				$ret = files_or_folder_with_tag -subcatalog $filename -tag $tags
				if ($ret -eq $false) {
					# в подкаталоге нет фич с такими тегами - не добавляем
				} else {
					$files_to_check.Add($filename)
				}
			}
		}
	}
}

foreach ($catalog in $DirsWithFeatures)
{
	if ($catalog -eq "") { continue	}
	# получение всех фич из каждого каталога
	if (Test-Path -path $catalog -PathType Container) {
		$features = Get-ChildItem -Path $catalog -Filter "*.feature"
		foreach ($file in $features) {
			$filename = change_slashes -text $file.FullName
			if ($tags -eq "") {
				# тегов нет - берем все
				$files_to_check.Add($filename)
			} else {
				$ret = files_or_folder_with_tag -subcatalog $filename -tag $tags
				if ($ret -eq $false) {
					# у фичи нет таких тегов - не добавляем
				} else {
					$files_to_check.Add($filename)
				}
			}
		}
	}
	# получение отдельной фичи, если указывает на файл
	if (Test-Path -path $catalog -PathType Leaf) {
		$filename = change_slashes -text $catalog
		$files_to_check.Add($filename)
	}
}
foreach ($catalog in $DirsWithFeaturesNoDefragmentation)
{
	if ($catalog -eq "") { continue	}
	if (Test-Path -path $catalog ) {
		$filename = change_slashes -text $catalog
		if ($tags -eq "") {
			# тегов нет - берем все
			$files_to_check.Add($filename)
		} else {
			$ret = files_or_folder_with_tag -subcatalog $filename -tag $tags
			if ($ret -eq $false) {
				# у фичи нет таких тегов - не добавляем
			} else {
				$files_to_check.Add($filename)
			}
		}
	}
}

# Если количество баз для многопоточного запуска ноль - значит все делаем в один поток, на соот-щих базах
if ($CountOfMultiClientBase -eq 0) {
	$files_to_checkOneThread.AddRange($files_to_check)
	$files_to_check.Clear()
}

$features_count = $files_to_check.count
show_message("Каталогов и фич в очереди на многопоточный запуск: <$features_count>")
$featuresOneThread_count = $files_to_checkOneThread.count
show_message("Каталогов и фич в очереди на однопоточный запуск: <$featuresOneThread_count>")


# тут надо получить все базы для однопоточного и многопоточного прогона в разные переменные

show_message("Инициализация потоков")

$threads_oneclient = New-Object System.Collections.Generic.List[System.Object]
for ($i=0;$i -lt $CountOfOneClientBase;$i++) { 
	$a = EmptyThread
	SetConstantPropertiesThread -thread $a -basename $DataBases[$i] -thread_number ($i+1)
	$threads_oneclient.add($a) 
}

# запуск потоков будет осуществляться с добавлением комплекта в каждую базу и только во второй заход и последующий проход будет добавлена многопоточность
$threads = New-Object System.Collections.Generic.List[System.Object]
for ($j=0;$j -lt $ThreadsPerBase;$j++) { 
	for ($i=$CountOfOneClientBase;$i -lt ($CountOfOneClientBase + $CountOfMultiClientBase);$i++) { 
		$a = EmptyThread
		SetConstantPropertiesThread -thread $a -basename $DataBases[$i] -thread_number ($i+1+$j*$CountOfMultiClientBase)
		$threads.add($a)
	}
}

save_header_plantuml -ar_threads $threads -ar_threads_oneclient $threads_oneclient


show_message("$($threads_oneclient.count)")
show_message("$($threads.count)")

show_message("Последовательный запуск всех фич")
$global:Working = $true
$old_minutes = 0

while ($global:Working -eq $true) {

	$global:Working = $false
	$global:working_threads = 0
	$start_new_thread = $false

	# получение всех запущенных процессов 
	$global:running_proc1C = Get-WmiObject -class Win32_PerfFormattedData_PerfProc_Process  | Select-Object @{Name="IDProcess"; Expression = {$_.IDProcess}}
	show_message("Число фич ожидающих своей очереди в один поток: <$($files_to_checkOneThread.Count)>, многопоточно: <$($files_to_check.Count)>")
	

	for ($indexThread=0;$indexThread -lt $CountOfOneClientBase;$indexThread++) 
	{
		
		$CurrentThread = $threads_oneclient[$indexThread]
		$dlina = $files_to_checkOneThread.Count

		$start_new_thread, $busy, $was_remove = check_work -CurrentThread $CurrentThread -files_to_check $files_to_checkOneThread   -start_new_thread $start_new_thread
		if ($was_remove) { $files_to_checkOneThread.RemoveAt(0); }
		# // если текущие $threads_oneclient сейчас работает, то ничего не делаем,
		# // иначе смотрим на очередь одного потока 
		# //   если очередь не пустая, добавляем задание для освободившегося потока
		# //   иначе добавляем еще $ThreadsPerBase в $threads, $CountOfThreads++
		if (!$busy -and $dlina -eq 0) {

			# // этот код для того, чтобы использовать однопоточную базу после того как она освободиться для целей многопоточного тестирования.
			# // минус подхода, что база будет чем-то заполнена и количество потоков увеличиться
			# for ($i=0;$i -lt $ThreadsPerBase;$i++) { 
			# 	$threads.add($CurrentThread) 
			# 	# /// сразу надо зафиксировать потоки и базы, ибо на 1 базу может быть не более Х потоков
			# }
		}
	}
	
	foreach ($CurrentThread in $threads) {
		$start_new_thread, $busy, $was_remove = check_work -CurrentThread $CurrentThread -files_to_check $files_to_check   -start_new_thread $start_new_thread
		if ($was_remove) { $files_to_check.RemoveAt(0) }
	}
	
	show_message("Число работающих потоков: <$global:working_threads>")

	# показываем текущие работающие потоки каждые две минуты (для понимания что упало при просмотре лога пайплайна)
	$working_threads_text = total_minutes
	if (($old_minutes + 2) -lt $working_threads_text) {
		$old_minutes = $working_threads_text
		show_message ("Работают:")
		foreach ($CurrentThread in $threads_oneclient) {
			if (IsWorkingThread -thread $CurrentThread) {
				show_message("однопоточный: $($CurrentThread.feature_path) (pid=$($CurrentThread.pid)), база $($CurrentThread.connection_string)")
			}
		}		
		foreach ($CurrentThread in $threads) {
			if (IsWorkingThread -thread $CurrentThread) {
				show_message("многопоточный: $($CurrentThread.feature_path) (pid=$($CurrentThread.pid)), база $($CurrentThread.connection_string)")
			}
		}
	}
	
	# подождать пока что-то не изменится
	if ($global:Working -eq $true) {
		Start-Sleep 10
	}

}

if ($kill_client_seanses) {
	
	$running_Client1C = Get-WmiObject Win32_Process -Filter "name = '1cv8c.exe'"  | Select-Object -Property processID,CommandLine
	$proc = $running_Client1C | Where-Object {$_.CommandLine -match "/testclient"} 
	
	foreach ($thread in $threads) {
		$client = $proc | Where-Object {$_.CommandLine -match $thread.Connection_String} 
		if ($client) {
			show_message ("Зависший клиент $client")
		}
	}
	foreach ($thread in $threads_oneclient) {
		$client = $proc | Where-Object {$_.CommandLine -match $thread.Connection_String} 
		if ($client) {
			show_message ("Зависший клиент $client")
		}
	}
	
}
save_footer_plantuml


$worktime = total_minutes
show_message ("Скрипт проработал: $worktime минут.")
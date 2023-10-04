function save_file($filename, $content, $level = 2)
{
	try {
		log_message -message "Записываю файл <$filename>" -level $level
		# тестирование необходимо, если путь к файлу содержит много каталогов, которые еще не существуют. Out-file -force не справляется
		if (!(Test-Path $filename )) {
				$result = new-item -force -path $filename -value "" -type file
		}
		Out-File -FilePath $filename -InputObject $content -Encoding "UTF8" -Force
		return $true
	}
	Catch {
		log_message -message "Не удалось записать файл <$filename>" -level $level
		return $false
	}
}

function CreateDirIfNotExists($path) {
	If (!(test-path -Path $path)) {
			$results = New-Item -Path $path -ItemType "directory"
			add_to_logfile -ob $results
	}
}

function CreateLogFolderIfNeed() {
	if ($EnableLog -eq "1") {
			CreateDirIfNotExists($PathLog)
	}
}

function ClearDir() {
	Param(
		[Parameter(Mandatory=$true)]
		[string]$path = "dir", # директория, внутри которой все хотим очистить
		$level = 2 # уровень логирования
		
	)
	Process {
		log_message -message "Очистка папки <$path>" -level $level
		$results = Get-ChildItem $path -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction:SilentlyContinue
		add_to_logfile -ob $results
	}
}
function DeleteDir() {
	Param(
		[Parameter(Mandatory=$true)]
		[string]$path = "dir", # директория, которую удаляем
		$level = 2 # уровень логирования
	)
	Process {
			log_message -message "Удаление папки <$path>" -level $level
		$results = Remove-Item -Force -Recurse -Path $path -ErrorAction:SilentlyContinue
			add_to_logfile -ob $results
	}
}

function ChangeAttributesToNormal()
{
	Param(
		[Parameter(Mandatory=$true)]
		[string]$path = "dir" # директория, все аттрибуты файлов и подпапок в которой будут изменены на простой тип
		
	)
	Process {
		add_to_logfile -ob "Приводим аттрибуты к Normal в <$path>"
		Get-ChildItem $path -Recurse | foreach { $_.Attributes = 'Normal' }
	}
}

function exit_with_code($code,$level=2)
{
	process {
		log_message -message "--закончили работу с кодом <$code>--" -level $level
		exit $code
	}
}

function format_file_log()
{
	return "dd.MM.yyyy HH:mm:ss"
}

function show_message($message)
{

	process {
		$format = format_file_log
		$date = Get-Date -Format $format
		if ($message)
		{
			if ($message.GetType().Name -eq "string")
			{
				$itogo = $date + ": "+$message
				Write-Host( $itogo )
				add_to_logfile -ob $itogo
			}
			else
			{
				Write-Host( $date )
				add_to_logfile -ob $date
				Write-Host( $message )
				add_to_logfile -ob $message
			}
		}
		else
		{
			#empty
				Write-Host( $date )
				add_to_logfile -ob $date
		}
	}
}

function log_message()
{
	Param(
		$message, # сообщение/объект для логирования
		$level=2 # уровень логирования, 0 - ничего не делать, 1 - только в лог, 2 - в лог и write-host
	)
	process {
		if ($level -gt 0) {
			$format = format_file_log
			$date = Get-Date -Format $format
			if ($message)
			{
				if ($message.GetType().Name -eq "string")
				{
					$itogo = $date + ": "+$message
					if ($level -eq 2) { Write-Host( $itogo ) }
					add_to_logfile -ob $itogo
				}
				else
				{
					if ($level -eq 2) { Write-Host( $date ) }
					add_to_logfile -ob $date
					if ($level -eq 2) { Write-Host( $message ) }
					add_to_logfile -ob $message
				}
			}
			else
			{
				#empty
				if ($level -eq 2) { Write-Host( $date ) }
				add_to_logfile -ob $date
			}	
		}
	}
}
function add_to_logfile($ob)
{
	if ($EnableLog)
	{
		CreateLogFolder
		$filename = $PathLog + "\log_" + $job_name + "_"+ $date_start + ".txt"
		Out-File -FilePath $filename -Append -InputObject $ob
	}
}

function CreateLogFolder()
{
	if ($EnableLog)
	{
		if (!(test-path -Path $PathLog))
		{
			$result = New-Item -Path $PathLog -ItemType "directory"
		}
	}
}

function DeleteOldLogs($level=2)
{
	if ($EnableLog) {
		if ($delete_old_log_seconds -gt 0) {
			If (test-path $PathLog) {
				$limit = (Get-Date).AddSeconds(-$delete_old_log_seconds)
				$format = format_file_log
				$date_string = Get-Date -date $limit -Format $format
				log_message -level $level -message "удаляем лог файлы ранее <$date_string>"

				$reg_string = "^log_$job_name"

				# удаление по рег.выражению
				Get-ChildItem -Path $PathLog -Recurse -Force `
					| Where-Object { !$_.PSIsContainer -and $_.CreationTime -lt $limit -and $_.Name -Match $reg_string} `
					| Remove-Item -Force

			}
		}
	}
}

function init_logs ([String]$tPathLog,[String]$tScriptDirectory) 
{
	if ($tPathLog) {
		$PathLog = $tPathLog 
	} else {
		$PathLog = $tScriptDirectory+"/log"
		
	}
	Set-Variable -Name "PathLog" -value $PathLog -scope global
	$date_start = Get-Date -format "yyyy-MM-dd_HH-mm-ss"
	Set-Variable -Name "date_start" -value $date_start -scope global

}
function StartProcessWithLogAndWindow($program, $ArgumentList, $kodirovka, $level=2) {
	StartProcessWithLogUni -program $program -ArgumentList $ArgumentList -kodirovka $kodirovka -NoNewWindow $false -level $level
}
function StartProcessWithLog($program, $ArgumentList, $kodirovka, $level) {
	StartProcessWithLogUni -program $program -ArgumentList $ArgumentList -kodirovka $kodirovka -NoNewWindow $true -level $level
}

function StartProcessWithLogUni($program, $ArgumentList, $kodirovka, $NoNewWindow,$level=2) {
	Process {
			$a = GenerateFilename("err")
			$stdErrLog = $PathLog + "/" + $a
			$a = GenerateFilename("out")
			$stdOutLog = $PathLog + "/" + $a
			log_message -message "Стартуем процесс: <$program -ArgumentList $ArgumentList>" -level $level
			if ($NoNewWindow) {
				$process = Start-Process $program -ArgumentList $ArgumentList -Wait -PassThru -RedirectStandardError $stdErrLog -RedirectStandardOutput $stdOutLog -NoNewWindow
			} else {
				$process = Start-Process $program -ArgumentList $ArgumentList -Wait -PassThru -RedirectStandardError $stdErrLog -RedirectStandardOutput $stdOutLog 
			}

			$ExitCode = $process.ExitCode
			if ($kodirovka -eq "")
			{
					$results = Get-Content $stdErrLog, $stdOutLog 
			}
			else 
			{
					$results = Get-Content $stdErrLog, $stdOutLog | ConvertTo-Encoding $kodirovka "windows-1251"
			}

			Remove-Item -Force -Recurse -Path $stdErrLog -ErrorAction:SilentlyContinue
			Remove-Item -Force -Recurse -Path $stdOutLog -ErrorAction:SilentlyContinue
			return $results,$ExitCode
	}
}

function StartProcess($program, $ArgumentList, $kodirovka, $level=2 ) {
	Process {
			$a = GenerateFilename("err")
			$stdErrLog = $PathLog + "/" + $a
			$a = GenerateFilename("out")
			$stdOutLog = $PathLog + "/" + $a
			log_message -message "Запускаем процесс: <$program -ArgumentList $ArgumentList>" -level $level
			$res = Start-Process $program -ArgumentList $ArgumentList -Wait -RedirectStandardError $stdErrLog -RedirectStandardOutput $stdOutLog -NoNewWindow
			$success = $res.ExitCode
			if ($kodirovka -eq "")
			{
					$logs = Get-Content $stdErrLog, $stdOutLog 
			}
			else 
			{
					$logs = Get-Content $stdErrLog, $stdOutLog | ConvertTo-Encoding $kodirovka "windows-1251"
			}

			Remove-Item -Force -Recurse -Path $stdErrLog -ErrorAction:SilentlyContinue
			Remove-Item -Force -Recurse -Path $stdOutLog -ErrorAction:SilentlyContinue
			
			return $success,$logs,$res
	}
}
function StartProcessNoWait($program, $ArgumentList, $level=2) {
	Process {
			log_message -message "Запускаем процесс: <$program -ArgumentList $ArgumentList>" -level $level
			$res = Start-Process $program -ArgumentList $ArgumentList -PassThru -NoNewWindow
			$pid_process = $res.ID
			return $pid_process,$stdOutLog,$stdErrLog
	}
}


function GenerateFilename($dop)
{
	$a = -join ((65..90) + (97..122) | Get-Random -Count 5 | % {[char]$_})
	$a = "temp"+$a+$dop+".txt"
	return $a
}

function ConvertTo-Encoding ([string]$From, [string]$To){
	Begin{
			$encFrom = [System.Text.Encoding]::GetEncoding($from)
			$encTo = [System.Text.Encoding]::GetEncoding($to)
	}
	Process{
			$bytes = $encTo.GetBytes($_)
			$bytes = [System.Text.Encoding]::Convert($encFrom, $encTo, $bytes)
			$encTo.GetString($bytes)
	}
}


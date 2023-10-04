chcp 65001
SET WE_path=C:/Program Files/windows_exporter
mkdir "%WE_path%"
xcopy config.yml "%WE_path%"
msiexec /i distribs\windows_exporter-0.21.0-amd64.msi EXTRA_FLAGS="--config.file=""%WE_path%/config.yml"""
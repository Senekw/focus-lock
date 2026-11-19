# One-line installer for Windows (paste into PowerShell):
#   irm https://raw.githubusercontent.com/Senekw/focus-lock/main/windows/get.ps1 | iex
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tmp = Join-Path $env:TEMP ('FocusLock-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $tmp | Out-Null
Write-Host 'Downloading Focus Lock...'
Invoke-WebRequest -UseBasicParsing 'https://github.com/Senekw/focus-lock/releases/latest/download/FocusLock-Windows.zip' -OutFile "$tmp\f.zip"
Expand-Archive "$tmp\f.zip" $tmp
Write-Host 'Click Yes on the Windows prompt to finish installing.'
Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$tmp\FocusLock-Windows\install.ps1`""

# Installs Focus Lock for Windows. Run through 'Install Focus Lock.cmd' (it asks for admin rights).
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$dst = Join-Path $env:ProgramFiles 'FocusLock'
$data = Join-Path $env:ProgramData 'FocusLock'
$req = Join-Path $env:PUBLIC 'FocusLock'
$list = Join-Path $src 'blocklist.txt'
if (-not (Test-Path $list)) { $list = Join-Path (Split-Path $src) 'blocklist.txt' }
if (-not (Test-Path $list)) { throw 'blocklist.txt not found next to install.ps1' }

Stop-ScheduledTask -TaskName FocusLock -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $dst, $data, $req | Out-Null
Copy-Item (Join-Path $src 'FocusLock.ps1') $dst -Force
Copy-Item (Join-Path $src 'uninstall.ps1') $dst -Force
Copy-Item $list (Join-Path $dst 'blocklist.txt') -Force
$ver = Join-Path $src 'version.txt'
if (-not (Test-Path $ver)) { $ver = Join-Path (Split-Path $src) 'VERSION' }
if (Test-Path $ver) { Set-Content (Join-Path $dst 'version.txt') ("$(Get-Content $ver -Raw)".Trim()) -NoNewline }
Get-ChildItem $dst | Unblock-File
# SYSTEM and Administrators: full. Users: read only (state) / modify (request folder).
& icacls $data /inheritance:r /grant '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
& icacls $req /grant '*S-1-5-32-545:(OI)(CI)M' | Out-Null

$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script = Join-Path $dst 'FocusLock.ps1'
# The loop restarts the daemon script after it updates itself.
$action = New-ScheduledTaskAction -Execute $ps -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"while (1) { & '$script' -Mode daemon; Start-Sleep 2 }`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName FocusLock -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName FocusLock

$shell = New-Object -ComObject WScript.Shell
$links = @(
    (Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'Focus Lock.lnk'),
    (Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Focus Lock.lnk')
)
foreach ($l in $links) {
    $s = $shell.CreateShortcut($l)
    $s.TargetPath = $ps
    $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Mode ui"
    $s.IconLocation = (Join-Path $env:SystemRoot 'System32\shell32.dll') + ',47'
    $s.WindowStyle = 7
    $s.Save()
}
Write-Host ''
Write-Host 'Focus Lock is installed. Open it from the desktop shortcut or the Start menu.'
Write-Host 'Tip: right-click the shortcut and choose "Pin to taskbar".'
Write-Host 'You can close this window.'
Start-Process $ps -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Mode ui"

# Removes Focus Lock for Windows. Run through 'Uninstall Focus Lock.cmd' (it asks for admin rights).
$ErrorActionPreference = 'SilentlyContinue'
Stop-ScheduledTask -TaskName FocusLock
Unregister-ScheduledTask -TaskName FocusLock -Confirm:$false
Start-Sleep -Seconds 1
$list = Join-Path $env:ProgramFiles 'FocusLock\blocklist.txt'
$domains = @(Get-Content $list | Where-Object { $_ -match '^domain\s+(\S+)' } | ForEach-Object { ($_ -split '\s+')[1].ToLower() })
foreach ($k in 'HKLM:\SOFTWARE\Policies\Google\Chrome\URLBlocklist', 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\URLBlocklist', 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave\URLBlocklist') {
    if (-not (Test-Path $k)) { continue }
    $item = Get-Item $k; $keep = @(); $i = 1
    while ($null -ne $item.GetValue("$i")) { $v = [string]$item.GetValue("$i"); if ($domains -notcontains $v) { $keep += $v }; $i++ }
    Remove-Item $k -Force
    if ($keep.Count) { New-Item $k -Force | Out-Null; for ($i = 0; $i -lt $keep.Count; $i++) { New-ItemProperty -Path $k -Name "$($i + 1)" -Value $keep[$i] -PropertyType String -Force | Out-Null } }
}
$hp = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$out = New-Object System.Collections.Generic.List[string]; $skip = $false
foreach ($l in ([IO.File]::ReadAllText($hp) -split "`r?`n")) {
    if ($l.StartsWith('# >>> FocusLock')) { $skip = $true; continue }
    if ($l.StartsWith('# <<< FocusLock')) { $skip = $false; continue }
    if (-not $skip) { $out.Add($l) }
}
[IO.File]::WriteAllText($hp, (($out -join "`r`n").TrimEnd() + "`r`n"), (New-Object Text.UTF8Encoding($false)))
& ipconfig /flushdns | Out-Null
Remove-Item (Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'Focus Lock.lnk') -Force
Remove-Item (Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Focus Lock.lnk') -Force
Remove-Item (Join-Path $env:ProgramData 'FocusLock'), (Join-Path $env:PUBLIC 'FocusLock') -Recurse -Force
Set-Location $env:TEMP
Remove-Item (Join-Path $env:ProgramFiles 'FocusLock') -Recurse -Force
Write-Host 'Focus Lock removed.'

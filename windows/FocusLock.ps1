# Focus Lock for Windows. One script, two modes:
#   -Mode daemon  runs as SYSTEM (scheduled task): owns lock state, hosts file, browser policies, quits blocked apps
#   -Mode ui      the window with the toggle; it only writes a request file
param([ValidateSet('ui', 'daemon')][string]$Mode = 'ui')
$ErrorActionPreference = 'SilentlyContinue'
$Root = Join-Path $env:ProgramData 'FocusLock'
$StatePath = Join-Path $Root 'state.json'
$ListPath = Join-Path $PSScriptRoot 'blocklist.txt'
$ReqDir = Join-Path $env:PUBLIC 'FocusLock'
$ReqPath = Join-Path $ReqDir 'request'
$UiPath = Join-Path $env:APPDATA 'FocusLock\ui.json'   # remembers whether the small window is showing

function Now { [double]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) / 1000 }
function Read-State {
    try { Get-Content -Raw -ErrorAction Stop $StatePath | ConvertFrom-Json } catch { $null }
}
function Read-List {
    $b = @{ domains = @(); hosts = @(); apps = @() }
    foreach ($line in @(Get-Content $ListPath)) {
        $t = "$line".Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $p = $t -split '\s+', 2
        if ($p.Count -lt 2) { continue }
        $v = $p[1].Trim()
        if ($p[0] -eq 'app') { $b.apps += $v }
        elseif ($v -match '^[A-Za-z0-9.-]+$') {
            if ($p[0] -eq 'domain') { $b.domains += $v.ToLower() }
            elseif ($p[0] -eq 'host') { $b.hosts += $v.ToLower() }
        }
    }
    $b
}

# ---------------------------------------------------------------- daemon
function Set-Hosts($on, $list) {
    $hp = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    $cur = ''
    try { $cur = [IO.File]::ReadAllText($hp) } catch {}
    $keep = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($l in ($cur -split "`r?`n")) {
        if ($l.StartsWith('# >>> FocusLock')) { $skip = $true; continue }
        if ($l.StartsWith('# <<< FocusLock')) { $skip = $false; continue }
        if (-not $skip) { $keep.Add($l) }
    }
    while ($keep.Count -gt 0 -and $keep[$keep.Count - 1] -eq '') { $keep.RemoveAt($keep.Count - 1) }
    $out = ($keep -join "`r`n") + "`r`n"
    if ($on) {
        $names = @()
        foreach ($d in $list.domains) { $names += $d; $names += "www.$d" }
        $names += $list.hosts
        $names = $names | Select-Object -Unique
        $lines = foreach ($n in $names) { "0.0.0.0 $n"; ":: $n" }
        $out += "# >>> FocusLock (managed, do not edit)`r`n" + ($lines -join "`r`n") + "`r`n# <<< FocusLock`r`n"
    }
    if ($out -ne $cur) {
        try {
            [IO.File]::WriteAllText($hp, $out, (New-Object Text.UTF8Encoding($false)))
            & ipconfig /flushdns | Out-Null
        } catch {}
    }
}
$PolKeys = @(
    'HKLM:\SOFTWARE\Policies\Google\Chrome\URLBlocklist',
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge\URLBlocklist',
    'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave\URLBlocklist'
)
function Set-Policies($on, $domains) {
    # Chromium reads list policies from values named 1, 2, 3... Keep anything that is not ours.
    foreach ($k in $PolKeys) {
        $have = @(); $others = @()
        if (Test-Path $k) {
            $item = Get-Item $k
            $i = 1
            while ($null -ne $item.GetValue("$i")) { $have += [string]$item.GetValue("$i"); $i++ }
            foreach ($v in $have) { if ($domains -notcontains $v) { $others += $v } }
        }
        $want = @($others)
        if ($on) { $want += $domains }
        if (($want -join '|') -eq ($have -join '|')) { continue }
        if ($want.Count -eq 0) { Remove-Item $k -Force; continue }
        New-Item $k -Force | Out-Null
        for ($i = 0; $i -lt $want.Count; $i++) {
            New-ItemProperty -Path $k -Name "$($i + 1)" -Value $want[$i] -PropertyType String -Force | Out-Null
        }
    }
}
function Stop-BlockedApps($apps) {
    foreach ($a in $apps) {
        $n = $a -replace '\.exe$', ''
        Get-Process -Name $n, ($n -replace ' ', '') | Stop-Process -Force
    }
}
# Installs the newest GitHub release over this copy. Lock state and blocklist are kept.
function Update-Self {
    try {
        $ProgressPreference = 'SilentlyContinue'
        $cur = '0'
        $vf = Join-Path $PSScriptRoot 'version.txt'
        if (Test-Path $vf) { $cur = "$(Get-Content $vf -Raw)".Trim() }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $rel = Invoke-RestMethod -TimeoutSec 20 -ErrorAction Stop 'https://api.github.com/repos/Senekw/focus-lock/releases/latest'
        $tag = "$($rel.tag_name)".TrimStart('v')
        if ($tag -notmatch '^\d+(\.\d+)*$' -or $cur -notmatch '^\d+(\.\d+)*$') { return $false }
        $a = $tag; if ($a -notmatch '\.') { $a = "$a.0" }
        $b = $cur; if ($b -notmatch '\.') { $b = "$b.0" }
        if ([version]$a -le [version]$b) { return $false }
        $tmp = Join-Path $Root 'update'
        Remove-Item $tmp -Recurse -Force
        New-Item -ItemType Directory -Force $tmp | Out-Null
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop "https://github.com/Senekw/focus-lock/releases/download/v$tag/FocusLock-Windows.zip" -OutFile "$tmp\f.zip"
        Expand-Archive "$tmp\f.zip" $tmp -Force -ErrorAction Stop
        $new = Join-Path $tmp 'FocusLock-Windows'
        $errs = $null
        [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $new 'FocusLock.ps1'), [ref]$null, [ref]$errs)
        if ($errs.Count -gt 0) { return $false }
        if ("$(Get-Content (Join-Path $new 'version.txt') -Raw)".Trim() -ne $tag) { return $false }
        foreach ($f in 'FocusLock.ps1', 'uninstall.ps1', 'version.txt') {
            Copy-Item (Join-Path $new $f) (Join-Path $PSScriptRoot $f) -Force -ErrorAction Stop
        }
        Remove-Item $tmp -Recurse -Force
        return $true
    } catch { return $false }
}
function Start-Daemon {
    New-Item -ItemType Directory -Force $Root | Out-Null
    $st = @{ on = $false; lockedUntil = 0.0; since = 0.0; heartbeat = 0.0 }
    $old = Read-State
    if ($old) { $st.on = [bool]$old.on; $st.lockedUntil = [double]$old.lockedUntil; $st.since = [double]$old.since }
    $tick = 0
    while ($true) {
        # shortly after start, then about every 6 hours. Returning lets the task's loop start the new script.
        if ($tick % 10800 -eq 5) { if (Update-Self) { return } }
        $tick++
        if (Test-Path $ReqPath) {
            $r = ''
            try { if ((Get-Item $ReqPath).Length -lt 64) { $r = [IO.File]::ReadAllText($ReqPath) } } catch {}
            # an empty read means the file is still being written: leave it for the next pass
            if ($r.Trim()) { Remove-Item $ReqPath -Force }
            $p = $r.Trim() -split '\s+'
            if ($p[0] -eq 'on') {
                $secs = 0.0
                if ($p.Count -gt 1) { [void][double]::TryParse($p[1], [ref]$secs) }
                $secs = [Math]::Min([Math]::Max($secs, 0), 12 * 3600)
                if (-not $st.on) { $st.on = $true; $st.since = Now }
                if ($secs -gt 0) { $st.lockedUntil = [Math]::Max($st.lockedUntil, (Now) + $secs) }
            } elseif ($p[0] -eq 'off' -and (Now) -ge $st.lockedUntil) {
                $st.on = $false; $st.lockedUntil = 0.0
            }
        }
        $st.heartbeat = Now
        $tmp = "$StatePath.tmp"
        [IO.File]::WriteAllText($tmp, ($st | ConvertTo-Json -Compress))
        Move-Item $tmp $StatePath -Force
        $list = Read-List
        Set-Hosts $st.on $list
        Set-Policies $st.on $list.domains
        if ($st.on) { Stop-BlockedApps $list.apps }
        Start-Sleep -Seconds 2
    }
}

# ---------------------------------------------------------------- ui
function Start-UI {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
    $cream = [Drawing.Color]::FromArgb(246, 241, 231)
    $ink = [Drawing.Color]::FromArgb(18, 15, 13)
    $muted = [Drawing.Color]::FromArgb(33, 29, 25)
    $clay = [Drawing.Color]::FromArgb(194, 87, 51)
    $moss = [Drawing.Color]::FromArgb(64, 107, 77)
    $white = [Drawing.Color]::White

    $form = New-Object Windows.Forms.Form
    $form.Text = 'Focus Lock'; $form.ClientSize = New-Object Drawing.Size(420, 440)
    $form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false
    $form.StartPosition = 'CenterScreen'; $form.BackColor = $cream
    # See-through background with solid letters: the main form's tan is keyed out, and a
    # separate half-transparent tan form sits right behind it.
    $form.TransparencyKey = $cream
    $back = New-Object Windows.Forms.Form
    $back.FormBorderStyle = 'None'; $back.ShowInTaskbar = $false; $back.StartPosition = 'Manual'
    $back.BackColor = $cream; $back.Opacity = 0.82
    function Sync-Back {
        $p = $form.PointToScreen([Drawing.Point]::Empty)
        $back.Bounds = New-Object Drawing.Rectangle($p.X, $p.Y, $form.ClientSize.Width, $form.ClientSize.Height)
        $back.Visible = $form.WindowState -ne 'Minimized'
    }
    $form.Add_Shown({ Sync-Back })
    $form.Add_LocationChanged({ Sync-Back })
    $form.Add_Resize({ Sync-Back })
    $form.Add_FormClosed({ $back.Close() })
    # The X button shrinks to the small always-on-top window. From the small window it really closes.
    $form.Add_FormClosing({
        if (-not $ui.mini -and $_.CloseReason -eq 'UserClosing') { $_.Cancel = $true; Set-Mini $true }
    })
    $ui = @{ mini = $false }
    try { $ui.mini = [bool](Get-Content -Raw -ErrorAction Stop $UiPath | ConvertFrom-Json).mini } catch {}
    function Save-Ui {
        New-Item -ItemType Directory -Force (Split-Path $UiPath) | Out-Null
        [IO.File]::WriteAllText($UiPath, ($ui | ConvertTo-Json -Compress))
    }
    $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon((Join-Path $env:SystemRoot 'System32\Narrator.exe'))
    try { $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon((Join-Path $env:SystemRoot 'System32\credwiz.exe')) } catch {}

    function New-Label($y, $h, $font, $color) {
        $l = New-Object Windows.Forms.Label
        $l.SetBounds(20, $y, 380, $h); $l.TextAlign = 'MiddleCenter'; $l.Font = $font; $l.ForeColor = $color
        $form.Controls.Add($l); $l
    }
    $head = New-Label 36 20 (New-Object Drawing.Font('Segoe UI', 8, [Drawing.FontStyle]::Bold)) $muted
    $head.Text = 'F O C U S   L O C K'
    $title = New-Label 70 50 (New-Object Drawing.Font('Georgia', 22)) $ink
    $clock = New-Label 130 50 (New-Object Drawing.Font('Segoe UI', 24, [Drawing.FontStyle]::Bold)) $clay
    $sub = New-Label 240 40 (New-Object Drawing.Font('Segoe UI', 9.5)) $muted
    $foot = New-Label 380 44 (New-Object Drawing.Font('Segoe UI', 8)) $muted

    # Top right: shrink to the small always-on-top window.
    $tip = New-Object Windows.Forms.ToolTip
    $toMini = New-Object Windows.Forms.Button
    $toMini.SetBounds(346, 8, 54, 22); $toMini.Text = 'Mini'; $toMini.FlatStyle = 'Flat'; $toMini.FlatAppearance.BorderSize = 0
    $toMini.BackColor = $white; $toMini.ForeColor = $ink; $toMini.TabStop = $false
    $toMini.Font = New-Object Drawing.Font('Segoe UI', 8, [Drawing.FontStyle]::Bold)
    $tip.SetToolTip($toMini, 'Shrink to a small window that stays on top')
    $toMini.Add_Click({ Set-Mini $true })
    $form.Controls.Add($toMini)

    # The small window: timer, end time, and a button back to the full window.
    $miniPanel = New-Object Windows.Forms.Panel
    $miniPanel.SetBounds(0, 0, 240, 52); $miniPanel.Visible = $false
    $miniClock = New-Object Windows.Forms.Label
    $miniClock.SetBounds(10, 3, 160, 28); $miniClock.TextAlign = 'MiddleLeft'; $miniClock.ForeColor = $ink
    $miniClock.Font = New-Object Drawing.Font('Segoe UI', 13, [Drawing.FontStyle]::Bold)
    $miniEnd = New-Object Windows.Forms.Label
    $miniEnd.SetBounds(12, 30, 160, 18); $miniEnd.TextAlign = 'MiddleLeft'; $miniEnd.ForeColor = $muted
    $miniEnd.Font = New-Object Drawing.Font('Segoe UI', 8)
    $miniOpen = New-Object Windows.Forms.Button
    $miniOpen.SetBounds(178, 11, 52, 30); $miniOpen.Text = 'Open'; $miniOpen.FlatStyle = 'Flat'; $miniOpen.FlatAppearance.BorderSize = 0
    $miniOpen.BackColor = $white; $miniOpen.ForeColor = $ink
    $miniOpen.Font = New-Object Drawing.Font('Segoe UI', 8, [Drawing.FontStyle]::Bold)
    $miniOpen.Add_Click({ Set-Mini $false })
    $miniPanel.Controls.AddRange(@($miniClock, $miniEnd, $miniOpen))
    $form.Controls.Add($miniPanel)
    function Set-Mini($on) {
        $ui.mini = [bool]$on
        $miniPanel.Visible = $ui.mini
        if ($ui.mini) { $miniPanel.BringToFront(); $form.ClientSize = New-Object Drawing.Size(240, 52) }
        else { $form.ClientSize = New-Object Drawing.Size(420, 440) }
        $form.TopMost = $ui.mini; $back.TopMost = $ui.mini
        Sync-Back; Save-Ui
    }
    $script:minutes = 60
    $script:action = ''
    $durs = @(@(30, '30m'), @(60, '1h'), @(120, '2h'), @(180, '3h'), @(0, 'No timer'))
    $durButtons = @()
    $x = 22
    foreach ($d in $durs) {
        $b = New-Object Windows.Forms.Button
        $w = 62; if ($d[0] -eq 0) { $w = 100 }
        $b.SetBounds($x, 150, $w, 34); $x += $w + 7
        $b.Text = $d[1]; $b.Tag = $d[0]; $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
        $b.Font = New-Object Drawing.Font('Segoe UI', 9.5)
        $b.Add_Click({ $script:minutes = [int]$this.Tag; Update-View })
        $form.Controls.Add($b); $durButtons += $b
    }
    $main = New-Object Windows.Forms.Button
    $main.SetBounds(40, 300, 340, 48); $main.FlatStyle = 'Flat'; $main.FlatAppearance.BorderSize = 0
    $main.Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold); $main.ForeColor = $white
    $form.Controls.Add($main)

    function Send-Request($text) {
        New-Item -ItemType Directory -Force $ReqDir | Out-Null
        $tmp = Join-Path $ReqDir ('request.' + [Guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($tmp, $text)
        Move-Item $tmp $ReqPath -Force
    }
    $addLabel = New-Object Windows.Forms.Label
    $addLabel.SetBounds(34, 300, 80, 40); $addLabel.TextAlign = 'MiddleLeft'; $addLabel.Text = 'Add time'
    $addLabel.Font = New-Object Drawing.Font('Segoe UI', 9.5); $addLabel.ForeColor = $muted
    $form.Controls.Add($addLabel)
    $addButtons = @()
    $x = 116
    foreach ($d in @(@(15, '+15m'), @(30, '+30m'), @(60, '+1h'), @(120, '+2h'))) {
        $b = New-Object Windows.Forms.Button
        $b.SetBounds($x, 302, 62, 36); $x += 69
        $b.Text = $d[1]; $b.Tag = $d[0]; $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
        $b.BackColor = $white; $b.ForeColor = $ink
        $b.Font = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold)
        $b.Add_Click({ Send-Request "on $([int]$script:remaining + [int]$this.Tag * 60)" })
        $form.Controls.Add($b); $addButtons += $b
    }
    $main.Add_Click({
        switch ($script:action) {
            'lock' { Send-Request "on $($script:minutes * 60)" }
            'off' { Send-Request 'off' }
        }
    })

    $d = (Read-List).domains
    if ($d.Count -gt 5) { $foot.Text = 'Blocks ' + (($d | Select-Object -First 5) -join ', ') + " and $($d.Count - 5) more" }
    else { $foot.Text = 'Blocks ' + ($d -join ', ') }

    function Get-EndText($unix) {
        # local time zone and the user's own 12/24-hour setting
        $d = [DateTimeOffset]::FromUnixTimeSeconds([long]$unix).LocalDateTime
        $time = $d.ToString('t')
        if ($d.Date -eq (Get-Date).Date) { return $time }
        if ($d.Date -eq (Get-Date).Date.AddDays(1)) { return "$time tomorrow" }
        return $d.ToString('g')
    }
    function Update-View {
        $st = Read-State
        $t = Now
        $installed = $st -and (($t - [double]$st.heartbeat) -lt 15)
        $on = $installed -and [bool]$st.on
        $script:remaining = 0
        if ($on) { $script:remaining = [Math]::Max(0, [double]$st.lockedUntil - $t) }
        foreach ($b in $durButtons) {
            $b.Visible = $installed -and -not $on
            if ([int]$b.Tag -eq $script:minutes) { $b.BackColor = $moss; $b.ForeColor = $white } else { $b.BackColor = $white; $b.ForeColor = $ink }
        }
        $clock.Visible = $on -and $script:remaining -gt 0
        $adding = $on -and $script:remaining -gt 0
        $main.Visible = $installed -and -not $adding
        $addLabel.Visible = $adding
        foreach ($b in $addButtons) { $b.Visible = $adding }
        if (-not $installed) {
            $title.Text = 'Not installed'; $sub.Text = 'Run the Focus Lock installer first.'; $script:action = ''
        } elseif (-not $on) {
            $title.Text = 'Ready to lock in?'
            if ($script:minutes -eq 0) { $sub.Text = 'You can turn it off any time.' } else { $sub.Text = "Ends at $(Get-EndText ($t + $script:minutes * 60)). Once on, it cannot be turned off until then." }
            $main.Text = 'Lock in'; $main.BackColor = $clay; $main.ForeColor = $white; $script:action = 'lock'
        } elseif ($script:remaining -gt 0) {
            $title.Text = 'Locked in'
            $s = [int][Math]::Ceiling($script:remaining)
            $clock.Text = '{0}:{1:00}:{2:00}' -f [Math]::Floor($s / 3600), ([Math]::Floor($s / 60) % 60), ($s % 60)
            $sub.Text = "Ends at $(Get-EndText ([double]$st.lockedUntil)). No turning it off until then."
            $script:action = ''
        } else {
            $title.Text = 'Locked in'; $sub.Text = 'Timer done. Blocking stays on until you turn it off.'
            $main.Text = 'Turn off'; $main.BackColor = $ink; $main.ForeColor = $white; $script:action = 'off'
        }
        $miniEnd.Text = ''
        if (-not $installed) { $miniClock.Text = 'Not installed' }
        elseif (-not $on) { $miniClock.Text = 'Not locked' }
        elseif ($script:remaining -gt 0) { $miniClock.Text = $clock.Text; $miniEnd.Text = "Ends at $(Get-EndText ([double]$st.lockedUntil))" }
        else { $miniClock.Text = 'Locked in' }
    }
    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 500; $timer.Add_Tick({ Update-View }); $timer.Start()
    Update-View
    $back.Show()
    if ($ui.mini) { Set-Mini $true }
    [void]$form.ShowDialog($back)
}

if ($Mode -eq 'daemon') { Start-Daemon } else { Start-UI }

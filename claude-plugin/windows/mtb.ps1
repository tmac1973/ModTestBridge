# mtb for PowerShell on Windows: the ModTestBridge client. Does what bin/mtb (bash) does, without Git Bash, curl or Python.
# Run it through bin\mtb.cmd, which works from cmd and PowerShell whatever the execution policy. See `mtb help`.
#
# Settings come from the environment, else .mtb (searched upward from the current directory), else
# %USERPROFILE%\.config\mtb\config (KEY=value lines). See README.md, "Configuring mtb".
# Works in Windows PowerShell 5.1 and PowerShell 7. Keep this file ASCII: 5.1 reads BOM-less files as ANSI.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$Usage = @'
mtb status                          game state (starting/menu/loading/world), world, character, position
mtb cmd "<console command>"         run a console command, print what it printed
mtb run "<command>" "<text>" [s]    run a command, then wait (default 600 s) for a new log line containing text
mtb log [from] [contains]           log lines from line N (0-based), optionally only those containing text
mtb mark                            the log's current line number (pass it to mtb log to read what came after)
mtb tail [n] [contains]             the last n (default 40) log lines, optionally only those containing text
mtb wait-log "<text>" [s]           wait (default 600 s) for a new log line containing text; prints it
mtb wait-world [s]                  wait (default 300 s) until a character is in a world
mtb quit                            save, log out and quit the game
mtb start [world] [character]       back up the saves, launch the game straight into the world (autostart)
mtb restart [world] [character]     quit if running, back up, launch, wait until in the world
mtb backup [world] [character]      copy the character and world saves (only while the game isn't running)
mtb profiles                        mod-manager profiles that have ModTestBridge installed
mtb doctor                          show what mtb found (profile, token, launch, saves) and whether the game answers
'@

# Fail stops with a message and an exit code; the top level prints it. Is-Fail tells these from PowerShell's own errors.
function Fail([string]$message, [int]$code = 1) {
    $e = New-Object Exception $message
    $e.Data['mtb'] = $code
    throw $e
}
function Is-Fail($err) { $err.Exception.Data.Contains('mtb') }
function Warn([string]$message) { [Console]::Error.WriteLine($message) }

# --- settings --------------------------------------------------------------------------------------------------------

$SettingNames = 'MTB_PROFILE', 'MTB_PROFILE_DIR', 'MTB_PORT', 'MTB_WORLD', 'MTB_CHARACTER', 'MTB_TIMEOUT', 'MTB_LAUNCH',
                'MTB_STEAM', 'MTB_GAME_PATTERN', 'MTB_SAVES_DIRS', 'MTB_CLOUD_DIRS', 'MTB_KEEP_BACKUPS'
$S = @{}

# KEY=value lines, as the bash mtb sources them: # comments, optional quotes, optional "export".
function Read-SettingsFile([string]$path) {
    foreach ($line in Get-Content -LiteralPath $path) {
        $line = $line.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        if ($line -notmatch '^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { continue }
        $key = $Matches[1]; $value = $Matches[2].Trim()
        if ($value -match '^"([^"]*)"' -or $value -match "^'([^']*)'") { $value = $Matches[1] }
        else { $value = ($value -replace '\s+#.*$', '').Trim() }
        $script:S[$key] = $value
    }
}

function Get-HomeDir { if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME } }

function Load-Settings {
    $configHome = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path (Get-HomeDir) '.config' }
    $f = Join-Path (Join-Path $configHome 'mtb') 'config'
    if (Test-Path -LiteralPath $f -PathType Leaf) { Read-SettingsFile $f }
    $d = (Get-Location).ProviderPath
    while ($d) {
        $f = Join-Path $d '.mtb'
        if (Test-Path -LiteralPath $f -PathType Leaf) { Read-SettingsFile $f; break }
        $d = Split-Path -Parent $d
    }
    foreach ($name in $SettingNames) {
        $v = [Environment]::GetEnvironmentVariable($name)
        if ($null -ne $v) { $script:S[$name] = $v }
    }
}

function Setting([string]$name, [string]$default = '') {
    if ($S.ContainsKey($name) -and $S[$name] -ne '') { $S[$name] } else { $default }
}

# MTB_SAVES_DIRS and MTB_CLOUD_DIRS: ';'-separated here (':' would split C:\...).
function Split-Dirs([string]$value) { $value -split ';' | Where-Object { $_ -ne '' } }

Load-Settings
$App = 892970
$Port = Setting 'MTB_PORT' '7811'
$Url = "http://127.0.0.1:$Port"

# --- where things are ------------------------------------------------------------------------------------------------

# Mod-manager profile folders (Gale, r2modman).
function Get-ManagerDirs {
    if (-not $env:APPDATA) { return }
    foreach ($d in (Join-Path $env:APPDATA 'com.kesomannen.gale\valheim\profiles'),
                   (Join-Path $env:APPDATA 'r2modmanPlus-local\Valheim\profiles')) {
        if (Test-Path -LiteralPath $d -PathType Container) { $d }
    }
}

function Test-Bridge([string]$dir) {
    $plugins = Join-Path $dir 'BepInEx\plugins'
    if (Test-Path -LiteralPath (Join-Path $plugins 'ModTestBridge.dll')) { return $true }
    if (-not (Test-Path -LiteralPath $plugins -PathType Container)) { return $false }
    foreach ($sub in Get-ChildItem -LiteralPath $plugins -Directory) {
        if (Test-Path -LiteralPath (Join-Path $sub.FullName 'ModTestBridge.dll')) { return $true }
    }
    $false
}

function Get-BridgeProfiles {
    foreach ($m in Get-ManagerDirs) {
        foreach ($p in Get-ChildItem -LiteralPath $m -Directory) { if (Test-Bridge $p.FullName) { $p.FullName } }
    }
}

$ProfileDirCache = $null
function Get-ProfileDir {
    if ($script:ProfileDirCache) { return $script:ProfileDirCache }
    $dir = Setting 'MTB_PROFILE_DIR'
    if (-not $dir) {
        $name = Setting 'MTB_PROFILE'
        if ($name) {
            foreach ($m in Get-ManagerDirs) {
                if (Test-Path -LiteralPath (Join-Path $m $name) -PathType Container) { $dir = Join-Path $m $name; break }
            }
            if (-not $dir) { Fail "no mod-manager profile named $name (set MTB_PROFILE_DIR to the folder holding BepInEx)" }
        } else {
            $found = @(Get-BridgeProfiles)
            if ($found.Count -eq 0) { Fail 'no profile with ModTestBridge installed found; set MTB_PROFILE or MTB_PROFILE_DIR' }
            if ($found.Count -gt 1) { Fail ("several profiles have ModTestBridge; set MTB_PROFILE to one of:`n" + ($found -join "`n")) }
            $dir = $found[0]
        }
    }
    $script:ProfileDirCache = $dir
    $dir
}

function Get-SteamRoot {
    try {
        $p = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction Stop).SteamPath
        if ($p) { return ($p -replace '/', '\') }
    } catch { }
    if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Steam' }
}

# Folders that hold characters_local\ and worlds_local\ (and, for older saves, characters\ and worlds\).
function Get-SavesDirs {
    $v = Setting 'MTB_SAVES_DIRS'
    if ($v) { return Split-Dirs $v }
    Join-Path (Get-HomeDir) 'AppData\LocalLow\IronGate\Valheim'
}

# Steam Cloud save folders (userdata\<account>\892970\remote).
function Get-CloudDirs {
    $v = Setting 'MTB_CLOUD_DIRS'
    if ($v) { return Split-Dirs $v }
    $root = Get-SteamRoot
    if (-not $root) { return }
    $userdata = Join-Path $root 'userdata'
    if (-not (Test-Path -LiteralPath $userdata -PathType Container)) { return }
    foreach ($u in Get-ChildItem -LiteralPath $userdata -Directory) {
        $d = Join-Path $u.FullName "$App\remote"
        if (Test-Path -LiteralPath $d -PathType Container) { $d }
    }
}

# --- talking to the bridge -------------------------------------------------------------------------------------------

$Token = $null
function Get-Token {
    if ($script:Token) { return $script:Token }
    $f = Join-Path (Get-ProfileDir) 'BepInEx\config\ModTestBridge.token'
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
        Fail "no token at ${f}: run the game once with ModTestBridge enabled (Enabled = true in BepInEx\config\Spronglehump.ModTestBridge.cfg)" 2
    }
    $script:Token = (Get-Content -LiteralPath $f -Raw).Trim()
    $script:Token
}

# One request; returns the response body whatever the status (like curl -sS). Fails if the game doesn't answer.
function Invoke-Bridge([string]$path, [string]$method = 'GET', [string]$body = $null, [int]$timeout = 0) {
    if ($timeout -le 0) { $timeout = [int](Setting 'MTB_TIMEOUT' '30') }
    $token = Get-Token
    $req = [Net.HttpWebRequest]::Create("$Url$path")
    $req.Method = $method
    $req.Timeout = $timeout * 1000
    $req.ReadWriteTimeout = $timeout * 1000
    $req.Proxy = $null
    $req.Headers.Add('X-Token', $token)
    if ($method -eq 'POST') {
        $bytes = [Text.Encoding]::UTF8.GetBytes([string]$body)
        $req.ContentType = 'text/plain; charset=utf-8'
        $req.ContentLength = $bytes.Length
        if ($bytes.Length -gt 0) {
            $s = $req.GetRequestStream(); try { $s.Write($bytes, 0, $bytes.Length) } finally { $s.Close() }
        }
    }
    try {
        $resp = $req.GetResponse()
    } catch [Net.WebException] {
        $resp = $_.Exception.Response
        if (-not $resp) { Fail "no answer from the game on ${Url}: $($_.Exception.Message)" 7 }
    } catch {
        $inner = $_.Exception.InnerException
        if ($inner -is [Net.WebException] -and $inner.Response) { $resp = $inner.Response }
        else { Fail "no answer from the game on ${Url}: $($_.Exception.Message)" 7 }
    }
    try {
        $reader = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
        $reader.ReadToEnd()
    } finally { $resp.Close() }
}

function Invoke-BridgeJson([string]$path, [string]$method = 'GET', [string]$body = $null, [int]$timeout = 0) {
    $d = Invoke-Bridge $path $method $body $timeout | ConvertFrom-Json
    if (Has-Prop $d 'error') { Fail "the bridge said: $($d.error)" }
    $d
}

function Has-Prop($obj, [string]$name) { $null -ne $obj -and $obj.PSObject.Properties.Name -contains $name }

function Get-LogNext { (Invoke-BridgeJson '/log?from=0&contains=%00').next }
function Get-LogLines([long]$from, [string]$contains = '') {
    Invoke-BridgeJson "/log?from=$from&contains=$([Uri]::EscapeDataString($contains))"
}

function Write-CommandOutput([string]$text) {
    $d = $text | ConvertFrom-Json
    if (Has-Prop $d 'output') { if ($d.output) { $d.output } } else { $text }
}

# --- the game process ------------------------------------------------------------------------------------------------

# MTB_GAME_PATTERN here is a regex on the process name (no .exe). Never valheim_server.
function Test-Running {
    $pattern = Setting 'MTB_GAME_PATTERN' '^valheim$'
    $null -ne (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match $pattern } | Select-Object -First 1)
}

function Quote([string]$s) { '"' + $s + '"' }

# How the profile is launched: as Gale and r2modman launch it (Steam, with BepInEx's doorstop pointed at the profile).
function Get-LaunchCmd {
    $launch = Setting 'MTB_LAUNCH'
    if ($launch) { return $launch }
    $preloader = Join-Path (Get-ProfileDir) 'BepInEx\core\BepInEx.Preloader.dll'
    $steam = Setting 'MTB_STEAM'
    if (-not $steam) {
        $root = Get-SteamRoot
        if (-not $root) { Fail "can't find Steam: set MTB_STEAM or MTB_LAUNCH" 2 }
        $steam = Join-Path $root 'steam.exe'
    }
    "$(Quote $steam) -applaunch $App --doorstop-enabled true --doorstop-target-assembly $(Quote $preloader)"
}

function Start-Game([string]$world, [string]$character) {
    $cmd = "$(Get-LaunchCmd) -console -mtb-world $(Quote $world) -mtb-character $(Quote $character)"
    # cmd /s /c "..." keeps the inner quotes; MTB_LAUNCH is a cmd.exe command line.
    Start-Process -FilePath $env:ComSpec -ArgumentList "/s /c `"$cmd`"" -WindowStyle Hidden | Out-Null
    Write-Output "launching $(Split-Path -Leaf (Get-ProfileDir)) into $world as $character"
}

$World = $null; $Character = $null
function Set-Names([string]$world, [string]$character) {
    $script:World = if ($world) { $world } else { Setting 'MTB_WORLD' }
    $script:Character = if ($character) { $character } else { Setting 'MTB_CHARACTER' }
    if (-not $script:World -or -not $script:Character) {
        Fail 'which world and character? pass them, or set MTB_WORLD and MTB_CHARACTER' 2
    }
}

$BackedUp = $false
# Copies of the character and world (local and Steam Cloud saves), taken while the game isn't running; newest N kept.
function Backup-Saves {
    $script:BackedUp = $false
    if (Test-Running) { Warn 'not backing up while the game is running (saves may be half-written)'; return }
    $c = $Character.ToLowerInvariant(); $w = $World.ToLowerInvariant()
    $root = Join-Path (Get-ProfileDir) 'BepInEx\ModTestBridge\backups'
    $dest = Join-Path $root (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $copied = New-Object Collections.Generic.List[string]
    function Copy-One([string]$from, [string]$name) {
        if (Test-Path -LiteralPath $from) {
            Copy-Item -LiteralPath $from -Destination (Join-Path $dest $name) -Recurse -Force
            $copied.Add($name)
        }
    }
    foreach ($d in Get-SavesDirs) {
        foreach ($sub in 'characters_local', 'characters') { Copy-One (Join-Path $d "$sub\$c.fch") "$sub-$c.fch" }
        foreach ($sub in 'worlds_local', 'worlds') {
            Copy-One (Join-Path $d "$sub\$w") "$sub-$w"   # chunked world (current format)
            foreach ($ext in 'db', 'fwl') { Copy-One (Join-Path $d "$sub\$w.$ext") "$sub-$w.$ext" }
        }
    }
    foreach ($d in Get-CloudDirs) {
        Copy-One (Join-Path $d "characters\$c.fch") "cloud-$c.fch"
        Copy-One (Join-Path $d "worlds\$w") "cloud-world-$w"
    }
    $keep = [int](Setting 'MTB_KEEP_BACKUPS' '5')
    $all = @(Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name)
    if ($all.Count -gt $keep) { $all[0..($all.Count - $keep - 1)] | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force } }
    if ($copied.Count -eq 0) {
        Warn "warning: found no saves for $Character / $World to back up (see mtb doctor)"
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
        return
    }
    $script:BackedUp = $true
    Write-Output "backed up to ${dest}: $($copied -join ' ')"
}

function Wait-Log([string]$text, [int]$timeout, [long]$from) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeout) {
        try { $d = Get-LogLines $from $text } catch { Start-Sleep -Seconds 5; continue }
        if ($d.lines -and @($d.lines).Count -gt 0) { $d.lines; return }
        Start-Sleep -Seconds 3
    }
    Fail "timed out after ${timeout}s waiting for: $text"
}

function Wait-World([int]$timeout) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeout) {
        $st = $null
        try { $st = Invoke-Bridge '/status' 'GET' $null 5 } catch { }
        if ($st) {
            $d = $st | ConvertFrom-Json
            if ((Has-Prop $d 'state') -and $d.state -eq 'world') { Write-Output $st; return }
            if ((Has-Prop $d 'autostart') -and "$($d.autostart)" -like 'refused*') { Fail "autostart $($d.autostart)" }
        }
        Start-Sleep -Seconds 5
    }
    Fail 'timed out waiting for the world'
}

function Show-Doctor {
    Write-Output 'platform:   Windows (PowerShell)'
    $ok = $true
    try { $dir = Get-ProfileDir; Write-Output "profile:    $dir" } catch { Write-Output "profile:    ?? $($_.Exception.Message)"; $ok = $false }
    if ($ok) {
        if (Test-Bridge $dir) { Write-Output 'plugin:     installed' } else { Write-Output "plugin:     ?? ModTestBridge.dll not under $dir\BepInEx\plugins" }
        $cfg = Join-Path $dir 'BepInEx\config\Spronglehump.ModTestBridge.cfg'
        if (Test-Path -LiteralPath $cfg) {
            $line = Get-Content -LiteralPath $cfg | Where-Object { $_ -match '^Enabled = ' } | Select-Object -First 1
            Write-Output "enabled:    $(if ($line) { $line -replace '^Enabled = ', '' })"
        } else { Write-Output 'enabled:    (no config yet: run the game once)' }
        if (Test-Path -LiteralPath (Join-Path $dir 'BepInEx\config\ModTestBridge.token')) { Write-Output 'token:      found' }
        else { Write-Output 'token:      ?? none yet (written on the first run with Enabled = true)' }
        try { Write-Output "launch:     $(Get-LaunchCmd)" } catch { Write-Output 'launch:     ?? unknown: set MTB_LAUNCH' }
    }
    $w = Setting 'MTB_WORLD' '(unset: MTB_WORLD)'; $c = Setting 'MTB_CHARACTER' '(unset: MTB_CHARACTER)'
    Write-Output "world:      $w   character: $c"
    Write-Output "saves:      $((@(Get-SavesDirs) | Where-Object { Test-Path -LiteralPath $_ }) -join ' ')"
    Write-Output "cloud:      $(@(Get-CloudDirs) -join ' ')"
    Write-Output "game:       $(if (Test-Running) { 'running' } else { 'not running' })"
    if ($ok) {
        $answer = try { Invoke-Bridge '/status' 'GET' $null 5 } catch { $_.Exception.Message }
        Write-Output "bridge:     $answer"
    }
}

# --- commands --------------------------------------------------------------------------------------------------------

$A = @($args)
# The i-th argument, or the default when it's missing or empty.
function Get-Arg([int]$i, [string]$default = '') { if ($A.Count -gt $i -and "$($A[$i])" -ne '') { "$($A[$i])" } else { $default } }

try {
    switch (Get-Arg 0 'status') {
        'status' { Invoke-Bridge '/status' }
        'cmd' { Write-CommandOutput (Invoke-Bridge '/command' 'POST' (($A | Select-Object -Skip 1) -join ' ')) }
        'run' {
            if ($A.Count -lt 3) { Fail 'usage: mtb run "<command>" "<text to wait for>" [timeout]' 2 }
            $from = Get-LogNext   # before the command, so a fast result isn't missed
            Write-CommandOutput (Invoke-Bridge '/command' 'POST' $A[1])
            Wait-Log $A[2] ([int](Get-Arg 3 '600')) $from
        }
        'log' {
            $d = Get-LogLines ([long](Get-Arg 1 '0')) (Get-Arg 2)
            $d.lines
            Warn "# next=$($d.next)"
        }
        'tail' {
            $n = [int](Get-Arg 1 '40')
            if (Get-Arg 2) {
                $lines = @((Get-LogLines 0 (Get-Arg 2)).lines)
                if ($lines.Count -gt $n) { $lines = $lines[($lines.Count - $n)..($lines.Count - 1)] }
                $lines
            } else {
                $next = [long](Get-LogNext)
                (Get-LogLines ([Math]::Max(0, $next - $n))).lines
            }
        }
        'mark' { Get-LogNext }
        'wait-log' {
            if ($A.Count -lt 2) { Fail 'usage: mtb wait-log "<text>" [timeout]' 2 }
            Wait-Log $A[1] ([int](Get-Arg 2 '600')) (Get-LogNext)
        }
        'wait-world' { Wait-World ([int](Get-Arg 1 '300')) }
        'quit' { Invoke-Bridge '/quit' 'POST' '' }
        'start' {
            Set-Names (Get-Arg 1) (Get-Arg 2)
            if (Test-Running) { Fail 'the game is already running (use mtb restart)' }
            Backup-Saves
            Start-Game $World $Character
        }
        'restart' {
            Set-Names (Get-Arg 1) (Get-Arg 2)
            if (Test-Running) {
                try { Invoke-Bridge '/quit' 'POST' '' | Out-Null } catch { }
                $sw = [Diagnostics.Stopwatch]::StartNew()
                while ((Test-Running) -and $sw.Elapsed.TotalSeconds -lt 120) { Start-Sleep -Seconds 2 }
                if (Test-Running) { Fail "the game didn't quit within 120 s" }
                Start-Sleep -Seconds 3
            }
            Backup-Saves
            Start-Game $World $Character
            Wait-World 400
        }
        'backup' {
            Set-Names (Get-Arg 1) (Get-Arg 2)
            Backup-Saves
            if (-not $BackedUp) { exit 1 }
        }
        'profiles' { Get-BridgeProfiles }
        'doctor' { Show-Doctor }
        { $_ -in 'help', '-h', '--help' } { $Usage }
        default { $Usage; exit 2 }
    }
} catch {
    if (-not (Is-Fail $_)) { throw }
    Warn $_.Exception.Message
    exit $_.Exception.Data['mtb']
}

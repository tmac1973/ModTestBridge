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
mtb shot [name] [options]           save a screenshot, print its path (PNG; read it to see the game)
     --size PX                         longer side in pixels (default 768; the screen is scaled down to it)
     --at x,y,z --look x,y,z [--fov D] from a camera of its own at one point looking at another (no UI)
     --day                             at noon (the time of day is put back afterwards)
mtb quit                            save, log out and quit the game
mtb start [world] [character]       back up the saves, launch the game straight into the world (autostart)
mtb restart [world] [character]     quit if running, back up, launch, wait until in the world
mtb backup [world] [character]      copy the character and world saves (only while the game isn't running)
mtb profiles                        mod-manager profiles that have ModTestBridge installed
mtb doctor                          show what mtb found (profile, token, launch, saves) and whether the game answers
mtb join [character] [host:port]    quit if running, back up, launch the game onto the test server, wait for it

A dedicated test server (headless, on this machine): put "server" first.
mtb server start [world]            back up its world, launch the server (creating the world if new), wait until up
mtb server restart [world]          stop if running, back up, start
mtb server stop                     save and stop it
mtb server backup [world]           copy its world (only while it isn't running)
mtb server status|cmd|run|log|mark|tail|wait-log|wait-world|doctor   as above, in the server
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
                'MTB_STEAM', 'MTB_GAME_PATTERN', 'MTB_SAVES_DIRS', 'MTB_CLOUD_DIRS', 'MTB_KEEP_BACKUPS',
                'MTB_SERVER_DIR', 'MTB_SERVER_PROFILE_DIR', 'MTB_SERVER_PORT', 'MTB_SERVER_WORLD', 'MTB_SERVER_SAVEDIR',
                'MTB_SERVER_GAME_PORT', 'MTB_SERVER_PASSWORD', 'MTB_SERVER_ARGS', 'MTB_SERVER_LAUNCH', 'MTB_SERVER_ADDRESS'
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
$A = @($args)
# Every command after "server" goes to the test server.
$Server = $A.Count -gt 0 -and "$($A[0])" -eq 'server'
if ($Server) { $A = @($A | Select-Object -Skip 1) }
$Port = if ($Server) { Setting 'MTB_SERVER_PORT' '7812' } else { Setting 'MTB_PORT' '7811' }
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
    if ($Server) { $script:ProfileDirCache = Get-ServerProfileDir; return $script:ProfileDirCache }
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
    if ($Server) { return Get-ServerSavedir }
    $v = Setting 'MTB_SAVES_DIRS'
    if ($v) { return Split-Dirs $v }
    Join-Path (Get-HomeDir) 'AppData\LocalLow\IronGate\Valheim'
}

# Steam Cloud save folders (userdata\<account>\892970\remote).
function Get-CloudDirs {
    if ($Server) { return }   # the server's world is only ever local
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
        Fail "no token at ${f}: run the $(if ($Server) { 'server' } else { 'game' }) once with ModTestBridge enabled (Enabled = true in BepInEx\config\Spronglehump.ModTestBridge.cfg)" 2
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

# A screenshot: the query is built from the options, the answer names the file relative to the profile.
function Save-Shot([object[]]$opts) {
    $q = @()
    for ($i = 0; $i -lt $opts.Count; $i++) {
        $o = "$($opts[$i])"
        if ($o -in '--size', '--at', '--look', '--fov') {
            if ($i + 1 -ge $opts.Count) { Fail "mtb shot: $o needs a value" 2 }
            $i++
            $q += "$($o.Substring(2))=$([Uri]::EscapeDataString("$($opts[$i])"))"
        } elseif ($o -eq '--day') { $q += 'day=1' }
        elseif ($o.StartsWith('-')) { Fail "mtb shot: unknown option $o (see mtb help)" 2 }
        else { $q += "name=$([Uri]::EscapeDataString($o))" }
    }
    $timeout = [int](Setting 'MTB_TIMEOUT' '60')
    $d = Invoke-Bridge "/screenshot?$($q -join '&')" 'GET' $null $timeout | ConvertFrom-Json
    if (-not (Has-Prop $d 'relative')) {
        $e = if (Has-Prop $d 'error') { $d.error } else { "$d" }
        if ($e -eq 'unknown path') { Fail 'mtb shot: this ModTestBridge has no screenshots (update the plugin to 0.2.0 or later)' }
        Fail "mtb shot: $e"
    }
    Join-Path (Get-ProfileDir) ($d.relative -replace '/', '\')
    if ($d.blank) { Fail 'mtb shot: the picture is black: is the game window minimised or hidden?' 3 }
}

# --- the game process ------------------------------------------------------------------------------------------------

# MTB_GAME_PATTERN here is a regex on the process name (no .exe). Never valheim_server.
function Test-Running {
    if ($Server) { return Test-ServerRunning }
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

# --- the dedicated test server ---------------------------------------------------------------------------------------

# Steam library folders, from libraryfolders.vdf.
function Get-SteamLibraries {
    $root = Get-SteamRoot
    if (-not $root) { return }
    $root
    $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($line in Get-Content -LiteralPath $vdf) {
            if ($line -match '^\s*"path"\s*"(.*)"') { $Matches[1] -replace '\\\\', '\' }
        }
    }
}

# The Valheim Dedicated Server install (Steam's free "Valheim Dedicated Server" tool).
function Get-ServerDir {
    $dir = Setting 'MTB_SERVER_DIR'
    if ($dir) { return $dir }
    foreach ($l in Get-SteamLibraries) {
        $d = Join-Path $l 'steamapps\common\Valheim dedicated server'
        if (Test-Path -LiteralPath $d -PathType Container) { return $d }
    }
    Fail 'no Valheim Dedicated Server found (install it from Steam''s Tools, or set MTB_SERVER_DIR)' 2
}
# The folder holding the server's BepInEx\: the server install itself unless MTB_SERVER_PROFILE_DIR says otherwise.
function Get-ServerProfileDir { $d = Setting 'MTB_SERVER_PROFILE_DIR'; if ($d) { $d } else { Get-ServerDir } }
# Its saves stay apart from the game's, so a test world never mixes with real ones.
function Get-ServerSavedir {
    $d = Setting 'MTB_SERVER_SAVEDIR'
    if ($d) { $d } else { Join-Path (Get-ServerProfileDir) 'BepInEx\ModTestBridge\server-saves' }
}
function Get-ServerStateDir { Join-Path (Get-ServerProfileDir) 'BepInEx\ModTestBridge' }
function Get-ServerPid {
    $f = Join-Path (Get-ServerStateDir) 'server.pid'
    if (Test-Path -LiteralPath $f) { (Get-Content -LiteralPath $f -Raw).Trim() }
}
# Only the server mtb started (by its pid), never another one running on this machine.
function Test-ServerRunning {
    $id = Get-ServerPid
    if (-not $id) { return $false }
    $p = Get-Process -Id ([int]$id) -ErrorAction SilentlyContinue
    $null -ne $p -and $p.ProcessName -match 'valheim_server'
}
function Test-ServerEnabled {
    $cfg = Join-Path (Get-ServerProfileDir) 'BepInEx\config\Spronglehump.ModTestBridge.cfg'
    (Test-Path -LiteralPath $cfg) -and (@(Get-Content -LiteralPath $cfg | Where-Object { $_ -match '^\s*Enabled\s*=\s*true' }).Count -gt 0)
}

# Everything a start needs, checked before anything is stopped or copied.
function Assert-ServerReady {
    $exe = Join-Path (Get-ServerDir) 'valheim_server.exe'
    $prof = Get-ServerProfileDir
    if (-not (Test-Path -LiteralPath $exe)) { Fail "no server at $exe (set MTB_SERVER_DIR)" 2 }
    if (-not (Test-Path -LiteralPath (Join-Path $prof 'BepInEx\core\BepInEx.Preloader.dll'))) {
        Fail "no BepInEx in ${prof}: install BepInExPack_Valheim there (see README, `"A dedicated test server`")" 2
    }
    if (-not (Test-Bridge $prof)) { Fail "ModTestBridge.dll isn't under $prof\BepInEx\plugins" 2 }
    if (-not (Test-ServerEnabled)) {
        Fail "ModTestBridge is off in the server. Put this in $prof\BepInEx\config\Spronglehump.ModTestBridge.cfg:`n[General]`nEnabled = true" 2
    }
}

# Launch the server in the background with BepInEx from the server profile (doorstop's command-line options), the test
# world and its own save folder, not listed publicly; output to server.out.
function Start-Server([string]$world) {
    $dir = Get-ServerDir; $prof = Get-ServerProfileDir; $saves = Get-ServerSavedir; $state = Get-ServerStateDir
    New-Item -ItemType Directory -Force -Path $saves, $state | Out-Null
    $gamePort = Setting 'MTB_SERVER_GAME_PORT' '2456'
    $argline = "-name $(Quote "mtb $world") -port $gamePort -world $(Quote $world) -savedir $(Quote $saves) -public 0"
    $pw = Setting 'MTB_SERVER_PASSWORD'
    if ($pw) { $argline += " -password $(Quote $pw)" }
    $extra = Setting 'MTB_SERVER_ARGS'
    if ($extra) { $argline += " $extra" }
    $out = Join-Path $state 'server.out'
    $launch = Setting 'MTB_SERVER_LAUNCH'
    if ($launch) {
        $p = Start-Process -FilePath $env:ComSpec -ArgumentList "/s /c `"$launch $argline`"" -WorkingDirectory $dir `
                -WindowStyle Hidden -RedirectStandardOutput $out -PassThru
    } else {
        $preloader = Join-Path $prof 'BepInEx\core\BepInEx.Preloader.dll'
        $p = Start-Process -FilePath (Join-Path $dir 'valheim_server.exe') -WorkingDirectory $dir -WindowStyle Hidden `
                -ArgumentList "--doorstop-enabled true --doorstop-target-assembly $(Quote $preloader) $argline" `
                -RedirectStandardOutput $out -PassThru
    }
    Set-Content -LiteralPath (Join-Path $state 'server.pid') -Value $p.Id
    Write-Output "launching the test server: world $world, port $gamePort, saves in $saves"
}

# Wait until the server has loaded its world; fail early (with its last output) if it exits.
function Wait-Server([int]$timeout) {
    Start-Sleep -Seconds 2
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeout) {
        if (-not (Test-ServerRunning)) {
            $out = Join-Path (Get-ServerStateDir) 'server.out'
            $tail = if (Test-Path -LiteralPath $out) { (Get-Content -LiteralPath $out -Tail 15) -join "`n" } else { '' }
            Fail "the server stopped; the end of ${out}:`n$tail"
        }
        $st = $null
        try { $st = Invoke-Bridge '/status' 'GET' $null 5 } catch { }
        if ($st -and ($st | ConvertFrom-Json).state -eq 'world') { Write-Output $st; return }
        Start-Sleep -Seconds 3
    }
    Fail 'timed out waiting for the server'
}

function Stop-Server {
    if (-not (Test-ServerRunning)) { Write-Output "the test server isn't running"; return }
    try { Invoke-Bridge '/quit' 'POST' '' | Out-Null } catch { }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ((Test-ServerRunning) -and $sw.Elapsed.TotalSeconds -lt 90) { Start-Sleep -Seconds 2 }
    if (Test-ServerRunning) {
        # The bridge didn't answer. Windows has no Ctrl-C for a hidden process, so this stops it without saving.
        Warn "the server didn't quit through the bridge; stopping it (its world isn't saved)"
        Stop-Process -Id ([int](Get-ServerPid)) -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        if (Test-ServerRunning) { Fail "the server didn't stop (pid $(Get-ServerPid))" }
    }
    Remove-Item -LiteralPath (Join-Path (Get-ServerStateDir) 'server.pid') -Force -ErrorAction SilentlyContinue
    Write-Output 'test server stopped'
}

function Set-ServerWorld([string]$world) {
    $script:World = if ($world) { $world } else { Setting 'MTB_SERVER_WORLD' (Setting 'MTB_WORLD') }
    $script:Character = ''
    if (-not $script:World) { Fail 'which world? pass it, or set MTB_SERVER_WORLD (or MTB_WORLD)' 2 }
}

function Show-ServerDoctor {
    $ok = $true
    try { $dir = Get-ServerDir; Write-Output "server:     $dir" } catch { Write-Output "server:     ?? $($_.Exception.Message)"; $ok = $false }
    if ($ok) {
        $prof = Get-ServerProfileDir
        Write-Output "profile:    $prof"
        if (Test-Path -LiteralPath (Join-Path $prof 'BepInEx\core\BepInEx.Preloader.dll')) { Write-Output 'bepinex:    installed' }
        else { Write-Output "bepinex:    ?? no BepInEx\core\BepInEx.Preloader.dll in $prof" }
        if (Test-Bridge $prof) { Write-Output 'plugin:     installed' } else { Write-Output "plugin:     ?? ModTestBridge.dll not under $prof\BepInEx\plugins" }
        if (Test-ServerEnabled) { Write-Output 'enabled:    true' }
        else { Write-Output "enabled:    ?? not on (Enabled = true in $prof\BepInEx\config\Spronglehump.ModTestBridge.cfg)" }
        if (Test-Path -LiteralPath (Join-Path $prof 'BepInEx\config\ModTestBridge.token')) { Write-Output 'token:      found' }
        else { Write-Output 'token:      (none yet: written on the first start)' }
        $bcfg = Join-Path $prof 'BepInEx\config\BepInEx.cfg'
        if ((Test-Path -LiteralPath $bcfg) -and @(Get-Content -LiteralPath $bcfg | Where-Object { $_ -match '^\s*WriteUnityLog\s*=\s*true' }).Count -gt 0) {
            Write-Output 'unity log:  in LogOutput.log'
        } else { Write-Output "unity log:  ?? not in LogOutput.log: the game's own lines and Debug.Log are missing (WriteUnityLog = true in BepInEx.cfg)" }
        Write-Output "saves:      $(Get-ServerSavedir)"
    }
    $w = Setting 'MTB_SERVER_WORLD' (Setting 'MTB_WORLD' '(unset: MTB_SERVER_WORLD)')
    Write-Output "world:      $w   game port: $(Setting 'MTB_SERVER_GAME_PORT' '2456')   bridge port: $Port"
    Write-Output "password:   $(if (Setting 'MTB_SERVER_PASSWORD') { 'set' } else { 'none (not listed publicly; anyone on your network could join)' })"
    Write-Output "running:    $(if ($ok -and (Test-ServerRunning)) { "yes (pid $(Get-ServerPid))" } else { 'no' })"
    if ($ok) {
        $answer = try { Invoke-Bridge '/status' 'GET' $null 5 } catch { $_.Exception.Message }
        Write-Output "bridge:     $answer"
    }
}

# The game, straight onto a server (Valheim's own -password answers its password prompt).
function Start-GameJoin([string]$address, [string]$character) {
    $cmd = "$(Get-LaunchCmd) -console -mtb-server $(Quote $address) -mtb-character $(Quote $character)"
    $pw = Setting 'MTB_SERVER_PASSWORD'
    if ($pw) { $cmd += " -password $(Quote $pw)" }
    Start-Process -FilePath $env:ComSpec -ArgumentList "/s /c `"$cmd`"" -WindowStyle Hidden | Out-Null
    Write-Output "launching $(Split-Path -Leaf (Get-ProfileDir)) onto $address as $character"
}

function Stop-GameForRestart {
    if (Test-Running) {
        try { Invoke-Bridge '/quit' 'POST' '' | Out-Null } catch { }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ((Test-Running) -and $sw.Elapsed.TotalSeconds -lt 120) { Start-Sleep -Seconds 2 }
        if (Test-Running) { Fail "the game didn't quit within 120 s" }
        Start-Sleep -Seconds 3
    }
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
    if (Test-Running) { Warn "not backing up while the $(if ($Server) { 'server' } else { 'game' }) is running (saves may be half-written)"; return }
    $c = "$Character".ToLowerInvariant(); $w = "$World".ToLowerInvariant()
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
        if ($c) { foreach ($sub in 'characters_local', 'characters') { Copy-One (Join-Path $d "$sub\$c.fch") "$sub-$c.fch" } }
        if ($w) {
            foreach ($sub in 'worlds_local', 'worlds') {
                Copy-One (Join-Path $d "$sub\$w") "$sub-$w"   # chunked world (current format)
                foreach ($ext in 'db', 'fwl') { Copy-One (Join-Path $d "$sub\$w.$ext") "$sub-$w.$ext" }
            }
        }
    }
    foreach ($d in Get-CloudDirs) {
        if ($c) { Copy-One (Join-Path $d "characters\$c.fch") "cloud-$c.fch" }
        if ($w) { Copy-One (Join-Path $d "worlds\$w") "cloud-world-$w" }
    }
    $keep = [int](Setting 'MTB_KEEP_BACKUPS' '5')
    $all = @(Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name)
    if ($all.Count -gt $keep) { $all[0..($all.Count - $keep - 1)] | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force } }
    if ($copied.Count -eq 0) {
        Warn "warning: found no saves for $((@($Character, $World) | Where-Object { $_ }) -join ' / ') to back up (see mtb doctor)"
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

# The i-th argument, or the default when it's missing or empty.
function Get-Arg([int]$i, [string]$default = '') { if ($A.Count -gt $i -and "$($A[$i])" -ne '') { "$($A[$i])" } else { $default } }

try {
    if ($Server) {
        switch (Get-Arg 0 'status') {
            'start' {
                Set-ServerWorld (Get-Arg 1)
                if (Test-ServerRunning) { Fail 'the test server is already running (use mtb server restart)' }
                Assert-ServerReady; Backup-Saves; Start-Server $World; Wait-Server 600; exit 0
            }
            'restart' { Set-ServerWorld (Get-Arg 1); Assert-ServerReady; Stop-Server; Backup-Saves; Start-Server $World; Wait-Server 600; exit 0 }
            { $_ -in 'stop', 'quit' } { Stop-Server; exit 0 }
            'backup' { Set-ServerWorld (Get-Arg 1); Backup-Saves; if (-not $BackedUp) { exit 1 }; exit 0 }
            'doctor' { Show-ServerDoctor; exit 0 }
            'shot' { Fail 'a dedicated server has no screen: take screenshots in the game (mtb shot)' 2 }
            'wait-world' { Wait-Server ([int](Get-Arg 1 '300')); exit 0 }
            { $_ -in 'status', 'cmd', 'run', 'log', 'tail', 'mark', 'wait-log' } { }   # the same as in the game, below
            default { $Usage; exit 2 }
        }
    }
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
        'shot' { Save-Shot @($A | Select-Object -Skip 1) }
        'quit' { Invoke-Bridge '/quit' 'POST' '' }
        'start' {
            Set-Names (Get-Arg 1) (Get-Arg 2)
            if (Test-Running) { Fail 'the game is already running (use mtb restart)' }
            Backup-Saves
            Start-Game $World $Character
        }
        'restart' {
            Set-Names (Get-Arg 1) (Get-Arg 2)
            Stop-GameForRestart
            Backup-Saves
            Start-Game $World $Character
            Wait-World 400
        }
        'backup' {
            Set-Names (Get-Arg 1) (Get-Arg 2)
            Backup-Saves
            if (-not $BackedUp) { exit 1 }
        }
        'join' {
            $script:Character = Get-Arg 1 (Setting 'MTB_CHARACTER'); $script:World = ''
            if (-not $Character) { Fail 'which character? pass it, or set MTB_CHARACTER' 2 }
            $address = Get-Arg 2 (Setting 'MTB_SERVER_ADDRESS' "127.0.0.1:$(Setting 'MTB_SERVER_GAME_PORT' '2456')")
            if (-not (Get-Arg 2) -and -not (Setting 'MTB_SERVER_ADDRESS')) {   # the local test server: is it up?
                $up = $false
                try {
                    $token = (Get-Content -LiteralPath (Join-Path (Get-ServerProfileDir) 'BepInEx\config\ModTestBridge.token') -Raw).Trim()
                    $st = Invoke-RestMethod -Uri "http://127.0.0.1:$(Setting 'MTB_SERVER_PORT' '7812')/status" -Headers @{ 'X-Token' = $token } -TimeoutSec 5
                    $up = $st.state -eq 'world'
                } catch { }
                if (-not $up) { Fail "the test server isn't up: mtb server start" }
            }
            Stop-GameForRestart
            Backup-Saves
            Start-GameJoin $address $Character
            Wait-World 400
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

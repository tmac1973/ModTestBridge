# ModTestBridge

**Drive Valheim from scripts, or from an AI coding agent, while you develop mods.**

ModTestBridge is a small BepInEx plugin for mod developers. It lets anything on your own machine:
- run console commands in the running game and get back what they printed;
- read the BepInEx log;
- see the game's state: menu or in a world, which world, which character, where;
- take screenshots, of the screen as the player sees it or from a camera placed anywhere in the world;
- quit cleanly, saving first;
- relaunch the game straight into a test world with an existing character, skipping the menus;
- run a headless dedicated server for testing, drive it the same way, and join it from the game.

Together these close the loop for automated testing:
1. build your mod;
2. `mtb restart`;
3. run your mod's test commands;
4. read the results, and look at a screenshot when a log line can't tell you;
5. fix, and repeat.

Nobody needs to click through menus or copy log lines by hand. It's how
[Hired Hands](https://github.com/tmac1973/HiredHands) is developed: Claude Code builds, restarts, runs the in-game
tests and reads the failures, while a human plays and judges how it feels.

It works with any mod, because it doesn't know about yours. Your mod keeps its own test commands, and the bridge runs
them. See [Writing tests for your mod](docs/writing-tests.md).

> [!WARNING]
> **Development profiles only.** Never install it on a server people play on or on a profile you play on: only on
> a test server of your own. Anything on your computer that can reach the port with the token can run console commands.
> It only listens on 127.0.0.1, and it is **off until you turn it on**.

What's here:
- **The plugin**, under `src/`. Download it from [Releases](https://github.com/tmac1973/ModTestBridge/releases), or from
  Hexium/Thunderstore as `Spronglehump-ModTestBridge`.
- **`mtb`**, a command-line client, in `claude-plugin/bin/`: `mtb` is bash with curl and python3 (Linux, Git Bash), and
  `mtb.cmd` runs the PowerShell port in `claude-plugin/windows/mtb.ps1` (Windows, nothing else needed).
- **A Claude Code plugin**, the `valheim-mod-testing` skill plus `mtb`, which teaches Claude how to test your mod
  in-game.
- **An example**, in `examples/`: a tiny mod with tests written the way the bridge expects, and a script that runs them
  and fails on any failure.

## Install

**1. Add the plugin to a development profile.** In Gale or r2modman, make a profile just for testing, with your mod and
the mods it needs. Then either:
- install `ModTestBridge` from the mod manager; or
- unzip the release so that `ModTestBridge.dll` ends up under the profile's `BepInEx/plugins/`.

**2. Turn it on.** Run the game once with the profile, then quit. Set `Enabled = true` in
`BepInEx/config/Spronglehump.ModTestBridge.cfg`. The mod manager's config editor works too.

**3. Start the game again.** The log says `ModTestBridge listening on 127.0.0.1:7811`. A random token has been written
to `BepInEx/config/ModTestBridge.token`.

**4. Get `mtb`.** Clone this repo, or install the Claude Code plugin (below), and put `claude-plugin/bin` on your PATH.
On Windows that gives you `mtb.cmd`, which works from PowerShell and cmd with nothing else installed (see
[Platforms](#platforms)). Then check what it found:
```
mtb doctor
```

**5. Make a test world and character.** Create a world and a character for testing, and play into that world by hand
once, so the character has been there. This matters for autostart. Then tell `mtb` about them in a `.mtb` file in your
mod's repo:
```
MTB_PROFILE=mymod-dev      # the mod-manager profile name (or MTB_PROFILE_DIR=/full/path/to/profile)
MTB_WORLD=testworld
MTB_CHARACTER=Tester
```

Tip: in Valheim's character and world menus, move the test character and world to **local** saves rather than Steam
Cloud. Restarting many times a day makes Steam Cloud churn.

## Using `mtb`
```
mtb status                          # {"state":"world","world":"testworld","character":"Tester","position":[...],...}
mtb cmd "devcommands"               # run a console command; prints what it printed
mtb run "mymod_test all" "[TEST] done" 600   # run, then wait up to 600 s for a log line containing the text
mtb mark                            # the log's current line number...
mtb log 1234 "[TEST]"               # ...and the lines after it, optionally only those containing text
mtb tail 40 "Error"                 # the last 40 lines (containing "Error")
mtb wait-log "[TEST] done" 600      # wait for a new log line
mtb wait-world                      # wait until a character is in a world
mtb shot hud                        # a screenshot of what the player sees, UI included; prints the PNG's path
mtb shot cook --at 10,32,5 --look 10,31.7,8 --fov 30 --day   # from a camera of its own (no UI), at noon
mtb quit                            # save, log out, quit
mtb restart [world] [character]     # quit if running, back up the saves, relaunch straight into the world, wait for it
mtb start [world] [character]       # the same, when the game isn't running
mtb backup                          # back up the test character and world now (game not running)
mtb profiles                        # mod-manager profiles with ModTestBridge installed
mtb doctor                          # what mtb found, and whether the game answers
mtb join [character] [host:port]    # relaunch straight onto a server (see "A dedicated test server")
mtb server ...                      # the same for a dedicated test server (see below)
```

**Screenshots.** For what a log line can't tell you: a model, a hat, a panel's layout. `mtb shot [name]` saves
`<profile>/BepInEx/ModTestBridge/screenshots/<name>.png` and prints its path, so an agent can read the picture.
- The name is letters, digits, `-`, `_` and `.`; a shot with the same name replaces the old one. Without a name you get
  `shot-<date>-<time>`.
- `--size PX`: the longer side, 768 by default (64 to 4096). The screen is scaled down to it, never up. Full-size frames
  cost an agent many tokens; go bigger only for detail.
- `--at x,y,z --look x,y,z [--fov D]`: a camera of its own, at one point looking at another, in world coordinates
  (`mtb status` gives the player's position). The field of view is 40 degrees by default (5 to 120). The player's view
  is left alone and there's no UI. This camera doesn't draw grass or the game's post-processing, so pictures look
  flatter than the game does. In PowerShell, quote the coordinates (`--at "10,32,5"`), since PowerShell reads an unquoted
  `10,32,5` as a list and may pass it on as three arguments.
- `--day`: noon for the shot, then the time of day is put back. Night shots are hard to read.

Without `--at`, the picture is the game window, so the game has to be drawing: a minimised window gives a black picture.
`mtb shot` still prints the path, but says so and exits with code 3. Before the game has a camera (while it's starting),
the bridge answers 409 and nothing is saved. `mtb shot` waits up to 60 seconds unless `MTB_TIMEOUT` says otherwise.

**Restart and backups.**
- `mtb restart` saves and quits the game, then copies the test character and world (local and Steam Cloud saves) to
  `<profile>/BepInEx/ModTestBridge/backups/<time>/`, keeping the newest 5.
- It then launches the game through Steam the way your mod manager launches the profile, and waits until the character
  is standing in the world. That's about 40 seconds.
- The game window comes to the front, so if someone is playing on that machine, ask first.

### Configuring `mtb`
Settings are read in this order, each overriding the ones before it:
1. `~/.config/mtb/config` (on Windows, `%USERPROFILE%\.config\mtb\config`);
2. a `.mtb` file in the current directory or the nearest parent directory that has one;
3. the environment.

Both files are `KEY=value` lines.

| Setting | Default | |
|---|---|---|
| `MTB_PROFILE` | the only profile with ModTestBridge installed | Gale or r2modman profile name |
| `MTB_PROFILE_DIR` | | Or the profile folder itself, the one holding `BepInEx/` |
| `MTB_WORLD`, `MTB_CHARACTER` | | For `start`, `restart`, `backup` |
| `MTB_PORT` | 7811 | Match the plugin's `Port` setting |
| `MTB_TIMEOUT` | 30 | Seconds for one request |
| `MTB_LAUNCH` | worked out | The command that launches the profile; `mtb` adds `-console -mtb-world … -mtb-character …`. A bash command line, or a cmd.exe one for `mtb.cmd` |
| `MTB_STEAM` | `steam` / `steam.exe` | The Steam executable |
| `MTB_GAME_PATTERN` | `[v]alheim\.exe` (Proton) or `[v]alheim\.x86_64` | `pgrep -f` pattern for the game process. For `mtb.cmd`, a regex on the process name (default `^valheim$`) |
| `MTB_SAVES_DIRS` | worked out | `:`-separated folders holding `characters_local/` and `worlds_local/` (`;`-separated for `mtb.cmd`) |
| `MTB_CLOUD_DIRS` | `<steam>/userdata/*/892970/remote` | Steam Cloud save folders |
| `MTB_KEEP_BACKUPS` | 5 | |
| `MTB_SERVER_DIR` | found in your Steam libraries | The Valheim Dedicated Server install |
| `MTB_SERVER_PROFILE_DIR` | `MTB_SERVER_DIR` | The folder holding the server's `BepInEx/` |
| `MTB_SERVER_WORLD` | `MTB_WORLD` | The server's world, made if it doesn't exist yet |
| `MTB_SERVER_SAVEDIR` | `<server profile>/BepInEx/ModTestBridge/server-saves` | The server's `-savedir` |
| `MTB_SERVER_PORT` | 7812 | Match the server's `Port` setting |
| `MTB_SERVER_GAME_PORT` | 2456 | The port players join on |
| `MTB_SERVER_PASSWORD` | none | The server's password, which `mtb join` passes to the game |
| `MTB_SERVER_ARGS` | | More server options, split at spaces, such as `-preset hard` or `-modifier raids none` |
| `MTB_SERVER_LAUNCH` | worked out | The command that starts the server, run in its folder; `mtb` adds `-name … -port … -world … -savedir … -public 0` |
| `MTB_SERVER_ADDRESS` | `127.0.0.1:<MTB_SERVER_GAME_PORT>` | Where `mtb join` goes |

### Platforms
- **Linux, Valheim under Proton:** the way Gale and r2modman run modded Valheim. This is the tested setup, and
  everything is found automatically.
- **Linux, native Valheim:** everything works except launching, because the mod managers' native launch scripts differ
  between versions. Set `MTB_LAUNCH` to the command your mod manager uses. Its "copy launch arguments" option, or its
  log, shows it.
- **Windows:** the plugin works the same. There are two clients, which take the same commands and settings:
  - `mtb.cmd`, for PowerShell and cmd. It runs `claude-plugin/windows/mtb.ps1` with PowerShell 7 (`pwsh`) if it's
    installed, else with the Windows PowerShell that comes with Windows, so it needs nothing else installed. It gets
    past PowerShell's script execution policy itself.
    With `claude-plugin/bin` on your PATH, typing `mtb` runs it.
  - `mtb`, the bash script, for Git Bash. It needs curl and Python. Claude Code on Windows runs its commands in Git
    Bash, so that's the one Claude uses.

  Launching uses
  `steam.exe -applaunch 892970 --doorstop-enabled true --doorstop-target-assembly <profile>\BepInEx\core\BepInEx.Preloader.dll`,
  as Gale does. Steam is found through the registry. This is untested on real Windows so far, so reports and fixes are
  welcome.

Anything that can send HTTP can use the bridge without `mtb` (see below).

## A dedicated test server
For what only happens on a server: server-side patches, config sync, what one player sees of another's actions. `mtb`
runs a headless Valheim Dedicated Server on your machine, with your mod and the bridge in it, and drives it the same
way it drives the game. Put `server` first:
```
mtb server start                    # launch it with MTB_SERVER_WORLD (made the first time), wait until it's up
mtb server cmd "mymod_status"       # a console command in the server
mtb server run "mymod_test server" "[TEST] done" 300
mtb server tail 40                  # the server's BepInEx log
mtb server status                   # {"state":"world","dedicated":true,"players":[{"name":"Tester","position":[...]}],...}
mtb join                            # relaunch the game straight onto the test server as MTB_CHARACTER
mtb server restart                  # after deploying a new build of your mod to the server
mtb server stop                     # save its world and stop it
```
The game and the server each have their own bridge, log and token, so `mtb cmd ...` still talks to the game and
`mtb server cmd ...` to the server. A test of something that crosses the network does its part in each: set up in the
server, act in the game, check in either.

**Setting it up.**
1. **Install the server.** In Steam, under Library > Tools, install *Valheim Dedicated Server* (free). `mtb` finds it in
   your Steam libraries, or set `MTB_SERVER_DIR`.
2. **Give it BepInEx.** Unzip [BepInExPack_Valheim](https://thunderstore.io/c/valheim/p/denikson/BepInExPack_Valheim/)
   into the server's folder, the one with `valheim_server` in it. Or, to keep the server install clean, unzip it into a
   folder of its own and set `MTB_SERVER_PROFILE_DIR` to it: `mtb` starts the server with BepInEx from there.
3. **Add the plugins.** Put `ModTestBridge.dll`, your mod and the mods it needs under that folder's `BepInEx/plugins/`.
   Your mod's build can deploy there too.
4. **Turn the bridge on.** Write `BepInEx/config/Spronglehump.ModTestBridge.cfg` there, with these two lines:
   ```
   [General]
   Enabled = true
   ```
5. **Name the world** in `.mtb`, with `MTB_SERVER_WORLD=servertest`, then check with `mtb server doctor` and start it.

**What `mtb server start` does.**
- It launches `valheim_server` in the background with BepInEx loaded, its output in
  `<server profile>/BepInEx/ModTestBridge/server.out`.
- It uses the test world, made the first time, and the server's own save folder,
  `<server profile>/BepInEx/ModTestBridge/server-saves`, so test worlds never mix with your real ones.
- The server isn't listed publicly (`-public 0`). Without `MTB_SERVER_PASSWORD` it has no password, which a server that
  isn't public allows, so anyone on your network could join it while it runs. Set a password if that matters; `mtb join`
  passes it to the game.
- It backs up the world first, keeping the newest 5, and waits until the world is loaded.
- On Linux it starts the server as BepInExPack's `start_server_bepinex.sh` does; this is the tested setup. On Windows it
  starts `valheim_server.exe` with doorstop's `--doorstop-target-assembly` option, which is untested so far.
- `mtb server stop` and `restart` save the world, through the bridge, and only ever stop the server that `mtb` started.
  Other servers on the machine are left alone.

**Inside the server.**
- Commands run in the server's console, as the server. Those that act on "the player", like `spawn` or `pos`, have no
  player to act on there.
- The server's bridge listens on port 7812, so the game (7811) and the server can run together. Each takes the port
  from its own config.
- Screenshots need the game: a server has no screen.
- With BepInExPack's config, the game's own log lines and `Debug.Log` are in `LogOutput.log` too. `mtb server doctor`
  warns if `WriteUnityLog` is off.

**Joining it.** `mtb join [character] [host:port]` quits the game if it's running, backs up the character, then
launches the game straight onto the server (`127.0.0.1:2456` by default) and waits until the character is in the world.
Unlike `mtb restart`, the character doesn't need to have been there before. `mtb restart` goes back to the single-player
test world.
- **Give the server the game's mods.** Mods built on Jötunn refuse to join a server that lacks them, and the server
  turns the game away with `ErrorVersion`. `mtb join` then stops with `autostart refused: couldn't join the server
  (ErrorVersion)`, and the game's log says which mods are missing.

## Using it with Claude Code
Install the plugin. It adds the `valheim-mod-testing` skill and puts `mtb` on Claude's PATH:
```
/plugin marketplace add tmac1973/ModTestBridge
/plugin install modtestbridge@modtestbridge
```
Then ask something like "run the tests in game" or "restart the game and check the fix". The skill teaches Claude to:
- check the setup with `mtb doctor`;
- build and deploy, then restart;
- run your mod's test commands and read the results;
- look at the game with `mtb shot` when a log can't show the result, such as a model or a panel;
- leave the game in a good state.

It also asks before taking over the screen.

## How it works
- **Listening.** The plugin listens on `127.0.0.1:<Port>` (default 7811 in the game, 7812 in a dedicated server), never
  on other interfaces. Every request
  needs the header `X-Token: <contents of BepInEx/config/ModTestBridge.token>`.
- **The token.** You never make or copy it yourself:
  - The first time the plugin starts with `Enabled = true`, it writes a random token (a GUID, 32 hex characters) to
    `BepInEx/config/ModTestBridge.token` in the profile. Later starts reuse it.
  - `mtb` finds the profile and reads the file before every request, and `mtb doctor` says whether it's there.
  - A request without the right token gets `401 {"error": "bad or missing X-Token"}` and nothing runs.
  - It is there because 127.0.0.1 keeps out other machines but not other things on yours, such as a web page in your
    browser. Only something that can read files in your profile can drive the game.
  - To change it, delete the file and start the game again. You can also put your own value there (at least 16
    characters).
- **Threading.** Requests are queued and handled on the game's main thread, up to 8 a frame, so commands run exactly as
  if typed into the console.

| Endpoint | | Returns |
|---|---|---|
| `GET /status` | | `state` (`starting`, `menu`, `loading`, `world`), `world`, `character`, `position`, `server` (hosting the world), `dedicated`, `players` (when hosting: the others connected, with `name` and `position`), `fps`, `time`, `autostart`, `bridge` (version) |
| `POST /command` | body: the command (or `?c=`) | `{"command": "...", "output": [lines the console printed while it ran]}` |
| `GET /log?from=N&contains=TEXT` | | `{"from": N, "next": M, "lines": [...]}`: lines of `BepInEx/LogOutput.log` from line N (0-based), optionally only those containing TEXT; continue from `next` |
| `GET /screenshot?name=N&size=PX` | `&at=x,y,z&look=x,y,z&fov=D` for a camera of its own; `&day=1` for noon | `{"file", "relative" (to the profile), "width", "height", "mode" ("screen"/"camera"), "blank"}`: answers once the PNG is saved. 400 with `error` for a bad option, 409 when there's no camera yet |
| `POST /quit` | | Logs out (which saves the world and character), then quits at the main menu. A dedicated server saves its world and stops |

- **Commands.** These run with the console's checks skipped, but devcommands still has to be on for cheat commands, as
  in the console. Run `devcommands` once if your tests need them.
- **Output.** The output is what the console printed while the command ran. For things that take time, have your
  command write a log line when it's done, and wait for it with `/log` or `mtb wait-log`/`mtb run`.
- **Autostart.** Launch options `-mtb-world <name> -mtb-character <name>` take the main menu's own path:
  1. choose the character;
  2. Start;
  3. choose the world;
  4. Start, as a single-player game that isn't open to others.

  The character is really loaded: no intro, and no new character at the spawn stones. Autostart refuses, staying at the
  menu with the reason in `/status`'s `autostart` and in the log, unless the character exists and has been in that
  world before.

  With `-mtb-server <host:port>` in place of `-mtb-world`, it joins that server with the character instead. Valheim's
  own `-password <password>` answers the server's password prompt.

Example with curl:
```
TOKEN=$(cat ~/.local/share/com.kesomannen.gale/valheim/profiles/mymod-dev/BepInEx/config/ModTestBridge.token)
curl -s -H "X-Token: $TOKEN" http://127.0.0.1:7811/status
curl -s -H "X-Token: $TOKEN" --data-binary "pos" http://127.0.0.1:7811/command
curl -s -H "X-Token: $TOKEN" "http://127.0.0.1:7811/screenshot?name=check&day=1"
```

## Building
- Needs the .NET SDK, plus Valheim and a BepInEx profile to compile against.
- Copy `ModTestBridge.user.props.example` to `ModTestBridge.user.props` and set `ValheimDir` and `GaleProfileDirs`.
- `dotnet build -c Release` builds and copies the DLL into each profile in `GaleProfileDirs`.
- `dotnet test` runs the unit tests.
- `dotnet build -c Release src/ModTestBridge -t:Package` makes the Thunderstore/Hexium zip in `dist/`.

## License
MIT. See [LICENSE](LICENSE).

# ModTestBridge

**Drive Valheim from scripts, or from an AI coding agent, while you develop mods.**

ModTestBridge is a small BepInEx plugin for mod developers. It lets anything on your own machine:
- run console commands in the running game and get back what they printed;
- read the BepInEx log;
- see the game's state: menu or in a world, which world, which character, where;
- quit cleanly, saving first;
- relaunch the game straight into a test world with an existing character, skipping the menus.

Together these close the loop for automated testing:
1. build your mod;
2. `mtb restart`;
3. run your mod's test commands;
4. read the results;
5. fix, and repeat.

Nobody needs to click through menus or copy log lines by hand. It's how
[Hired Hands](https://github.com/tmac1973/HiredHands) is developed: Claude Code builds, restarts, runs the in-game
tests and reads the failures, while a human plays and judges how it feels.

It works with any mod, because it doesn't know about yours. Your mod keeps its own test commands, and the bridge runs
them. See [Writing tests for your mod](docs/writing-tests.md).

> [!WARNING]
> **Development profiles only.** Never install it on a server or on a profile you play on. Anything on your computer
> that can reach the port with the token can run console commands. It only listens on 127.0.0.1, and it is **off until
> you turn it on**.

What's here:
- **The plugin**, under `src/`. Download it from [Releases](https://github.com/tmac1973/ModTestBridge/releases), or from
  Hexium/Thunderstore as `Spronglehump-ModTestBridge`.
- **`mtb`**, a command-line client, in `claude-plugin/bin/mtb`. It is bash with curl and python3.
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
mtb quit                            # save, log out, quit
mtb restart [world] [character]     # quit if running, back up the saves, relaunch straight into the world, wait for it
mtb start [world] [character]       # the same, when the game isn't running
mtb backup                          # back up the test character and world now (game not running)
mtb profiles                        # mod-manager profiles with ModTestBridge installed
mtb doctor                          # what mtb found, and whether the game answers
```

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
- leave the game in a good state.

It also asks before taking over the screen.

## How it works
- **Listening.** The plugin listens on `127.0.0.1:<Port>` (default 7811), never on other interfaces. Every request
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
| `GET /status` | | `state` (`starting`, `menu`, `loading`, `world`), `world`, `character`, `position`, `server`, `fps`, `time`, `autostart`, `bridge` (version) |
| `POST /command` | body: the command (or `?c=`) | `{"command": "...", "output": [lines the console printed while it ran]}` |
| `GET /log?from=N&contains=TEXT` | | `{"from": N, "next": M, "lines": [...]}`: lines of `BepInEx/LogOutput.log` from line N (0-based), optionally only those containing TEXT; continue from `next` |
| `POST /quit` | | Logs out (which saves the world and character), then quits at the main menu |

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

Example with curl:
```
TOKEN=$(cat ~/.local/share/com.kesomannen.gale/valheim/profiles/mymod-dev/BepInEx/config/ModTestBridge.token)
curl -s -H "X-Token: $TOKEN" http://127.0.0.1:7811/status
curl -s -H "X-Token: $TOKEN" --data-binary "pos" http://127.0.0.1:7811/command
```

## Building
- Needs the .NET SDK, plus Valheim and a BepInEx profile to compile against.
- Copy `ModTestBridge.user.props.example` to `ModTestBridge.user.props` and set `ValheimDir` and `GaleProfileDirs`.
- `dotnet build -c Release` builds and copies the DLL into each profile in `GaleProfileDirs`.
- `dotnet test` runs the unit tests.
- `dotnet build -c Release src/ModTestBridge -t:Package` makes the Thunderstore/Hexium zip in `dist/`.

## License
MIT. See [LICENSE](LICENSE).

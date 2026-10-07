# ModTestBridge

A development-only BepInEx plugin for Valheim that lets scripts drive the game while you develop mods: run console
commands and get back what they printed, read the BepInEx log, check the game's state, and quit cleanly. Mod-agnostic:
each mod keeps its own test commands (Hired Hands' `vfh_test_chain`, say), and the bridge just runs them.

**Development profiles only.** Never install it on a server or a profile you play on: anything that can reach the port
with the token can run console commands.

## How it works
- Listens on `127.0.0.1:7811` (setting `Port`) only. Every request needs the `X-Token` header, whose value the plugin
  writes to `BepInEx/config/ModTestBridge.token` on first run.
- Requests are queued and handled on the game's main thread.
- `GET /status`: `state` (`starting`, `menu`, `loading`, `world`), world, character, position, server, fps.
- `POST /command` (body: the console command): runs it as if typed in the console (devcommands rules apply for cheat
  commands) and returns the lines the console printed while it ran.
- `GET /log?from=N&contains=TEXT`: BepInEx `LogOutput.log` lines from line N, optionally only those containing TEXT, and
  `next` (the line to continue from).
- `POST /quit`: logs out (saving world and character), then quits the game.
- **Autostart:** launch options `-mtb-world <name> -mtb-character <name>` skip the menus into that single-player world with
  that character, through the menu's own Start path (the character really loads: no intro, no new character at the spawn
  stones). It refuses, staying at the menu with the reason in `/status`'s `autostart`, unless the character exists and has
  been in that world before.

## Client
`scripts/mtb` (bash + curl + python3):
```
mtb status
mtb cmd "vfh_test_chain pass"
mtb log 0 "[VFH]"
mtb wait-log "row=VFH-PASS-1 pass=" 900
mtb wait-world
mtb quit
mtb restart [world] [character]   # save, quit, back up the saves, relaunch into the world, wait for it
```
`mtb restart` / `mtb start` relaunch through Steam the way Gale launches the profile (`MTB_PROFILE`), and back up the
character and world (Steam Cloud and local saves) to `BepInEx/ModTestBridge/backups` first, keeping the newest 5.
`MTB_WORLD` / `MTB_CHARACTER` set the defaults (testboy / Testboy).
`MTB_PROFILE` picks the Gale profile whose token to use (default `vikingsforhire-dev`); `MTB_PORT` the port.

## Build
`dotnet build -c Release` builds and copies the DLL into each profile in `GaleProfileDirs` (see
`ModTestBridge.user.props.example`). `dotnet test` runs the unit tests.

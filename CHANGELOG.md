# Changelog

## 0.3.0
- A dedicated test server: the plugin also runs in `valheim_server`, where it listens on port 7812 (the game keeps 7811,
  so both run side by side). Console commands, the log and `/status` work there: `state` is `world` once the server's
  world is loaded, and `/status` has `dedicated` and the connected `players` with their positions. `/quit` saves the
  world and stops the server.
- `mtb server start|restart|stop|backup [world]`: launch a headless server with BepInEx, a test world (created when it's
  new) and its own save folder, not listed publicly, and wait until it's up. `mtb server status|cmd|run|log|mark|tail|
  wait-log|wait-world|doctor` do what they do in the game, in the server. Only the server mtb started is ever stopped.
- `mtb join [character]`: relaunch the game straight onto the test server with the test character (autostart's new
  `-mtb-server host:port`).
- The example mod has a server-side test (`global_key`); `example_test all` skips tests that need a player of its own on
  a dedicated server.
- `mtb backup` also finds world saves whose names aren't lower case.

## 0.2.1
- Screenshots: a failure while taking or saving one now answers 500 with the reason, instead of leaving `mtb shot`
  waiting out its timeout. Overlapping `--day` shots no longer leave the game stuck at noon.
- README: screenshots in the overview, name and option limits, errors; the Windows client under "What's here".

## 0.2.0
- Screenshots: `mtb shot [name]` saves what the player sees (UI included), or with `--at x,y,z --look x,y,z` a picture
  from a camera of its own; `--size` (768 by default), `--fov`, `--day` (noon for the shot). Prints the PNG's path and
  says when the picture came out black (a minimised window). New endpoint `GET /screenshot`.
- `mtb.cmd`, a Windows client for PowerShell and cmd that needs no Git Bash, curl or Python.
- README: how the token is made and used.

## 0.1.0
- First release: a local HTTP bridge (127.0.0.1, token) to run console commands and get their output, read the BepInEx
  log, see the game's state, and quit cleanly.
- Autostart (`-mtb-world`, `-mtb-character`) straight into a single-player world with an existing character.
- `mtb`, the command-line client: run and wait for results, restart into the world with save backups, `doctor`.
- A Claude Code plugin (skill + `mtb`) for testing mods with an agent.
- Off by default: set `Enabled = true` on your development profile.

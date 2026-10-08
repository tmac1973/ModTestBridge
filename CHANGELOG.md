# Changelog

## Unreleased
- `mtb.cmd`, a Windows client for PowerShell and cmd that needs no Git Bash, curl or Python.
- README: how the token is made and used.

## 0.1.0
- First release: a local HTTP bridge (127.0.0.1, token) to run console commands and get their output, read the BepInEx
  log, see the game's state, and quit cleanly.
- Autostart (`-mtb-world`, `-mtb-character`) straight into a single-player world with an existing character.
- `mtb`, the command-line client: run and wait for results, restart into the world with save backups, `doctor`.
- A Claude Code plugin (skill + `mtb`) for testing mods with an agent.
- Off by default: set `Enabled = true` on your development profile.

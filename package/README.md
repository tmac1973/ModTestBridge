# ModTestBridge

**For mod developers, not players.** If you just play Valheim, you don't need this.

This mod lets scripts, or an AI coding agent such as Claude Code, drive Valheim while you develop a mod:
- run console commands and get back what they printed;
- read the BepInEx log;
- see whether you're at the menu or in a world, and where;
- quit cleanly, saving first;
- relaunch straight into a test world with an existing character, with no menus.

Your mod keeps its own in-game test commands; the bridge just runs them and reads the results. So you build, restart,
test and read the failures without clicking through anything.

## ⚠️ Development profiles only
- **Off until you turn it on:** set `Enabled = true` in `BepInEx/config/Spronglehump.ModTestBridge.cfg`.
- It listens on 127.0.0.1 only, and every request needs a random token.
- Even so, anything on your computer with that token can run console commands. Never install it on a server or on a
  profile you play on.

## Everything else is on GitHub
**https://github.com/tmac1973/ModTestBridge**

You'll find:
- **setup and the full guide:** the HTTP API, autostart, backups;
- **`mtb`**, the command-line client: `mtb restart`, `mtb run "mymod_test all" "[TEST] done"`, `mtb doctor`...;
- **the Claude Code plugin**, a skill that teaches Claude to test your mod in-game:
  `/plugin marketplace add tmac1973/ModTestBridge`;
- **how to write in-game tests for your mod**, with an example mod and a test-runner script.

---
name: valheim-mod-testing
description: Test a Valheim (BepInEx) mod in the running game through ModTestBridge and the mtb command. Use this when asked to run a mod's in-game tests, check a fix in game, restart Valheim into the test world, run console commands in Valheim, or read the game's BepInEx log, and also when setting up ModTestBridge or writing in-game test commands for a mod.
---

# Testing a Valheim mod in the running game

ModTestBridge is a dev-only BepInEx plugin that the `mtb` command (on your PATH from this plugin) talks to. With it,
you can drive the real game:
- run console commands and read what they printed;
- read the BepInEx log;
- see the game's state;
- quit cleanly;
- relaunch straight into a test world with an existing character.

The mod under development provides its own test commands. You run them and read the results.

Run `mtb help` for every command. The ones you'll use most:

| Command | What it does |
|---|---|
| `mtb doctor` | What mtb found (profile, token, launch command, saves) and whether the game answers. **Start here.** |
| `mtb status` | JSON: `state` (`starting`/`menu`/`loading`/`world`), world, character, position, `autostart` |
| `mtb cmd "<command>"` | Run a console command, print its console output |
| `mtb mark` | The log's current line number. Take it before running tests. |
| `mtb run "<command>" "<text>" [timeout]` | Run a command, then wait for a new log line containing the text (the test's "done" line) |
| `mtb log <mark> "<text>"` | Log lines since the mark, only those containing the text |
| `mtb tail [n] [text]` | The last n log lines |
| `mtb restart` | Save and quit, back up the test saves, relaunch into `MTB_WORLD` as `MTB_CHARACTER`, wait until in the world (~40 s) |
| `mtb quit` | Save, log out, quit |

## Before you start
1. **Check the setup.** Run `mtb doctor`. If something is marked `??`, help the user fix it rather than working around
   it; [setup](#setting-up) is below.
2. **Find the mod's tests.** Look for its test commands and what their result lines look like:
   - the README, or a test checklist;
   - `new Terminal.ConsoleCommand(` in the source;
   - a macros/alias file;
   - a project `CLAUDE.md`.

   Note the command that runs them, the line that means "finished", and how a pass and a failure look. If the mod has
   none yet, offer to write some; [writing tests](#writing-tests-for-a-mod) is below.
3. **Find how the mod builds and deploys** into the dev profile, such as `dotnet build` with a deploy step. Never
   deploy into a profile someone plays on, or onto a server.

## The loop
1. **Build and deploy** the mod.
2. **Restart, if the code changed.** A new DLL needs `mtb restart`; config or data files can often be reloaded live.
   - Restarting brings the game window to the front and kicks out anyone playing. If the user may be at the computer,
     **ask before restarting**.
   - `mtb restart` backs up the test character and world first.
   - If it reports `autostart refused: ...`, read the reason. Usually the character has never been in that world: the
     user must play into it by hand once.
3. **Run.**
   ```
   mark=$(mtb mark)
   mtb run "<test command>" "<done line>" <timeout seconds>
   ```
   - Pick a timeout that fits the tests. In-game tests can take minutes, so run long ones with the Bash tool's
     background option or a generous timeout.
   - `mtb cmd` returns as soon as the command starts. The test's progress is in the log, not in the command's output.
4. **Read.**
   - `mtb log $mark "<result marker>"` lists the results.
   - `mtb log $mark "pass=false"` (or the mod's own failure marker) lists what failed.
   - `mtb tail 80` shows the context around a failure.
   - Report each failure with its expected and actual values.
5. **Fix and repeat.** When you're done, leave the game in the world. Don't quit unless asked, because the user may want
   to look.

If a test hangs, use the mod's abort command if it has one. Otherwise run `mtb restart`, after asking.

## Rules
- **Dev profiles only.** Don't install or enable ModTestBridge on a profile someone plays on, or on a server.
- **The game is the user's.** Ask before `mtb restart`, `mtb quit`, or anything that changes their world in ways a test
  wouldn't, such as deleting things they built or teleporting them far away. Tests should clean up after themselves.
- **Cheat commands need `devcommands` on.** Turn it on in the test setup, or once with `mtb cmd devcommands`. Note that
  running `devcommands` again toggles it off.
- **Report faithfully.** Give the counts of passed and failed tests, and quote the failing checks. Don't call it fixed
  until the test that failed passes.

## Setting up
The user does these steps, guided by you:
1. **Install the plugin.** Install `ModTestBridge` into a development profile with Gale or r2modman (it's
   `Spronglehump-ModTestBridge`), or from https://github.com/tmac1973/ModTestBridge/releases.
2. **Turn it on.** Run the game once, then set `Enabled = true` in
   `<profile>/BepInEx/config/Spronglehump.ModTestBridge.cfg`. Start the game again: it writes
   `BepInEx/config/ModTestBridge.token`.
3. **Make a test world and character.** Create them, and play into the world by hand once.
   - Moving both to local saves rather than Steam Cloud is kinder to Steam Cloud.
4. **Tell mtb about them** in a `.mtb` file in the mod's repo (`KEY=value` lines):
   ```
   MTB_PROFILE=<profile name>      # or MTB_PROFILE_DIR=<folder holding BepInEx>
   MTB_WORLD=<world>
   MTB_CHARACTER=<character>
   ```
   On native-Linux Valheim (not Proton), also set `MTB_LAUNCH` to the mod manager's launch command. See the
   repository's README, "Configuring mtb".
5. **Check it.** `mtb doctor` should show the profile, `enabled: true`, a token, a launch command, and the bridge
   answering.

## Writing tests for a mod
If the mod has no tests, propose test commands in this pattern:
- `mymod_test <name|all|list>` runs tests as Unity coroutines. Each test:
  1. sets up near the player (flat ground, cleared area, devcommands on);
  2. waits for a condition, with a deadline;
  3. checks, logging each check with `pass=` and the actual value;
  4. cleans up, even on failure;
  5. logs one result line: `[TEST] result name=<n> pass=<bool> ...`.
- After the last test it logs `[TEST] done passed=N failed=M`.
- `mymod_test_abort` stops whatever is running, and cleans up.
- Log at Info or above. `LogOutput.log` doesn't get Debug lines.

The repository has a complete, compilable example (`examples/ExampleTests/ExampleTests.cs`), a script that runs it
(`examples/run-tests.sh`), and a guide (`docs/writing-tests.md`). Fetch them from
https://github.com/tmac1973/ModTestBridge if they're not local.

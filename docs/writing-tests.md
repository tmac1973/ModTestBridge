# Writing tests for your mod

ModTestBridge doesn't know anything about your mod. All it does is run console commands and read the log. So the way
to make your mod testable is to give it **test commands**:
- a test sets up a situation in the live game;
- it waits for your mod to act;
- it checks what happened;
- it cleans up;
- it writes a result line that a script (or an agent) can find.

`examples/ExampleTests` is a complete, small version of this pattern, and `examples/run-tests.sh` runs it. The advice
below comes from building the much larger harness in [Hired Hands](https://github.com/tmac1973/HiredHands): about 80
tests of hireling AI, run many times a day by Claude Code.

## The shape
```
mymod_test list                 what tests there are
mymod_test <name>               one test
mymod_test all                  all of them, one after another
mymod_test_abort                stop whatever is running, and clean up
```
Each test is a coroutine. Unity coroutines are what let a test wait for the game to move on:
1. **set up**: spawn what it needs near the player, and clear the area;
2. **wait**: for something to happen, with a deadline;
3. **check**: log each check as `pass=true` or `pass=false`, with the expected and actual values;
4. **clean up**: even if it failed;
5. **report**: log exactly one result line.

Finish with a line saying the whole run is over:
```
[TEST] check name=wood_drops what="5 wood landed nearby" pass=false actual=3
[TEST] result name=wood_drops pass=false checks=2 failed=1
[TEST] done passed=4 failed=1
```
Then this one call runs everything and waits for the end:
```
mtb run "mymod_test all" "[TEST] done" 900
```
Afterwards, `mtb log <mark> "[TEST] result"` lists the results, and `mtb log <mark> "pass=false"` lists the failures.
Get `<mark>` from `mtb mark` before starting.

## Lessons learned
- **Log at Info or above.** `LogOutput.log` (what the bridge reads) only gets BepInEx's Info, Warning and Error
  levels by default. Debug lines can go to a file of your own.
- **Make lines easy to find.** Use a fixed prefix and `key=value` pairs, and keep one fact per line. Names should be
  stable, so a search like `name=wood_drops pass=` always works.
- **Wait for a result rather than sleeping a fixed time.** Write checks as "becomes true within N seconds". They poll
  every half second and pass as soon as it's true, which makes the tests both faster and less flaky. Log how long each
  one waited: slow passes tell you something too.
- **Clean up everything you spawn, and kill quietly.** Tests that leave things behind poison the next test. In
  Valheim, killing a creature carrying items makes a grave and a map marker, so empty inventories before you remove
  anything.
- **Test somewhere neutral.**
  - Teleport, or set up, away from the player's base, on flat ground.
  - Flatten or clear the terrain in the setup step. Logs rolling off a cliff will fail a woodcutting test for reasons
    that have nothing to do with your code.
  - Freeze the time of day, or the weather, if they matter.
- **Run one test at a time,** with an abort command. A test that hangs should be stoppable without restarting the game.
- **Turn devcommands on in the setup step,** if the setup needs cheats such as spawning items or god mode.
- **Keep fixtures and checks separate.**
  - Fixtures are commands that build a situation, like "a chest with 20 wood".
  - Checks are commands that measure it, like "count of wood in chests >= 20".
  - Tests are then short lists of fixtures and checks. In Hired Hands they live in a YAML file of console macros, which
    the mod reloads without a restart, so new tests don't need a rebuild.
- **Log the facts that explain a failure,** not just the verdict. `actual=3` saves a round trip, and so does the AI's
  current state in an AI mod. An agent reading the log can only fix what the log tells it.
- **Restart only when the code changed.** Config and data changes can often be reloaded live. Have a reload command if
  your mod supports it, because a restart costs about 40 seconds.

## A loop for an agent
This is what the Claude Code skill in this repo teaches:
1. **Build and deploy** the mod into the dev profile.
2. **Restart** with `mtb restart`, after asking if someone's at the computer.
3. **Run** with `mtb mark`, then `mtb run "<test command>" "<done line>" <timeout>`.
4. **Read** `mtb log <mark> "result"` and the failed checks. `mtb tail 80` shows the context around them.
5. **Fix** the code, and go back to step 1. When it's green, leave the game running in the world.

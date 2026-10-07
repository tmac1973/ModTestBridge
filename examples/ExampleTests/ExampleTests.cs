using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using BepInEx;
using UnityEngine;

namespace ExampleTests
{
    /// <summary>
    /// The pattern ModTestBridge is built for: a mod's tests are console commands that set up a scene in the live game,
    /// wait for things to happen, check the result, clean up, and write one easy-to-find log line per test. A script or
    /// an agent then runs <c>mtb run "example_test all" "[TEST] done"</c> and reads the result lines.
    ///
    ///   example_test list          the tests
    ///   example_test &lt;name&gt;       one test
    ///   example_test all           every test, one after another, then "[TEST] done passed=N failed=M"
    /// </summary>
    [BepInPlugin("Example.ExampleTests", "ExampleTests", "0.1.0")]
    public sealed class ExampleTestsPlugin : BaseUnityPlugin
    {
        private delegate IEnumerator Test(Checks checks);

        // Name -> test. A test is a coroutine: it can wait (yield) for the game to move on before checking.
        private static readonly Dictionary<string, Test> Tests = new()
        {
            ["wood_drops"] = WoodDrops,
            ["player_alive"] = PlayerAlive,
        };

        private static ExampleTestsPlugin? _instance;
        private bool _running;

        private void Awake()
        {
            _instance = this;
            new Terminal.ConsoleCommand("example_test", "[name|all|list] run example tests", args =>
            {
                string which = args.Length > 1 ? args[1] : "list";
                if (which == "list")
                {
                    args.Context.AddString("tests: " + string.Join(", ", Tests.Keys));
                    return;
                }
                if (_running)
                {
                    args.Context.AddString("tests are already running");
                    return;
                }
                List<string> names = which == "all" ? Tests.Keys.ToList() : new List<string> { which };
                if (names.Any(n => !Tests.ContainsKey(n)))
                {
                    args.Context.AddString($"no test named {which}");
                    return;
                }
                args.Context.AddString($"running {string.Join(", ", names)}");   // mtb cmd/run prints this
                StartCoroutine(Run(names));
            });
        }

        private IEnumerator Run(List<string> names)
        {
            _running = true;
            int passed = 0, failed = 0;
            foreach (string name in names)
            {
                var checks = new Checks(name);
                // One test throwing must not stop the rest, so step the coroutine by hand.
                IEnumerator test = Tests[name](checks);
                while (true)
                {
                    object? current;
                    try
                    {
                        if (!test.MoveNext())
                            break;
                        current = test.Current;
                    }
                    catch (Exception e)
                    {
                        checks.That("no exception", false, e.Message);
                        break;
                    }
                    yield return current;
                }
                bool pass = checks.Failed == 0;
                if (pass) passed++; else failed++;
                Log(pass, $"[TEST] result name={name} pass={(pass ? "true" : "false")} checks={checks.Count} failed={checks.Failed}");
            }
            Log(failed == 0, $"[TEST] done passed={passed} failed={failed}");
            _running = false;
        }

        private static void Log(bool ok, string line)
        {
            if (ok) _instance!.Logger.LogInfo(line); else _instance!.Logger.LogWarning(line);
        }

        /// <summary>Each check is logged as it's made, so a failure says what was expected and what was there.</summary>
        private sealed class Checks
        {
            private readonly string _test;
            public int Count, Failed;
            public Checks(string test) => _test = test;

            public void That(string what, bool ok, object? actual = null)
            {
                Count++;
                if (!ok) Failed++;
                Log(ok, $"[TEST] check name={_test} what=\"{what}\" pass={(ok ? "true" : "false")}" + (actual != null ? $" actual={actual}" : ""));
            }
        }

        // --- the tests ------------------------------------------------------------------------------------------------

        // Spawn some wood in front of the player, let physics settle, count it, clean up.
        private static IEnumerator WoodDrops(Checks checks)
        {
            Player p = Player.m_localPlayer;
            checks.That("in a world", p != null);
            if (p == null)
                yield break;
            GameObject prefab = ZNetScene.instance.GetPrefab("Wood");
            Vector3 at = p.transform.position + p.transform.forward * 3f + Vector3.up;
            var spawned = new List<GameObject>();
            for (int i = 0; i < 5; i++)
                spawned.Add(Instantiate(prefab, at + UnityEngine.Random.insideUnitSphere * 0.5f, Quaternion.identity));

            yield return new WaitForSeconds(2f);   // let it fall and settle

            int near = ItemDrop.s_instances.Count(d => d != null && d.m_itemData.m_shared.m_name == "$item_wood"
                                                      && Vector3.Distance(d.transform.position, at) < 6f);
            checks.That("5 wood landed nearby", near >= 5, near);

            foreach (GameObject go in spawned)
                if (go != null)
                    ZNetScene.instance.Destroy(go);   // tests clean up after themselves
        }

        private static IEnumerator PlayerAlive(Checks checks)
        {
            Player p = Player.m_localPlayer;
            checks.That("in a world", p != null);
            checks.That("not dead", p != null && !p.IsDead());
            yield break;
        }
    }
}

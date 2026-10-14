using System;
using System.Collections;
using System.IO;
using System.Linq;
using BepInEx;
using HarmonyLib;
using UnityEngine;

namespace ModTestBridge
{
    /// <summary>
    /// Launch options: <c>-mtb-world &lt;name&gt; -mtb-character &lt;name&gt;</c> skip the menus into that single-player world
    /// with that character, the way the menu's own buttons do (so the character really is loaded: no intro, no new
    /// character at the spawn stones). It refuses (staying at
    /// the menu, with the reason in /status and the log) unless the character exists and has been in that world before.
    /// Or <c>-mtb-server &lt;host:port&gt; -mtb-character &lt;name&gt;</c>: join that server with that character (Valheim's
    /// own <c>-password</c> option answers a password prompt). Only on the first visit to the main menu.
    /// </summary>
    [HarmonyPatch]
    internal static class AutoStart
    {
        private static bool _done;

        /// <summary>What the last autostart did (for /status).</summary>
        public static string State { get; private set; } = "off";

        private static string? Arg(string name)
        {
            string[] args = Environment.GetCommandLineArgs();
            int i = Array.FindIndex(args, a => string.Equals(a, name, StringComparison.OrdinalIgnoreCase));
            return i >= 0 && i + 1 < args.Length && !args[i + 1].StartsWith("-") ? args[i + 1] : null;
        }

        [HarmonyPostfix]
        [HarmonyPatch(typeof(FejdStartup), nameof(FejdStartup.Start))]
        private static void OnMenu(FejdStartup __instance)
        {
            if (_done)
                return;
            _done = true;
            string? world = Arg("-mtb-world"), server = Arg("-mtb-server"), character = Arg("-mtb-character");
            if ((world == null && server == null) || character == null)
                return;
            State = "pending";
            __instance.StartCoroutine(server != null ? Join(__instance, server, character) : Run(__instance, world!, character));
        }

        private static PlayerProfile? FindProfile(string characterName) =>
            SaveSystem.GetAllPlayerProfiles()
                .FirstOrDefault(p => string.Equals(p.GetName(), characterName, StringComparison.OrdinalIgnoreCase));

        private static IEnumerator Join(FejdStartup menu, string server, string characterName)
        {
            yield return new WaitForSeconds(2f); // the menu and its character list settle
            try
            {
                PlayerProfile? profile = FindProfile(characterName);
                if (profile == null)
                {
                    Fail($"no character named {characterName}");
                    yield break;
                }
                var join = new ServerJoinDataDedicated(server);
                if (join.m_host == null)
                {
                    Fail($"can't read the server address {server} (host:port)");
                    yield break;
                }
                // The menu's own path for a queued join: Start with this character, which then joins the server.
                menu.SetSelectedProfile(profile.GetFilename());
                menu.m_queuedJoinServer = new ServerJoinData(join);
                State = $"joining {server} as {profile.GetName()}";
                Debug.Log($"ModTestBridge: autostart {State}");
                menu.OnCharacterStart();
            }
            catch (Exception e)
            {
                Fail(e.Message);
            }
        }

        private static IEnumerator Run(FejdStartup menu, string worldName, string characterName)
        {
            yield return new WaitForSeconds(2f); // the menu and its character list settle
            try
            {
                PlayerProfile? profile = FindProfile(characterName);
                if (profile == null)
                {
                    Fail($"no character named {characterName}");
                    yield break;
                }
                menu.SetSelectedProfile(profile.GetFilename());
                menu.UpdateWorldList(true);
                World? world = menu.FindWorld(worldName);
                if (world == null)
                {
                    Fail($"no world named {worldName}");
                    yield break;
                }
                if (!profile.m_worldData.ContainsKey(world.m_uid))
                {
                    Fail($"{characterName} has never been in {worldName}: start it by hand once");
                    yield break;
                }
                // The menu's own path: Start with this character (loads it into the game), then this world.
                menu.OnCharacterStart();
                menu.m_world = world;
                menu.m_openServerToggle.isOn = false;
                menu.m_publicServerToggle.isOn = false;
                State = $"starting {worldName} as {profile.GetName()}";
                Debug.Log($"ModTestBridge: autostart {State}");
                menu.OnWorldStart();
            }
            catch (Exception e)
            {
                Fail(e.Message);
            }
        }

        private static void Fail(string why)
        {
            State = "refused: " + why;
            Debug.LogWarning("ModTestBridge: autostart " + State);
        }
    }
}

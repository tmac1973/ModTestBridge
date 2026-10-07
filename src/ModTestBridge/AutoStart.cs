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
    /// character at the spawn stones). Before starting it backs up the character and world saves, and it refuses (staying at
    /// the menu, with the reason in /status and the log) unless the character exists and has been in that world before.
    /// Only on the first visit to the main menu.
    /// </summary>
    [HarmonyPatch]
    internal static class AutoStart
    {
        private const int KeepBackups = 5;
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
            string? world = Arg("-mtb-world"), character = Arg("-mtb-character");
            if (world == null || character == null)
                return;
            State = "pending";
            __instance.StartCoroutine(Run(__instance, world, character));
        }

        private static IEnumerator Run(FejdStartup menu, string worldName, string characterName)
        {
            yield return new WaitForSeconds(2f); // the menu and its character list settle
            try
            {
                PlayerProfile? profile = SaveSystem.GetAllPlayerProfiles()
                    .FirstOrDefault(p => string.Equals(p.GetName(), characterName, StringComparison.OrdinalIgnoreCase));
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
                Backup(profile, world);
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

        // Copies of the character and world saves, newest few kept, in BepInEx/ModTestBridge/backups.
        private static void Backup(PlayerProfile profile, World world)
        {
            string root = Path.Combine(Paths.BepInExRootPath, "ModTestBridge", "backups");
            string dir = Path.Combine(root, DateTime.Now.ToString("yyyyMMdd-HHmmss"));
            Directory.CreateDirectory(dir);
            foreach (string file in new[]
                     {
                         SaveSystem.GetCharacterPath(profile.m_fileSource, profile.GetFilename()),
                         world.GetDBPath(), world.GetMetaPath(),
                     })
                if (File.Exists(file))
                    File.Copy(file, Path.Combine(dir, Path.GetFileName(file)), true);
            foreach (string old in Directory.GetDirectories(root).OrderByDescending(d => d).Skip(KeepBackups))
                Directory.Delete(old, true);
            Debug.Log($"ModTestBridge: backed up {profile.GetName()} and {world.m_name} to {dir}");
        }
    }
}

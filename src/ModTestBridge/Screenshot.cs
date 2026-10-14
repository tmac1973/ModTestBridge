using System;
using System.Collections;
using System.IO;
using System.Net;
using BepInEx;
using ModTestBridge.Core;
using UnityEngine;

namespace ModTestBridge
{
    /// <summary>
    /// /screenshot: a PNG of what the player sees (UI included), or from a camera of its own at a point looking at another
    /// (no UI; the player's view is left alone). Saved under BepInEx/ModTestBridge/screenshots, scaled down to a size an
    /// agent can read cheaply.
    /// </summary>
    internal static class Screenshot
    {
        public const string Folder = "ModTestBridge/screenshots";
        public const string NoCamera = "no camera yet (in the world or at the menu?)";

        // --day shots in progress. They can overlap, so the first saves the time of day and the last puts it back.
        private static int _dayShots;
        private static bool _wasDebug;
        private static float _wasTime;

        public static IEnumerator Take(HttpListenerContext ctx, ShotOptions o)
        {
            bool day = o.Day && EnvMan.instance != null;
            if (day)
                BeginDay();
            Texture2D? image = null;
            string? error = null;
            try
            {
                if (day)
                    for (int i = 0; i < 5; i++)
                        yield return null; // the sun and the light settle
                if (!o.FromCamera)
                    yield return new WaitForEndOfFrame(); // everything drawn, UI included
                try
                {
                    image = o.FromCamera ? FromCamera(o) : FromScreen(o);
                }
                catch (Exception e)
                {
                    error = e.Message;
                }
            }
            finally
            {
                if (day)
                    EndDay();
            }

            if (error != null)
            {
                Fail(ctx, error);
                yield break;
            }
            if (image == null)
            {
                Plugin.Respond(ctx, 409, Json.Obj(("error", NoCamera)));
                yield break;
            }
            try
            {
                bool blank = ShotOptions.LooksBlank(image.GetRawTextureData());
                string relative = Path.Combine("BepInEx", Folder, o.Name + ".png").Replace('\\', '/');
                string file = Path.Combine(Paths.BepInExRootPath, Folder, o.Name + ".png");
                Directory.CreateDirectory(Path.GetDirectoryName(file)!);
                File.WriteAllBytes(file, image.EncodeToPNG());
                Plugin.Log($"ModTestBridge screenshot: {relative} {image.width}x{image.height}{(blank ? " (blank)" : "")}");
                Plugin.Respond(ctx, 200, Json.Obj(
                    ("file", file), ("relative", relative), ("width", image.width), ("height", image.height),
                    ("mode", o.FromCamera ? "camera" : "screen"), ("blank", blank)));
            }
            catch (Exception e)
            {
                Fail(ctx, e.Message);
            }
            finally
            {
                UnityEngine.Object.Destroy(image);
            }
        }

        // Every request gets an answer, or the client waits out its timeout and learns nothing.
        private static void Fail(HttpListenerContext ctx, string error)
        {
            Plugin.Log($"ModTestBridge screenshot failed: {error}");
            Plugin.Respond(ctx, 500, Json.Obj(("error", "screenshot failed: " + error)));
        }

        private static void BeginDay()
        {
            if (_dayShots++ == 0)
            {
                _wasDebug = EnvMan.instance!.m_debugTimeOfDay;
                _wasTime = EnvMan.instance.m_debugTime;
            }
            EnvMan.instance!.m_debugTimeOfDay = true;
            EnvMan.instance.m_debugTime = 0.5f;
        }

        private static void EndDay()
        {
            if (--_dayShots == 0 && EnvMan.instance != null)
            {
                EnvMan.instance.m_debugTimeOfDay = _wasDebug;
                EnvMan.instance.m_debugTime = _wasTime;
            }
        }

        private static Texture2D? FromScreen(ShotOptions o)
        {
            Texture2D full = ScreenCapture.CaptureScreenshotAsTexture();
            try
            {
                (int w, int h) = ShotOptions.Fit(full.width, full.height, o.Size);
                RenderTexture rt = RenderTexture.GetTemporary(w, h, 0);
                try
                {
                    Graphics.Blit(full, rt);
                    return Read(rt);
                }
                finally
                {
                    RenderTexture.ReleaseTemporary(rt);
                }
            }
            finally
            {
                UnityEngine.Object.Destroy(full);
            }
        }

        private static Texture2D? FromCamera(ShotOptions o)
        {
            Camera? main = Camera.main;
            if (main == null)
                return null;
            (int w, int h) = ShotOptions.Fit(Screen.width, Screen.height, o.Size);
            var go = new GameObject("ModTestBridge_shot");
            RenderTexture rt = RenderTexture.GetTemporary(w, h, 24);
            try
            {
                Camera cam = go.AddComponent<Camera>();
                cam.CopyFrom(main);
                cam.enabled = false;
                cam.fieldOfView = o.Fov;
                cam.nearClipPlane = 0.05f;
                cam.transform.position = V(o.At!);
                cam.transform.LookAt(V(o.Look!));
                cam.targetTexture = rt;
                cam.Render();
                return Read(rt);
            }
            finally
            {
                UnityEngine.Object.Destroy(go);
                RenderTexture.ReleaseTemporary(rt);
            }
        }

        private static Texture2D Read(RenderTexture rt)
        {
            RenderTexture? was = RenderTexture.active;
            RenderTexture.active = rt;
            try
            {
                var tex = new Texture2D(rt.width, rt.height, TextureFormat.RGB24, false);
                tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
                tex.Apply();
                return tex;
            }
            finally
            {
                RenderTexture.active = was;
            }
        }

        private static Vector3 V(float[] v) => new(v[0], v[1], v[2]);
    }
}

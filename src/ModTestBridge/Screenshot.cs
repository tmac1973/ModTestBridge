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

        public static IEnumerator Take(HttpListenerContext ctx, ShotOptions o)
        {
            bool day = o.Day && EnvMan.instance != null;
            bool wasDebug = day && EnvMan.instance!.m_debugTimeOfDay;
            float wasTime = day ? EnvMan.instance!.m_debugTime : 0f;
            Texture2D? image = null;
            try
            {
                if (day)
                {
                    EnvMan.instance!.m_debugTimeOfDay = true;
                    EnvMan.instance.m_debugTime = 0.5f;
                    for (int i = 0; i < 5; i++)
                        yield return null; // the sun and the light settle
                }
                if (o.FromCamera)
                    image = FromCamera(o);
                else
                {
                    yield return new WaitForEndOfFrame(); // everything drawn, UI included
                    image = FromScreen(o);
                }
            }
            finally
            {
                if (day && EnvMan.instance != null)
                {
                    EnvMan.instance.m_debugTimeOfDay = wasDebug;
                    EnvMan.instance.m_debugTime = wasTime;
                }
            }

            if (image == null)
            {
                Plugin.Respond(ctx, 409, Json.Obj(("error", "no camera yet (in the world or at the menu?)")));
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
            finally
            {
                UnityEngine.Object.Destroy(image);
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

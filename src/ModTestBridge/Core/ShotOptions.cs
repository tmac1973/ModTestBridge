using System;
using System.Collections.Specialized;
using System.Globalization;
using System.Linq;

namespace ModTestBridge.Core
{
    /// <summary>
    /// What a /screenshot request asks for. With <see cref="At"/> and <see cref="Look"/> it's a picture from a camera of its
    /// own (no UI, the player's view untouched); without them it's the screen as the player sees it, UI and all.
    /// </summary>
    public sealed class ShotOptions
    {
        public const int DefaultSize = 768, MinSize = 64, MaxSize = 4096;

        /// <summary>File name without extension: letters, digits, '-', '_' and '.' only.</summary>
        public string Name = "";
        /// <summary>The longer side of the saved image, in pixels (the screen is scaled down to it, never up).</summary>
        public int Size = DefaultSize;
        public float[]? At;
        public float[]? Look;
        public float Fov = 40f;
        /// <summary>Set the time of day to noon for the shot, then put it back.</summary>
        public bool Day;

        public bool FromCamera => At != null;

        /// <summary>Reads the query string; <paramref name="error"/> says what's wrong when it returns null.</summary>
        public static ShotOptions? Parse(NameValueCollection q, DateTime now, out string error)
        {
            error = "";
            var o = new ShotOptions();
            string name = q["name"] ?? "";
            o.Name = name.Length > 0 ? name : "shot-" + now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);
            if (o.Name.Any(c => !(char.IsLetterOrDigit(c) || c == '-' || c == '_' || c == '.')) || o.Name.StartsWith("."))
            {
                error = "name: letters, digits, '-', '_' and '.' only";
                return null;
            }
            if (q["size"] is string size)
            {
                if (!int.TryParse(size, NumberStyles.Integer, CultureInfo.InvariantCulture, out o.Size) || o.Size < MinSize || o.Size > MaxSize)
                {
                    error = $"size: a whole number from {MinSize} to {MaxSize}";
                    return null;
                }
            }
            if (q["fov"] is string fov)
            {
                if (!float.TryParse(fov, NumberStyles.Float, CultureInfo.InvariantCulture, out o.Fov) || o.Fov < 5f || o.Fov > 120f)
                {
                    error = "fov: degrees from 5 to 120";
                    return null;
                }
            }
            o.Day = q["day"] is string day && (day == "1" || day.Equals("true", StringComparison.OrdinalIgnoreCase));
            string? at = q["at"], look = q["look"];
            if ((at == null) != (look == null))
            {
                error = "at and look go together (a camera at one point looking at another)";
                return null;
            }
            if (at != null)
            {
                o.At = Vector(at);
                o.Look = Vector(look!);
                if (o.At == null || o.Look == null)
                {
                    error = "at and look: x,y,z in world coordinates";
                    return null;
                }
                if (o.At.Zip(o.Look, (a, b) => (a - b) * (a - b)).Sum() < 1e-6f)
                {
                    error = "at and look are the same point";
                    return null;
                }
            }
            return o;
        }

        private static float[]? Vector(string s)
        {
            string[] parts = s.Split(',');
            if (parts.Length != 3)
                return null;
            var v = new float[3];
            for (int i = 0; i < 3; i++)
                if (!float.TryParse(parts[i].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out v[i]))
                    return null;
            return v;
        }

        /// <summary>The saved size for a source of <paramref name="w"/> x <paramref name="h"/>: the longer side at most <paramref name="size"/>, aspect kept.</summary>
        public static (int W, int H) Fit(int w, int h, int size)
        {
            if (w <= size && h <= size)
                return (w, h);
            float k = (float)size / Math.Max(w, h);
            return (Math.Max(1, (int)Math.Round(w * k)), Math.Max(1, (int)Math.Round(h * k)));
        }

        /// <summary>
        /// A frame that's all but black (a minimised or hidden game window draws nothing): the brightest of a sample of
        /// pixels stays under a few percent. <paramref name="rgb"/> is RGB24.
        /// </summary>
        public static bool LooksBlank(byte[] rgb)
        {
            int pixels = rgb.Length / 3;
            int step = Math.Max(1, pixels / 4096);
            int brightest = 0;
            for (int p = 0; p < pixels; p += step)
                brightest = Math.Max(brightest, Math.Max(rgb[p * 3], Math.Max(rgb[p * 3 + 1], rgb[p * 3 + 2])));
            return brightest < 8;
        }
    }
}

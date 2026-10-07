using System;
using System.Collections.Generic;
using System.IO;

namespace ModTestBridge.Core
{
    /// <summary>Lines of a log file from a line number on, optionally only those containing some text.</summary>
    public static class LogTail
    {
        public const int MaxLines = 2000;

        /// <summary>Returns the matching lines from <paramref name="from"/> (0-based) and the line count read so far.</summary>
        public static (List<string> Lines, int Next) Read(string path, int from, string? contains, int max = MaxLines)
        {
            var lines = new List<string>();
            int n = 0;
            if (!File.Exists(path))
                return (lines, 0);
            // The game keeps the log open for writing: open it shared.
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var reader = new StreamReader(stream);
            string? line;
            while ((line = reader.ReadLine()) != null)
            {
                if (n++ < from)
                    continue;
                if (contains != null && contains.Length > 0 && line.IndexOf(contains, StringComparison.Ordinal) < 0)
                    continue;
                if (lines.Count < max)
                    lines.Add(line);
            }
            return (lines, n);
        }
    }
}

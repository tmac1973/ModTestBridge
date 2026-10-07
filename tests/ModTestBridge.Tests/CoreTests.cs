using System.Collections.Generic;
using System.IO;
using ModTestBridge.Core;
using Xunit;

namespace ModTestBridge.Tests
{
    public class CoreTests
    {
        [Fact]
        public void JsonEscapesAndNests()
        {
            string s = Json.Write(Json.Obj(("a", "q\"\\\n"), ("n", 3), ("f", 1.5f), ("b", true), ("l", new List<string> { "x" }), ("z", null)));
            Assert.Equal("{\"a\":\"q\\\"\\\\\\n\",\"n\":3,\"f\":1.5,\"b\":true,\"l\":[\"x\"],\"z\":null}", s);
        }

        [Fact]
        public void LogTailReadsFromALineAndFilters()
        {
            string path = Path.GetTempFileName();
            File.WriteAllLines(path, new[] { "one", "[VFH] two", "three", "[VFH] four" });
            (List<string> all, int next) = LogTail.Read(path, 1, null);
            Assert.Equal(new[] { "[VFH] two", "three", "[VFH] four" }, all);
            Assert.Equal(4, next);
            Assert.Equal(new[] { "[VFH] four" }, LogTail.Read(path, 2, "[VFH]").Lines);
            Assert.Empty(LogTail.Read(path + ".missing", 0, null).Lines);
            File.Delete(path);
        }
    }
}

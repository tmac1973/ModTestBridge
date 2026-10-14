using System;
using System.Collections.Generic;
using System.Collections.Specialized;
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

        private static ShotOptions? Shot(string query, out string error)
        {
            var q = new NameValueCollection();
            foreach (string pair in query.Split(new[] { '&' }, StringSplitOptions.RemoveEmptyEntries))
            {
                string[] kv = pair.Split(new[] { '=' }, 2);
                q[kv[0]] = kv.Length > 1 ? kv[1] : "";
            }
            return ShotOptions.Parse(q, new DateTime(2026, 10, 14, 9, 5, 7), out error);
        }

        [Fact]
        public void ShotDefaultsToTheScreenWithADatedName()
        {
            ShotOptions o = Shot("", out _)!;
            Assert.Equal("shot-20261014-090507", o.Name);
            Assert.Equal(ShotOptions.DefaultSize, o.Size);
            Assert.False(o.FromCamera);
            Assert.False(o.Day);
        }

        [Fact]
        public void ShotFromACamera()
        {
            ShotOptions o = Shot("name=cook.front&size=512&at=1,2.5,-3&look=1, 2 ,0&fov=30&day=1", out _)!;
            Assert.Equal("cook.front", o.Name);
            Assert.Equal(512, o.Size);
            Assert.True(o.FromCamera);
            Assert.Equal(new[] { 1f, 2.5f, -3f }, o.At);
            Assert.Equal(new[] { 1f, 2f, 0f }, o.Look);
            Assert.Equal(30f, o.Fov);
            Assert.True(o.Day);
        }

        [Theory]
        [InlineData("name=../evil", "name")]
        [InlineData("name=.hidden", "name")]
        [InlineData("size=10", "size")]
        [InlineData("size=big", "size")]
        [InlineData("at=1,2,3", "together")]
        [InlineData("at=1,2&look=1,2,3", "x,y,z")]
        [InlineData("at=1,2,3&look=1,2,3", "same point")]
        [InlineData("fov=500", "fov")]
        public void BadShotsSayWhy(string query, string because)
        {
            Assert.Null(Shot(query, out string error));
            Assert.Contains(because, error);
        }

        [Fact]
        public void ShotsShrinkToFitAndNeverGrow()
        {
            Assert.Equal((768, 432), ShotOptions.Fit(1600, 900, 768));
            Assert.Equal((432, 768), ShotOptions.Fit(900, 1600, 768));
            Assert.Equal((640, 360), ShotOptions.Fit(640, 360, 768));
        }

        [Fact]
        public void ABlackFrameLooksBlank()
        {
            var black = new byte[64 * 64 * 3];
            Assert.True(ShotOptions.LooksBlank(black));
            black[3 * 100 + 1] = 200; // one bright pixel in a dark night scene is still a picture
            Assert.False(ShotOptions.LooksBlank(black));
        }
    }
}

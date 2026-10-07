using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;
using BepInEx;
using BepInEx.Configuration;
using HarmonyLib;
using ModTestBridge.Core;
using UnityEngine;

namespace ModTestBridge
{
    /// <summary>
    /// A local HTTP bridge for driving the game from outside while developing mods: run console commands (and read what
    /// they print), read the BepInEx log, see the game's state, and quit. Listens on 127.0.0.1 only, and every request
    /// needs the token written to BepInEx/config/ModTestBridge.token. For development profiles only: never install it on a
    /// server or a profile you play on.
    /// </summary>
    [BepInPlugin(Guid, Name, Version)]
    public sealed class Plugin : BaseUnityPlugin
    {
        public const string Guid = "Spronglehump.ModTestBridge";
        public const string Name = "ModTestBridge";
        public const string Version = "0.1.0";

        private sealed class Request
        {
            public HttpListenerContext Context = null!;
            public string Path = "";
            public string Body = "";
        }

        private ConfigEntry<bool> _enabled = null!;
        private ConfigEntry<int> _port = null!;
        private HttpListener? _listener;
        private Thread? _thread;
        private string _token = "";
        private readonly ConcurrentQueue<Request> _queue = new();
        private bool _quitAtMenu;

        internal static List<string>? Capture;

        private void Awake()
        {
            _enabled = Config.Bind("General", "Enabled", true, "Listen for requests (127.0.0.1 only, token required).");
            _port = Config.Bind("General", "Port", 7811, "Local port to listen on.");
            new Harmony(Guid).PatchAll(typeof(Plugin).Assembly);
            if (!_enabled.Value)
                return;
            _token = LoadToken();
            try
            {
                _listener = new HttpListener();
                _listener.Prefixes.Add($"http://127.0.0.1:{_port.Value}/");
                _listener.Start();
                _thread = new Thread(Listen) { IsBackground = true, Name = "ModTestBridge" };
                _thread.Start();
                Logger.LogInfo($"ModTestBridge listening on 127.0.0.1:{_port.Value} (token in {TokenPath})");
            }
            catch (Exception e)
            {
                Logger.LogError($"ModTestBridge couldn't listen on port {_port.Value}: {e.Message}");
            }
        }

        private static string TokenPath => Path.Combine(Paths.ConfigPath, "ModTestBridge.token");

        private static string LoadToken()
        {
            if (File.Exists(TokenPath))
            {
                string t = File.ReadAllText(TokenPath).Trim();
                if (t.Length >= 16)
                    return t;
            }
            string token = System.Guid.NewGuid().ToString("N");
            File.WriteAllText(TokenPath, token);
            return token;
        }

        private void OnDestroy()
        {
            try
            {
                _listener?.Stop();
            }
            catch
            {
                // shutting down anyway
            }
        }

        // Background thread: accept, check the token, hand the request to the main thread.
        private void Listen()
        {
            while (_listener != null && _listener.IsListening)
            {
                HttpListenerContext ctx;
                try
                {
                    ctx = _listener.GetContext();
                }
                catch
                {
                    return;
                }
                try
                {
                    if (ctx.Request.Headers["X-Token"] != _token)
                    {
                        Respond(ctx, 401, Json.Obj(("error", "bad or missing X-Token")));
                        continue;
                    }
                    string body;
                    using (var reader = new StreamReader(ctx.Request.InputStream, Encoding.UTF8))
                        body = reader.ReadToEnd();
                    _queue.Enqueue(new Request { Context = ctx, Path = ctx.Request.Url.AbsolutePath.TrimEnd('/'), Body = body });
                }
                catch (Exception e)
                {
                    Respond(ctx, 500, Json.Obj(("error", e.Message)));
                }
            }
        }

        // Main thread: the game's state and console are only safe to touch here.
        private void Update()
        {
            if (_quitAtMenu && Game.instance == null && FejdStartup.instance != null)
            {
                Logger.LogInfo("ModTestBridge: quitting");
                Application.Quit();
                return;
            }
            int handled = 0;
            while (handled++ < 8 && _queue.TryDequeue(out Request r))
            {
                try
                {
                    Handle(r);
                }
                catch (Exception e)
                {
                    Respond(r.Context, 500, Json.Obj(("error", e.ToString())));
                }
            }
        }

        private void Handle(Request r)
        {
            HttpListenerRequest req = r.Context.Request;
            switch (r.Path)
            {
                case "/status":
                    Respond(r.Context, 200, Status());
                    return;
                case "/command":
                {
                    string command = r.Body.Trim();
                    if (command.Length == 0)
                        command = req.QueryString["c"] ?? "";
                    if (command.Length == 0 || Console.instance == null)
                    {
                        Respond(r.Context, 400, Json.Obj(("error", command.Length == 0 ? "no command" : "no console yet")));
                        return;
                    }
                    Capture = new List<string>();
                    try
                    {
                        Console.instance.TryRunCommand(command, silentFail: false, skipAllowedCheck: true);
                    }
                    finally
                    {
                        List<string> output = Capture;
                        Capture = null;
                        Logger.LogInfo($"ModTestBridge ran: {command}");
                        Respond(r.Context, 200, Json.Obj(("command", command), ("output", output)));
                    }
                    return;
                }
                case "/log":
                {
                    int from = int.TryParse(req.QueryString["from"], out int f) ? Math.Max(0, f) : 0;
                    (List<string> lines, int next) = LogTail.Read(Path.Combine(Paths.BepInExRootPath, "LogOutput.log"), from, req.QueryString["contains"]);
                    Respond(r.Context, 200, Json.Obj(("from", from), ("next", next), ("lines", lines)));
                    return;
                }
                case "/quit":
                    _quitAtMenu = true;
                    if (Game.instance != null)
                        Game.instance.Logout(); // saves the world and character, then back to the menu, then quit
                    Respond(r.Context, 200, Json.Obj(("quitting", true)));
                    return;
                default:
                    Respond(r.Context, 404, Json.Obj(("error", "unknown path"), ("paths", new[] { "/status", "/command", "/log?from=N&contains=TEXT", "/quit" })));
                    return;
            }
        }

        private static Dictionary<string, object?> Status()
        {
            Player p = Player.m_localPlayer;
            string state = p != null ? "world" : Game.instance != null ? "loading" : FejdStartup.instance != null ? "menu" : "starting";
            return Json.Obj(
                ("state", state),
                ("world", ZNet.instance != null ? ZNet.instance.GetWorldName() : null),
                ("character", p != null ? p.GetPlayerName() : null),
                ("position", p != null ? new[] { p.transform.position.x, p.transform.position.y, p.transform.position.z } : null),
                ("server", ZNet.instance != null && ZNet.instance.IsServer()),
                ("fps", Time.deltaTime > 0f ? 1f / Time.deltaTime : 0f),
                ("time", Time.time),
                ("bridge", Version));
        }

        private static void Respond(HttpListenerContext ctx, int code, object body)
        {
            try
            {
                byte[] bytes = Encoding.UTF8.GetBytes(Json.Write(body));
                ctx.Response.StatusCode = code;
                ctx.Response.ContentType = "application/json";
                ctx.Response.ContentLength64 = bytes.Length;
                ctx.Response.OutputStream.Write(bytes, 0, bytes.Length);
                ctx.Response.OutputStream.Close();
            }
            catch
            {
                // the caller went away
            }
        }
    }

    /// <summary>Whatever the console prints while a bridge command runs is returned with the request.</summary>
    [HarmonyPatch(typeof(Terminal), nameof(Terminal.AddString), typeof(string))]
    internal static class CapturePatch
    {
        private static void Postfix(string text)
        {
            Plugin.Capture?.Add(text);
        }
    }
}

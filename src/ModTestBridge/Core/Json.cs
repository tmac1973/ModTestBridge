using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace ModTestBridge.Core
{
    /// <summary>Just enough JSON to answer requests: strings, numbers, booleans, lists and objects (dictionaries).</summary>
    public static class Json
    {
        public static string Write(object? value)
        {
            var sb = new StringBuilder();
            Append(sb, value);
            return sb.ToString();
        }

        private static void Append(StringBuilder sb, object? v)
        {
            switch (v)
            {
                case null:
                    sb.Append("null");
                    break;
                case string s:
                    AppendString(sb, s);
                    break;
                case bool b:
                    sb.Append(b ? "true" : "false");
                    break;
                case int or long or short or byte:
                    sb.Append(System.Convert.ToInt64(v, CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture));
                    break;
                case float f:
                    sb.Append(float.IsNaN(f) || float.IsInfinity(f) ? "null" : f.ToString("0.###", CultureInfo.InvariantCulture));
                    break;
                case double d:
                    sb.Append(double.IsNaN(d) || double.IsInfinity(d) ? "null" : d.ToString("0.###", CultureInfo.InvariantCulture));
                    break;
                case IDictionary dict:
                {
                    sb.Append('{');
                    bool first = true;
                    foreach (DictionaryEntry e in dict)
                    {
                        if (!first)
                            sb.Append(',');
                        first = false;
                        AppendString(sb, e.Key?.ToString() ?? "");
                        sb.Append(':');
                        Append(sb, e.Value);
                    }
                    sb.Append('}');
                    break;
                }
                case IEnumerable list:
                {
                    sb.Append('[');
                    bool first = true;
                    foreach (object? item in list)
                    {
                        if (!first)
                            sb.Append(',');
                        first = false;
                        Append(sb, item);
                    }
                    sb.Append(']');
                    break;
                }
                default:
                    AppendString(sb, v.ToString() ?? "");
                    break;
            }
        }

        public static void AppendString(StringBuilder sb, string s)
        {
            sb.Append('"');
            foreach (char c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < 0x20)
                            sb.Append("\\u").Append(((int)c).ToString("x4"));
                        else
                            sb.Append(c);
                        break;
                }
            }
            sb.Append('"');
        }

        public static Dictionary<string, object?> Obj(params (string Key, object? Value)[] fields)
        {
            var d = new Dictionary<string, object?>();
            foreach ((string k, object? v) in fields)
                d[k] = v;
            return d;
        }
    }
}

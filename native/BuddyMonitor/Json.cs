using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace BuddyMonitor
{
    /// <summary>Tiny allocation-light JSON writer (no dependencies on net472).</summary>
    internal sealed class Json
    {
        readonly StringBuilder _sb = new StringBuilder(4096);
        readonly Stack<bool> _first = new Stack<bool>();

        void Sep()
        {
            if (_first.Count == 0) return;
            if (_first.Peek()) { _first.Pop(); _first.Push(false); }
            else _sb.Append(',');
        }

        void Key(string k) { Sep(); Str(k); _sb.Append(':'); }

        void Str(string s)
        {
            _sb.Append('"');
            foreach (char c in s ?? "")
            {
                switch (c)
                {
                    case '"': _sb.Append("\\\""); break;
                    case '\\': _sb.Append("\\\\"); break;
                    case '\n': _sb.Append("\\n"); break;
                    case '\r': _sb.Append("\\r"); break;
                    case '\t': _sb.Append("\\t"); break;
                    default:
                        if (c < 0x20) _sb.AppendFormat("\\u{0:x4}", (int)c); else _sb.Append(c);
                        break;
                }
            }
            _sb.Append('"');
        }

        public Json Obj(string key = null) { if (key != null) Key(key); else Sep(); _sb.Append('{'); _first.Push(true); return this; }
        public Json Arr(string key = null) { if (key != null) Key(key); else Sep(); _sb.Append('['); _first.Push(true); return this; }
        public Json EndObj() { _first.Pop(); _sb.Append('}'); return this; }
        public Json EndArr() { _first.Pop(); _sb.Append(']'); return this; }

        public Json P(string key, string v) { Key(key); if (v == null) _sb.Append("null"); else Str(v); return this; }
        public Json P(string key, bool v) { Key(key); _sb.Append(v ? "true" : "false"); return this; }
        public Json P(string key, double? v, int digits = 1)
        {
            Key(key);
            if (!v.HasValue || double.IsNaN(v.Value) || double.IsInfinity(v.Value)) _sb.Append("null");
            else _sb.Append(Math.Round(v.Value, digits).ToString(CultureInfo.InvariantCulture));
            return this;
        }
        public Json V(double v, int digits = 1)
        {
            Sep();
            _sb.Append(Math.Round(v, digits).ToString(CultureInfo.InvariantCulture));
            return this;
        }

        public override string ToString() { return _sb.ToString(); }
    }
}

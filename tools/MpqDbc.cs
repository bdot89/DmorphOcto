// MPQ (v1) and WDBC readers for tools/build_models.ps1 and tools/build_items.ps1.
// Read-only. Ported from OctoBG/tools/MpqRead.ps1.
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
public class Mpq {
  static uint[] CT = Build();
  static uint[] Build() {
    uint seed = 0x00100001; uint[] t = new uint[0x500];
    for (int i1 = 0; i1 < 0x100; i1++) {
      int i2 = i1;
      for (int k = 0; k < 5; k++) {
        seed = (seed * 125 + 3) % 0x2AAAAB; uint t1 = (seed & 0xFFFF) << 16;
        seed = (seed * 125 + 3) % 0x2AAAAB; uint t2 = seed & 0xFFFF;
        t[i2] = t1 | t2; i2 += 0x100;
      }
    }
    return t;
  }
  public static uint Hs(string s, int ht) {
    uint s1 = 0x7FED7FED, s2 = 0xEEEEEEEE;
    foreach (char c0 in s.ToUpperInvariant()) {
      uint ch = (uint)c0;
      s1 = CT[(ht << 8) + ch] ^ (s1 + s2);
      s2 = ch + s1 + s2 + (s2 << 5) + 3;
    }
    return s1;
  }
  static byte[] Decrypt(byte[] data, uint key) {
    uint s2 = 0xEEEEEEEE; byte[] o = (byte[])data.Clone(); int n = data.Length / 4;
    for (int i = 0; i < n; i++) {
      s2 += CT[0x400 + (key & 0xFF)];
      uint v = BitConverter.ToUInt32(data, i * 4);
      v = v ^ (key + s2);
      key = ((~key << 0x15) + 0x11111111) | (key >> 0x0B);
      s2 = v + s2 + (s2 << 5) + 3;
      byte[] b = BitConverter.GetBytes(v); Array.Copy(b, 0, o, i * 4, 4);
    }
    return o;
  }
  public string Name;
  FileStream f; long bas; int sector; uint[][] hashes; uint[][] blocks;
  public Mpq(string path) {
    Name = Path.GetFileName(path);
    f = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
    byte[] d = new byte[4096]; f.Read(d, 0, 4096);
    int off = -1;
    for (int i = 0; i + 3 < d.Length; i++) if (d[i]=='M'&&d[i+1]=='P'&&d[i+2]=='Q'&&d[i+3]==0x1a) { off = i; break; }
    if (off < 0) throw new Exception("no MPQ header");
    bas = off; f.Seek(off, SeekOrigin.Begin);
    byte[] h = new byte[32]; f.Read(h, 0, 32);
    ushort bss = BitConverter.ToUInt16(h, 14);
    uint hto = BitConverter.ToUInt32(h, 16), bto = BitConverter.ToUInt32(h, 20);
    uint hte = BitConverter.ToUInt32(h, 24), bte = BitConverter.ToUInt32(h, 28);
    sector = 512 << bss;
    byte[] ht = ReadAt(bas + hto, (int)(hte * 16)); ht = Decrypt(ht, Hs("(hash table)", 3));
    byte[] bt = ReadAt(bas + bto, (int)(bte * 16)); bt = Decrypt(bt, Hs("(block table)", 3));
    hashes = new uint[hte][]; blocks = new uint[bte][];
    for (int i = 0; i < hte; i++) hashes[i] = new uint[] { BitConverter.ToUInt32(ht, i*16), BitConverter.ToUInt32(ht, i*16+4), BitConverter.ToUInt32(ht, i*16+12) };
    for (int i = 0; i < bte; i++) blocks[i] = new uint[] { BitConverter.ToUInt32(bt, i*16), BitConverter.ToUInt32(bt, i*16+4), BitConverter.ToUInt32(bt, i*16+8), BitConverter.ToUInt32(bt, i*16+12) };
  }
  byte[] ReadAt(long pos, int len) { f.Seek(pos, SeekOrigin.Begin); byte[] b = new byte[len]; int r = 0; while (r < len) { int k = f.Read(b, r, len - r); if (k <= 0) break; r += k; } return b; }
  uint[] Find(string name) { return Find(Hs(name, 0), Hs(name, 1), Hs(name, 2)); }
  uint[] Find(uint h0, uint a, uint b) {
    int n = hashes.Length; int i = (int)(h0 % (uint)n);
    for (int k = 0; k < n; k++) {
      uint[] e = hashes[i];
      if (e[2] == 0xFFFFFFFF) return null;
      if (e[0] == a && e[1] == b && e[2] != 0xFFFFFFFE && e[2] < blocks.Length) return blocks[e[2]];
      i = (i + 1) % n;
    }
    return null;
  }
  // A file counts only if its block is marked as existing (0x80000000).
  public bool Has(string name) { uint[] blk = Find(name); return blk != null && (blk[3] & 0x80000000) != 0; }
  // Has() for a name already hashed with Hs(name, 0), (name, 1) and (name, 2).
  public bool HasHashed(uint h0, uint a, uint b) { uint[] blk = Find(h0, a, b); return blk != null && (blk[3] & 0x80000000) != 0; }
  static byte[] Inflate(byte[] p, int off) {
    using (var ms = new MemoryStream(p, off + 2, p.Length - off - 2))
    using (var ds = new DeflateStream(ms, CompressionMode.Decompress))
    using (var o = new MemoryStream()) { ds.CopyTo(o); return o.ToArray(); }
  }
  static byte[] Dec(byte[] data, int size) {
    if (data.Length == size) return data;
    byte m = data[0];
    if ((m & 0x02) != 0 && (m & ~0x02) == 0) return Inflate(data, 1);
    throw new Exception("unsupported compression 0x" + m.ToString("X2"));
  }
  static uint FileKey(string name, uint pos, uint size, uint flags) {
    string b = name.Replace('/', '\\'); int s = b.LastIndexOf('\\'); if (s >= 0) b = b.Substring(s + 1);
    uint key = Hs(b, 3);
    if ((flags & 0x00020000) != 0) key = (key + pos) ^ size;
    return key;
  }
  // The start of a file (its first sector, at most the whole file), for reading
  // a header without decompressing everything. Null if the file isn't there.
  public byte[] ReadStart(string name) {
    uint[] blk = Find(name); if (blk == null || (blk[3] & 0x80000000) == 0) return null;
    uint pos = blk[0], csize = blk[1], size = blk[2], flags = blk[3];
    bool enc = (flags & 0x00010000) != 0;
    if ((flags & 0x01000000) != 0) return Read(name);
    uint key = enc ? FileKey(name, pos, size, flags) : 0;
    if ((flags & 0x0000FF00) == 0) {
      byte[] first = ReadAt(bas + pos, (int)Math.Min(csize, (uint)sector));
      return enc ? Decrypt(first, key) : first;
    }
    int ns = (int)((size + sector - 1) / sector);
    byte[] tbl = ReadAt(bas + pos, (ns + 1) * 4);
    if (enc) tbl = Decrypt(tbl, key - 1);
    int a = (int)BitConverter.ToUInt32(tbl, 0), z = (int)BitConverter.ToUInt32(tbl, 4);
    if (a < 0 || z <= a || z > csize) return null;
    byte[] sct = ReadAt(bas + pos + a, z - a);
    if (enc) sct = Decrypt(sct, key);
    return Dec(sct, (int)Math.Min(sector, size));
  }
  public byte[] Read(string name) {
    uint[] blk = Find(name); if (blk == null || (blk[3] & 0x80000000) == 0) return null;
    uint pos = blk[0], csize = blk[1], size = blk[2], flags = blk[3];
    byte[] raw = ReadAt(bas + pos, (int)csize);
    bool enc = (flags & 0x00010000) != 0; uint key = 0;
    if (enc) key = FileKey(name, pos, size, flags);
    if ((flags & 0x01000000) != 0) { if (enc) raw = Decrypt(raw, key); return (flags & 0x0000FF00) != 0 ? Dec(raw, (int)size) : raw; }
    if ((flags & 0x0000FF00) == 0) {
      if (!enc) return raw;
      var o = new MemoryStream();
      for (int i = 0; i < raw.Length; i += sector) { int l = Math.Min(sector, raw.Length - i); byte[] c = new byte[l]; Array.Copy(raw, i, c, 0, l); c = Decrypt(c, key + (uint)(i / sector)); o.Write(c, 0, c.Length); }
      return o.ToArray();
    }
    int ns = (int)((size + sector - 1) / sector);
    byte[] tbl = new byte[(ns + 1) * 4]; Array.Copy(raw, tbl, tbl.Length);
    if (enc) tbl = Decrypt(tbl, key - 1);
    var outp = new MemoryStream();
    for (int i = 0; i < ns; i++) {
      int a = (int)BitConverter.ToUInt32(tbl, i * 4), z = (int)BitConverter.ToUInt32(tbl, i * 4 + 4);
      byte[] sct = new byte[z - a]; Array.Copy(raw, a, sct, 0, z - a);
      if (enc) sct = Decrypt(sct, key + (uint)i);
      int want = (int)Math.Min(sector, size - i * sector);
      byte[] d = Dec(sct, want); outp.Write(d, 0, d.Length);
    }
    return outp.ToArray();
  }
  public void Close() { f.Close(); }
}

// A WDBC table: fixed-size records of 4-byte fields, then a string block.
public class Dbc {
  byte[] b; public int Count, Fields, Size; int strings;
  public Dbc(byte[] data) {
    b = data;
    if (b.Length < 20 || b[0] != 'W' || b[1] != 'D' || b[2] != 'B' || b[3] != 'C') throw new Exception("not a WDBC file");
    Count = BitConverter.ToInt32(b, 4); Fields = BitConverter.ToInt32(b, 8); Size = BitConverter.ToInt32(b, 12);
    strings = 20 + Count * Size;
  }
  public int Int(int row, int field) { return BitConverter.ToInt32(b, 20 + row * Size + field * 4); }
  public string Str(int row, int field) {
    int off = Int(row, field); if (off <= 0) return "";
    int start = strings + off, end = start; while (b[end] != 0) end++;
    return System.Text.Encoding.UTF8.GetString(b, start, end - start);
  }
  // A field read as text only if it really points at the start of a string in
  // the string block (for tables whose text columns aren't known); else null.
  public string TryStr(int row, int field) {
    int off = Int(row, field);
    if (off <= 0 || strings + off >= b.Length || b[strings + off - 1] != 0) return null;
    int start = strings + off, end = start; while (end < b.Length && b[end] != 0) end++;
    if (end >= b.Length || end == start) return null;
    return System.Text.Encoding.UTF8.GetString(b, start, end - start);
  }
}

// All of a client's MPQs at once: whether any of them has a file (each name
// hashed once, answers cached), and whether an item display has files to draw.
public class GameFiles {
  Mpq[] mpqs;
  Dictionary<string, bool> found = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
  Dictionary<string, bool> values = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
  public GameFiles(Mpq[] archives) { mpqs = archives; }
  public bool Has(string name) {
    bool yes;
    if (found.TryGetValue(name, out yes)) return yes;
    uint h0 = Mpq.Hs(name, 0), a = Mpq.Hs(name, 1), b = Mpq.Hs(name, 2);
    yes = false;
    foreach (Mpq m in mpqs) if (m.HasHashed(h0, a, b)) { yes = true; break; }
    found[name] = yes;
    return yes;
  }

  static readonly string[] Regions = { "ArmUpperTexture", "ArmLowerTexture", "HandTexture", "TorsoUpperTexture",
    "TorsoLowerTexture", "LegUpperTexture", "LegLowerTexture", "FootTexture" };
  static readonly string[] Objects = { "Weapon", "Shield", "Shoulder", "Head", "Cape", "Quiver", "Ammo" };
  // Helmets are stored once per race and gender: Helm_X_HuM.m2, Helm_X_OrF.m2, ...
  static readonly string[] HeadSuffixes = { "_HuM", "_HuF", "_OrM", "_OrF", "_DwM", "_DwF", "_NiM", "_NiF",
    "_ScM", "_ScF", "_TaM", "_TaF", "_GnM", "_GnF", "_TrM", "_TrF" };

  // Whether a text value from ItemDisplayInfo.dbc names a file the game has: a
  // model under Item\ObjectComponents, or a texture there or under
  // Item\TextureComponents (armour textures come in _U, _M and _F versions).
  public bool ItemFile(string value) {
    bool yes;
    if (values.TryGetValue(value, out yes)) return yes;
    yes = false;
    string lower = value.ToLowerInvariant();
    if (lower.EndsWith(".mdx") || lower.EndsWith(".m2")) {
      string bas = value.Substring(0, value.LastIndexOf('.'));
      foreach (string o in Objects) if (Has("Item\\ObjectComponents\\" + o + "\\" + bas + ".m2")) { yes = true; break; }
      if (!yes) foreach (string sfx in HeadSuffixes) if (Has("Item\\ObjectComponents\\Head\\" + bas + sfx + ".m2")) { yes = true; break; }
    } else {
      string bas = value;
      if (lower.EndsWith(".blp") || lower.EndsWith(".tga")) bas = value.Substring(0, value.Length - 4);
      foreach (string r in Regions) {
        foreach (string g in new string[] { "_U", "_M", "_F", "" }) {
          if (Has("Item\\TextureComponents\\" + r + "\\" + bas + g + ".blp")) { yes = true; break; }
        }
        if (yes) break;
      }
      if (!yes) foreach (string o in Objects) if (Has("Item\\ObjectComponents\\" + o + "\\" + bas + ".blp")) { yes = true; break; }
    }
    values[value] = yes;
    return yes;
  }

  // Whether an ItemDisplayInfo.dbc row names any model or texture file the game
  // has. Read without knowing the table's columns: every field that points at a
  // string counts, except icons.
  public bool ItemDisplayShows(Dbc table, int row) {
    for (int f = 1; f < table.Fields; f++) {
      string v = table.TryStr(row, f);
      if (v == null || v.StartsWith("INV_", StringComparison.OrdinalIgnoreCase)) continue;
      if (ItemFile(v)) return true;
    }
    return false;
  }
}

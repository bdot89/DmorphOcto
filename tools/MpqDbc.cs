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
  uint[] Find(string name) {
    uint a = Hs(name, 1), b = Hs(name, 2); int n = hashes.Length; int i = (int)(Hs(name, 0) % (uint)n);
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
  public byte[] Read(string name) {
    uint[] blk = Find(name); if (blk == null || (blk[3] & 0x80000000) == 0) return null;
    uint pos = blk[0], csize = blk[1], size = blk[2], flags = blk[3];
    byte[] raw = ReadAt(bas + pos, (int)csize);
    bool enc = (flags & 0x00010000) != 0; uint key = 0;
    if (enc) {
      string b = name.Replace('/', '\\'); int s = b.LastIndexOf('\\'); if (s >= 0) b = b.Substring(s + 1);
      key = Hs(b, 3);
      if ((flags & 0x00020000) != 0) key = (key + pos) ^ size;
    }
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
}

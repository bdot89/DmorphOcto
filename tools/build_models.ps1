param(
  [string]$GameDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path,
  [string]$OutFile = (Join-Path $PSScriptRoot "..\Data\Models.lua"),
  [string]$Creatures = (Join-Path $PSScriptRoot "..\Data\Creatures.lua")
)
# Builds Data/Models.lua: every creature display ID the client can show that
# Data/Creatures.lua (creature names from the 1.12.1 world database) doesn't
# name already. The source is the client's own DBFilesClient tables, so models
# that OctoWoW added are included too.
#
#   powershell -ExecutionPolicy Bypass -File tools\build_models.ps1 [-GameDir C:\Games\OctoWoW]
#
# Each display is named after its model file ("Crystal Spider"), with the
# skin added when several displays share that model, or after the race of a
# dressed NPC ("Human Male NPC"). Displays whose model file is missing from
# every MPQ are left out: morphing into them would make you invisible.
# Runs on Windows PowerShell 5.1, no Python or Lua needed.

$ErrorActionPreference = "Stop"

$src = @"
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
"@
Add-Type -TypeDefinition $src -Language CSharp

# The client reads its MPQs in this order and later ones win: the base
# archives, patch.MPQ, then patch-1..9, then patch-A..Z.
function Get-Priority([string]$name) {
  $base = [IO.Path]::GetFileNameWithoutExtension($name).ToLowerInvariant()
  if ($base -eq "patch") { return 100 }
  if ($base -match '^patch-([0-9])$') { return 100 + [int]$matches[1] }
  if ($base -match '^patch-([a-z])$') { return 200 + [int][char]$matches[1] }
  return 0
}

$dataDir = Join-Path $GameDir "Data"
if (-not (Test-Path $dataDir)) { throw "No Data folder in $GameDir" }
$mpqs = @()
foreach ($file in Get-ChildItem $dataDir -Filter *.mpq) {
  try { $mpqs += New-Object Mpq $file.FullName } catch { Write-Output ("skipped {0}: {1}" -f $file.Name, $_.Exception.Message) }
}
$mpqs = @($mpqs | Sort-Object @{ Expression = { Get-Priority $_.Name } }, Name)

function Read-Newest([string]$name) {
  for ($i = $mpqs.Count - 1; $i -ge 0; $i--) {
    $bytes = $mpqs[$i].Read($name)
    if ($bytes) { return New-Object Dbc (,$bytes) }
  }
  throw "$name is in none of the MPQs"
}

$display = Read-Newest "DBFilesClient\CreatureDisplayInfo.dbc"
$modelData = Read-Newest "DBFilesClient\CreatureModelData.dbc"
$extraData = Read-Newest "DBFilesClient\CreatureDisplayInfoExtra.dbc"

# The stock 1.12.1 table (patch.MPQ), to tell OctoWoW's additions apart.
$stock = @{}
$stockMpq = $mpqs | Where-Object { $_.Name -ieq "patch.MPQ" } | Select-Object -First 1
if ($stockMpq) {
  $bytes = $stockMpq.Read("DBFilesClient\CreatureDisplayInfo.dbc")
  if ($bytes) { $t = New-Object Dbc (,$bytes); for ($i = 0; $i -lt $t.Count; $i++) { $stock[$t.Int($i, 0)] = $true } }
}

# CreatureModelData: 0 ID, 2 model path. CreatureDisplayInfo: 0 ID, 1 model,
# 3 CreatureDisplayInfoExtra ID, 6-8 skins. Extra: 0 ID, 1 race, 2 gender.
$models = @{}
for ($i = 0; $i -lt $modelData.Count; $i++) { $models[$modelData.Int($i, 0)] = $modelData.Str($i, 2) }
$extras = @{}
for ($i = 0; $i -lt $extraData.Count; $i++) { $extras[$extraData.Int($i, 0)] = @($extraData.Int($i, 1), $extraData.Int($i, 2)) }

$named = @{}
foreach ($line in [IO.File]::ReadAllLines($Creatures)) {
  if ($line -match '^(\d+)\t') { $named[[int]$matches[1]] = $true }
}

$RACES = @{ 1 = "Human"; 2 = "Orc"; 3 = "Dwarf"; 4 = "Night Elf"; 5 = "Undead"; 6 = "Tauren"; 7 = "Gnome";
  8 = "Troll"; 9 = "Goblin"; 10 = "High Elf" }
$RACE_DIRS = @{ human = "Human"; orc = "Orc"; dwarf = "Dwarf"; nightelf = "Night Elf"; scourge = "Undead";
  tauren = "Tauren"; gnome = "Gnome"; troll = "Troll"; goblin = "Goblin"; bloodelf = "High Elf"; highelf = "High Elf" }

# "HUMLMagicSmith" -> "HUML Magic Smith", "furbolg_b" -> "Furbolg B".
function Split-Words([string]$text) {
  $text = $text -creplace '([a-z0-9])([A-Z])', '$1 $2'
  $text = $text -creplace '([A-Z])([A-Z][a-z])', '$1 $2'
  $text = $text -replace '[_\-]+', ' '
  $words = @($text -split '\s+' | Where-Object { $_ -ne "" })
  for ($i = 0; $i -lt $words.Count; $i++) {
    $w = $words[$i]
    $words[$i] = $w.Substring(0, 1).ToUpperInvariant() + $w.Substring(1)
  }
  return $words
}

# The words of a skin name that tell it apart from its model: "TigerSkinTurquoise" -> "Turquoise".
function Get-SkinHint([string]$skin, [string]$modelBase, [string[]]$nameWords) {
  if (-not $skin) { return "" }
  if ($skin.ToLowerInvariant().StartsWith($modelBase.ToLowerInvariant()) -and $skin.Length -gt $modelBase.Length) {
    $skin = $skin.Substring($modelBase.Length)
  }
  $drop = @{ skin = 1; tex = 1; texture = 1 }
  foreach ($w in $nameWords) { $drop[$w.ToLowerInvariant()] = 1 }
  $kept = @(Split-Words $skin | Where-Object { -not $drop.ContainsKey($_.ToLowerInvariant()) })
  return ($kept -join " ")
}

$exists = @{}
function Test-ModelFile([string]$path) {
  if ($exists.ContainsKey($path)) { return $exists[$path] }
  $m2 = [IO.Path]::ChangeExtension($path, ".m2")
  $found = $false
  foreach ($m in $mpqs) { if ($m.Has($m2) -or $m.Has($path)) { $found = $true; break } }
  $exists[$path] = $found
  return $found
}

$entries = New-Object System.Collections.ArrayList
$missing = 0; $added = 0; $total = 0
$perModel = @{}
for ($i = 0; $i -lt $display.Count; $i++) {
  $id = $display.Int($i, 0)
  $total++
  if ($named.ContainsKey($id)) { continue }
  $path = $models[$display.Int($i, 1)]
  if (-not $path -or -not (Test-ModelFile $path)) { $missing++; continue }
  $skin = ""
  foreach ($f in 6, 7, 8) { $s = $display.Str($i, $f); if ($s) { $skin = $s; break } }
  $e = [pscustomobject]@{ id = $id; path = $path; skin = $skin; extra = $display.Int($i, 3); custom = -not $stock.ContainsKey($id); name = "" }
  [void]$entries.Add($e)
  if ($perModel.ContainsKey($path)) { $perModel[$path]++ } else { $perModel[$path] = 1 }
}

foreach ($e in $entries) {
  $parts = $e.path -split '[\\/]'
  $base = [IO.Path]::GetFileNameWithoutExtension($e.path)
  if ($parts[0] -ieq "Character" -and $parts.Count -ge 4) {
    $race = $RACE_DIRS[$parts[1].ToLowerInvariant()]
    if (-not $race) { $race = (Split-Words $parts[1]) -join " " }
    $sex = (Split-Words $parts[2]) -join " "
    if ($e.extra -gt 0 -and $extras.ContainsKey($e.extra)) {
      $x = $extras[$e.extra]
      if ($RACES.ContainsKey($x[0])) { $race = $RACES[$x[0]] }
      if ($x[1] -eq 1) { $sex = "Female" } else { $sex = "Male" }
      $e.name = "$race $sex NPC"
    } else {
      $e.name = "$race $sex (player model)"
    }
  } else {
    $words = @(Split-Words $base)
    $name = $words -join " "
    if ($perModel[$e.path] -gt 1) {
      $hint = Get-SkinHint $e.skin $base $words
      if ($hint -and $hint -ne $name) { $name = "$name ($hint)" }
    }
    $e.name = $name
  }
  if ($e.custom) { $added++ }
}

# Sorted like Lua compares strings (byte order), so the addon can merge this
# list with Creatures.lua in one pass.
$keys = New-Object string[] $entries.Count
$sorted = $entries.ToArray()
for ($i = 0; $i -lt $sorted.Length; $i++) {
  $keys[$i] = $sorted[$i].name.ToLowerInvariant() + [char]1 + $sorted[$i].id.ToString("D8")
}
[Array]::Sort($keys, $sorted, [System.Collections.IComparer][StringComparer]::Ordinal)
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("-- Generated by tools/build_models.ps1 from the client's CreatureDisplayInfo.dbc. Do not edit.`n")
[void]$sb.Append("-- Every display ID that Data/Creatures.lua doesn't name, named after its model file.`n")
[void]$sb.Append("-- One per line: displayID<TAB>flag<TAB>name, flag 1 = added by OctoWoW (not in stock 1.12.1).`n")
[void]$sb.Append("DmorphOcto_ModelData = [[`n")
foreach ($e in $sorted) {
  $flag = 0; if ($e.custom) { $flag = 1 }
  if ($e.name.Contains("]]") -or $e.name.Contains("`t")) { throw "name can't be stored: $($e.name)" }
  [void]$sb.Append("$($e.id)`t$flag`t$($e.name)`n")
}
[void]$sb.Append("]]`n")
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutFile), $sb.ToString(), $utf8)
foreach ($m in $mpqs) { $m.Close() }

"{0} display IDs in the client: {1} named in Creatures.lua, {2} written to Models.lua ({3} added by OctoWoW), {4} skipped (model file missing)" -f `
  $total, $named.Count, $entries.Count, $added, $missing

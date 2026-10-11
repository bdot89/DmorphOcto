param(
  [string]$GameDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path,
  [string]$Base = (Join-Path $PSScriptRoot "..\Data\Items.lua"),
  [string]$OutFile = (Join-Path $PSScriptRoot "..\Data\ItemsExtra.lua"),
  [string]$SetsFile = (Join-Path $PSScriptRoot "..\Data\ItemSets.lua"),
  [string]$TurtleItems = (Join-Path $PSScriptRoot "data\turtle_items.tsv"),
  [string]$TurtleOther = (Join-Path $PSScriptRoot "data\turtle_other_items.txt"),
  [string]$ItemDisplays = (Join-Path $PSScriptRoot "data\classic_item_displays.tsv"),
  [string]$HiddenFile = (Join-Path $PSScriptRoot "..\Data\HiddenItems.lua"),
  [string[]]$Caches = @(),
  [string]$Atlas = ""
)
# Adds the items that the 1.12.1 database behind Data/Items.lua doesn't have:
#
#   Data/ItemsExtra.lua  per slot, the weapons and armour from Turtle WoW's
#                        database (tools/data/turtle_items.tsv) and from the
#                        game's item cache (WDB\itemcache.wdb, items OctoWoW
#                        sent this client); plus "pending" item IDs whose slot
#                        is unknown here (from Atlas-CFM's loot tables and the
#                        item sets), which the addon looks up in game.
#   Data/ItemSets.lua    every item set in the client's ItemSet.dbc.
#   Data/HiddenItems.lua the items that have nothing to draw in this client:
#                        their display isn't in its ItemDisplayInfo.dbc, or
#                        none of its model and texture files are in the MPQs.
#                        The addon leaves them out (ItemsExtra.lua already does).
#
#   powershell -ExecutionPolicy Bypass -File tools\build_items.ps1 [-GameDir C:\Games\OctoWoW]
#
# By default it reads WDB\itemcache.wdb and WDB.old\itemcache.wdb in the game
# folder and Interface\AddOns\Atlas-CFM\CFMLoot\Data if they exist.

$ErrorActionPreference = "Stop"
Add-Type -Path (Join-Path $PSScriptRoot "MpqDbc.cs")

# InventoryType -> the inventory slots an item can be shown in (as build_data.py).
$SLOTS = @{ 1 = @(1); 3 = @(3); 4 = @(4); 5 = @(5); 20 = @(5); 6 = @(6); 7 = @(7); 8 = @(8); 9 = @(9);
  10 = @(10); 16 = @(15); 19 = @(19); 13 = @(16, 17); 17 = @(16); 21 = @(16); 14 = @(17); 22 = @(17);
  23 = @(17); 15 = @(18); 25 = @(18); 26 = @(18) }
$SLOT_ORDER = @(1, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18, 19)
$SKIP = '^(deprecated|zz|qa )|\[ph\]|\btest\b'

# What the base list already has, per slot and overall.
$baseSlot = @{}; $known = @{}
$slot = 0
foreach ($line in [IO.File]::ReadAllLines($Base)) {
  if ($line -match '^DmorphOcto_ItemData\[(\d+)\]') { $slot = [int]$matches[1]; continue }
  if ($slot -and $line -match '^(\d+)\t') { $baseSlot["$slot/$($matches[1])"] = $true; $known[[int]$matches[1]] = $true }
}

# id -> @{ inv; quality; name; source }
$items = @{}
function Add-Item([int]$id, [int]$inv, [int]$quality, [string]$name, [string]$source) {
  $name = ($name -replace '\s+', ' ').Trim()
  if (-not $name -or $name -match $SKIP) { return }
  if ($name.Contains("]]") -or $name.Contains("`t")) { return }
  if (-not $script:items.ContainsKey($id)) { $script:items[$id] = @{ inv = $inv; quality = $quality; name = $name; source = $source } }
}

$nonWearable = @{}
foreach ($line in [IO.File]::ReadAllLines($TurtleItems)) {
  if ($line -match '^(\d+)\t(\d+)\t(\d+)\t(.+)$') { Add-Item ([int]$matches[1]) ([int]$matches[2]) ([int]$matches[3]) $matches[4] "turtle" }
}
if (Test-Path $TurtleOther) {
  foreach ($line in [IO.File]::ReadAllLines($TurtleOther)) {
    if ($line.StartsWith("#")) { continue }
    foreach ($v in $line.Split(",")) { if ($v) { $nonWearable[[int]$v] = $true } }
  }
}

# The game's item cache: entry, size, then class, subclass, 4 names, display,
# quality, flags, buy, sell, inventory type, ... (SMSG_ITEM_QUERY_SINGLE_RESPONSE).
if (-not $Caches.Count) {
  $Caches = @((Join-Path $GameDir "WDB\itemcache.wdb"), (Join-Path $GameDir "WDB.old\itemcache.wdb")) | Where-Object { Test-Path $_ }
}
$fromCache = 0
$cacheDisplay = @{}
$cacheType = @{} # class * 100 + subclass, for the item filters (cloth, plate, dagger, ...)
foreach ($cache in $Caches) {
  $b = [IO.File]::ReadAllBytes($cache)
  $pos = 20
  while ($pos + 8 -le $b.Length) {
    $entry = [int][BitConverter]::ToUInt32($b, $pos); $size = [BitConverter]::ToInt32($b, $pos + 4)
    if ($entry -eq 0 -or $size -le 0) { break }
    $d = $pos + 8
    $class = [BitConverter]::ToInt32($b, $d); $subclass = [BitConverter]::ToInt32($b, $d + 4); $p = $d + 8
    $name = ""
    for ($k = 0; $k -lt 4; $k++) {
      $e = $p; while ($b[$e] -ne 0) { $e++ }
      if ($k -eq 0) { $name = [Text.Encoding]::UTF8.GetString($b, $p, $e - $p) }
      $p = $e + 1
    }
    $cacheDisplay[$entry] = [BitConverter]::ToInt32($b, $p)
    $quality = [BitConverter]::ToInt32($b, $p + 4); $inv = [BitConverter]::ToInt32($b, $p + 20)
    if (($class -eq 2 -or $class -eq 4) -and $SLOTS.ContainsKey($inv)) {
      $before = $items.Count
      Add-Item $entry $inv $quality $name "cache"
      if ($items.Count -gt $before) { $fromCache++ }
      $cacheType[$entry] = $class * 100 + $subclass
    } else {
      $nonWearable[$entry] = $true
    }
    $pos = $d + $size
  }
}
foreach ($id in $items.Keys) { $known[$id] = $true }

# The client's MPQs, newest last (later ones win).
function Get-Priority([string]$name) {
  $base = [IO.Path]::GetFileNameWithoutExtension($name).ToLowerInvariant()
  if ($base -eq "patch") { return 100 }
  if ($base -match '^patch-([0-9])$') { return 100 + [int]$matches[1] }
  if ($base -match '^patch-([a-z])$') { return 200 + [int][char]$matches[1] }
  return 0
}
$mpqs = @()
foreach ($file in Get-ChildItem (Join-Path $GameDir "Data") -Filter *.mpq) {
  if ($file.Name -ieq "patch-Z.mpq") { continue } # the model porting tool's, only on that PC
  try { $mpqs += New-Object Mpq $file.FullName } catch { }
}
$mpqs = @($mpqs | Sort-Object @{ Expression = { Get-Priority $_.Name } }, Name)
$files = New-Object GameFiles (,[Mpq[]]$mpqs)
function Read-Newest([string]$name) {
  for ($i = $mpqs.Count - 1; $i -ge 0; $i--) {
    $bytes = $mpqs[$i].Read($name)
    if ($bytes) { return New-Object Dbc (,$bytes) }
  }
  return $null
}

# Items with nothing to draw in this client: their display ID (the 1.12.1
# database's, or what the server sent into the item cache) isn't in
# ItemDisplayInfo.dbc, or none of its files are in the MPQs. Items whose display
# isn't known here (Turtle WoW's list) are kept. In a slot where this would hide
# more than a quarter of the items, nothing is hidden: that would mean the check
# misreads the files.
$itemDisplay = @{}
if (Test-Path $ItemDisplays) {
  foreach ($line in [IO.File]::ReadAllLines($ItemDisplays)) {
    if ($line -match '^(\d+)\t(\d+)$') { $itemDisplay[[int]$matches[1]] = [int]$matches[2] }
  }
}
foreach ($id in $cacheDisplay.Keys) { $itemDisplay[$id] = $cacheDisplay[$id] }
$hiddenItems = @{}
$displayInfo = Read-Newest "DBFilesClient\ItemDisplayInfo.dbc"
if ($displayInfo) {
  $rowOf = @{}
  for ($r = 0; $r -lt $displayInfo.Count; $r++) { $rowOf[$displayInfo.Int($r, 0)] = $r }
  $shows = @{}
  $perSlot = @{}
  foreach ($k in $baseSlot.Keys) {
    $parts = $k -split '/'
    if (-not $perSlot.ContainsKey($parts[0])) { $perSlot[$parts[0]] = New-Object System.Collections.ArrayList }
    [void]$perSlot[$parts[0]].Add([int]$parts[1])
  }
  foreach ($id in $items.Keys) {
    foreach ($s in $SLOTS[$items[$id].inv]) {
      if (-not $perSlot.ContainsKey("$s")) { $perSlot["$s"] = New-Object System.Collections.ArrayList }
      [void]$perSlot["$s"].Add($id)
    }
  }
  foreach ($s in $perSlot.Keys) {
    $bad = New-Object System.Collections.ArrayList
    foreach ($id in $perSlot[$s]) {
      if (-not $itemDisplay.ContainsKey($id)) { continue }
      $d = $itemDisplay[$id]
      if (-not $shows.ContainsKey($d)) {
        $shows[$d] = $rowOf.ContainsKey($d) -and $files.ItemDisplayShows($displayInfo, $rowOf[$d])
      }
      if (-not $shows[$d]) { [void]$bad.Add($id) }
    }
    if ($bad.Count -gt $perSlot[$s].Count / 4) {
      Write-Output ("warning: slot {0}: {1} of {2} items have nothing to draw, so none are hidden there" -f $s, $bad.Count, $perSlot[$s].Count)
    } else {
      foreach ($id in $bad) { $hiddenItems[$id] = $true }
    }
  }
} else {
  Write-Output "warning: no ItemDisplayInfo.dbc in the MPQs, so no items were checked"
}

# Per slot, the items the base list doesn't have yet, sorted like Lua compares
# strings so the addon merges them with Items.lua in one pass.
$utf8 = New-Object System.Text.UTF8Encoding($false)
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("-- Generated by tools/build_items.ps1. Do not edit.`n")
[void]$sb.Append("-- Weapons and armour that Data/Items.lua (the 1.12.1 database) doesn't have: Turtle WoW's database and`n")
[void]$sb.Append("-- the game's item cache. Per slot, one item per line: itemID<TAB>quality<TAB>name, sorted by name.`n")
[void]$sb.Append("DmorphOcto_ItemExtra = {}`n")
$extraCount = 0
foreach ($s in $SLOT_ORDER) {
  $list = New-Object System.Collections.ArrayList
  foreach ($id in $items.Keys) {
    $it = $items[$id]
    if ($SLOTS[$it.inv] -contains $s -and -not $baseSlot.ContainsKey("$s/$id") -and -not $hiddenItems.ContainsKey($id)) {
      [void]$list.Add([pscustomobject]@{ id = $id; it = $it })
    }
  }
  $arr = $list.ToArray()
  $keys = New-Object string[] $arr.Length
  for ($i = 0; $i -lt $arr.Length; $i++) { $keys[$i] = $arr[$i].it.name.ToLowerInvariant() + [char]1 + $arr[$i].id.ToString("D8") }
  [Array]::Sort($keys, $arr, [System.Collections.IComparer][StringComparer]::Ordinal)
  [void]$sb.Append("DmorphOcto_ItemExtra[$s] = [[`n")
  foreach ($x in $arr) { [void]$sb.Append("$($x.id)`t$($x.it.quality)`t$($x.it.name)`n"); $extraCount++ }
  [void]$sb.Append("]]`n")
}
# The kinds of the items the cache knows (Data/ItemTypes.lua has the rest).
[void]$sb.Append("-- Their kinds, from the item cache, like Data/ItemTypes.lua: kind<TAB>itemID,itemID,...`n")
[void]$sb.Append("DmorphOcto_ItemTypeExtra = [[`n")
$byKind = @{}
foreach ($id in $cacheType.Keys) {
  if (-not $items.ContainsKey($id)) { continue }
  $k = $cacheType[$id]
  if (-not $byKind.ContainsKey($k)) { $byKind[$k] = New-Object System.Collections.ArrayList }
  [void]$byKind[$k].Add($id)
}
foreach ($k in ($byKind.Keys | Sort-Object)) { [void]$sb.Append("$k`t$((@($byKind[$k]) | Sort-Object) -join ',')`n") }
[void]$sb.Append("]]`n")

# Item IDs worth looking up in game: Atlas-CFM's loot tables and the set pieces
# that no source here knows.
$pending = @{}
if (-not $Atlas) { $Atlas = Join-Path $GameDir "Interface\AddOns\Atlas-CFM\CFMLoot\Data" }
if (Test-Path $Atlas) {
  $files = Get-ChildItem $Atlas -Recurse -Filter *.lua | Where-Object { $_.FullName -notmatch '\\(Menu|Info)\\' -and $_.Name -notmatch '^(Crafting|ProfessionTrainers|Spells|WeaponSkills)\.lua$' }
  foreach ($f in $files) {
    foreach ($line in [IO.File]::ReadAllLines($f.FullName)) {
      if ($line -match '\{\s*id\s*=\s*(\d+)\b[^-]*(?:-[^-][^-]*)*(--\s*(.*))?$') {
        $id = [int]$matches[1]; $name = ""
        if ($matches[3]) { $name = ($matches[3] -split '\s--')[0].Trim() }
        if ($id -gt 100 -and -not $known.ContainsKey($id) -and -not $nonWearable.ContainsKey($id) -and -not $pending.ContainsKey($id)) { $pending[$id] = $name }
      }
      foreach ($m in [regex]::Matches($line, 'container\s*=\s*\{([^}]*)\}')) {
        foreach ($v in [regex]::Matches($m.Groups[1].Value, '\d+')) {
          $id = [int]$v.Value
          if ($id -gt 100 -and -not $known.ContainsKey($id) -and -not $nonWearable.ContainsKey($id) -and -not $pending.ContainsKey($id)) { $pending[$id] = "" }
        }
      }
    }
  }
}

# Item sets: ItemSet.dbc (0 ID, 1 name, 10-26 item IDs), newest MPQ first.
$setDbc = $null; $stockSets = @{}
for ($i = $mpqs.Count - 1; $i -ge 0; $i--) {
  $bytes = $mpqs[$i].Read("DBFilesClient\ItemSet.dbc")
  if ($bytes -and -not $setDbc) { $setDbc = New-Object Dbc (,$bytes) }
  if ($bytes -and $mpqs[$i].Name -ieq "patch.MPQ") { $t = New-Object Dbc (,$bytes); for ($r = 0; $r -lt $t.Count; $r++) { $stockSets[$t.Int($r, 0)] = $true } }
}
foreach ($m in $mpqs) { $m.Close() }

$visible = @{}
foreach ($k in $baseSlot.Keys) { $visible[[int]($k -split '/')[1]] = $true }
foreach ($id in $items.Keys) { $visible[$id] = $true }
$sets = New-Object System.Collections.ArrayList
for ($r = 0; $r -lt $setDbc.Count; $r++) {
  $name = $setDbc.Str($r, 1).Trim()
  $ids = @()
  for ($j = 10; $j -le 26; $j++) { $v = $setDbc.Int($r, $j); if ($v -gt 0) { $ids += $v } }
  # Only the pieces that can show on a character, or might (slot unknown).
  $shown = @($ids | Where-Object { -not $hiddenItems.ContainsKey($_) -and ($visible.ContainsKey($_) -or -not ($known.ContainsKey($_) -or $nonWearable.ContainsKey($_))) })
  if (-not $name -or $shown.Count -eq 0 -or $name.Contains("]]") -or $name.Contains("`t")) { continue }
  foreach ($id in $shown) { if (-not $visible.ContainsKey($id) -and -not $pending.ContainsKey($id)) { $pending[$id] = "" } }
  $kind = 2; if ($stockSets.ContainsKey($setDbc.Int($r, 0))) { $kind = 0 }
  [void]$sets.Add([pscustomobject]@{ id = $setDbc.Int($r, 0); name = $name; kind = $kind; items = ($shown -join ",") })
}

[void]$sb.Append("-- Item IDs whose slot isn't known here (Atlas-CFM loot tables, item set pieces): the addon asks the`n")
[void]$sb.Append("-- game about them. One per line: itemID<TAB>name (may be empty).`n")
[void]$sb.Append("DmorphOcto_ItemPending = [[`n")
foreach ($id in ($pending.Keys | Sort-Object)) { [void]$sb.Append("$id`t$($pending[$id])`n") }
[void]$sb.Append("]]`n")
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutFile), $sb.ToString(), $utf8)

$arr = $sets.ToArray()
$keys = New-Object string[] $arr.Length
for ($i = 0; $i -lt $arr.Length; $i++) { $keys[$i] = $arr[$i].name.ToLowerInvariant() + [char]1 + $arr[$i].id.ToString("D8") }
[Array]::Sort($keys, $arr, [System.Collections.IComparer][StringComparer]::Ordinal)
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("-- Generated by tools/build_items.ps1 from the client's ItemSet.dbc. Do not edit.`n")
[void]$sb.Append("-- One set per line: setID<TAB>kind<TAB>name<TAB>itemID,itemID,... (pieces that show on a character),`n")
[void]$sb.Append("-- kind 0 = in stock 1.12.1, 2 = added by Turtle WoW / OctoWoW. Sorted by name.`n")
[void]$sb.Append("DmorphOcto_SetData = [[`n")
foreach ($s in $arr) { [void]$sb.Append("$($s.id)`t$($s.kind)`t$($s.name)`t$($s.items)`n") }
[void]$sb.Append("]]`n")
[IO.File]::WriteAllText([IO.Path]::GetFullPath($SetsFile), $sb.ToString(), $utf8)

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("-- Generated by tools/build_items.ps1 from the client's files. Do not edit.`n")
[void]$sb.Append("-- Item IDs with nothing to draw in this client (display not in ItemDisplayInfo.dbc, or none of its`n")
[void]$sb.Append("-- model and texture files in the MPQs), comma-separated. The addon leaves them out.`n")
[void]$sb.Append("DmorphOcto_HiddenItems = ""$(($hiddenItems.Keys | Sort-Object) -join ',')""`n")
[IO.File]::WriteAllText([IO.Path]::GetFullPath($HiddenFile), $sb.ToString(), $utf8)

"{0} extra slot entries ({1} items, {2} only in the item cache), {3} item IDs to look up in game, {4} item sets, {5} items hidden (nothing to draw in this client)" -f `
  $extraCount, $items.Count, $fromCache, $pending.Count, $sets.Count, $hiddenItems.Count

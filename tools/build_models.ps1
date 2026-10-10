param(
  [string]$GameDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path,
  [string]$OutFile = (Join-Path $PSScriptRoot "..\Data\Models.lua"),
  [string]$LooksFile = (Join-Path $PSScriptRoot "..\Data\Looks.lua"),
  [string]$Creatures = (Join-Path $PSScriptRoot "..\Data\Creatures.lua"),
  [string]$TurtleNames = (Join-Path $PSScriptRoot "data\turtle_creatures.tsv"),
  [string]$TagsFile = (Join-Path $PSScriptRoot "..\Data\ModelTags.lua"),
  [string]$TagSource = (Join-Path $PSScriptRoot "data\turtle_ranks.tsv")
)
# Builds two files from the client's own DBFilesClient tables (read straight
# from the MPQs, newest patch first), so everything OctoWoW added is included:
#
#   Data/Models.lua  every creature display ID that Data/Creatures.lua (the
#                    1.12.1 world database) doesn't name.
#   Data/Looks.lua   per race and gender, the dressed-NPC displays: the faces,
#                    skin colours and hairstyles the look generator goes through.
#
#   powershell -ExecutionPolicy Bypass -File tools\build_models.ps1 [-GameDir C:\Games\OctoWoW]
#
# A display gets the name of a Turtle WoW creature that uses it
# (tools/data/turtle_creatures.tsv), else its model file's name ("Crystal
# Spider", plus the skin when several displays share the model), else the race
# of a dressed NPC ("Human Male NPC"). Displays whose model file is missing
# from every MPQ are left out: morphing into them would make you invisible.
# Runs on Windows PowerShell 5.1, no Python or Lua needed.

$ErrorActionPreference = "Stop"
Add-Type -Path (Join-Path $PSScriptRoot "MpqDbc.cs")

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
# 3 CreatureDisplayInfoExtra ID, 6-8 skins. Extra: 0 ID, 1 race, 2 gender,
# 3 skin, 4 face, 5 hair style, 6 hair colour, 7 facial hair, 8-17 equipment.
$models = @{}
for ($i = 0; $i -lt $modelData.Count; $i++) { $models[$modelData.Int($i, 0)] = $modelData.Str($i, 2) }
$extras = @{}
for ($i = 0; $i -lt $extraData.Count; $i++) {
  $gear = @(); $pieces = 0
  for ($j = 8; $j -le 17; $j++) { $v = $extraData.Int($i, $j); $gear += $v; if ($v -ne 0) { $pieces++ } }
  $extras[$extraData.Int($i, 0)] = [pscustomobject]@{
    race = $extraData.Int($i, 1); gender = $extraData.Int($i, 2); pieces = $pieces
    features = "{0},{1},{2},{3},{4}" -f $extraData.Int($i, 3), $extraData.Int($i, 4), $extraData.Int($i, 5),
      $extraData.Int($i, 6), $extraData.Int($i, 7)
    look = "{0},{1},{2},{3},{4}|{5}" -f $extraData.Int($i, 3), $extraData.Int($i, 4), $extraData.Int($i, 5),
      $extraData.Int($i, 6), $extraData.Int($i, 7), ($gear -join ",")
  }
}

$named = @{}
foreach ($line in [IO.File]::ReadAllLines($Creatures)) {
  if ($line -match '^(\d+)\t') { $named[[int]$matches[1]] = $true }
}
$turtle = @{}
if (Test-Path $TurtleNames) {
  foreach ($line in [IO.File]::ReadAllLines($TurtleNames)) {
    if ($line -match '^(\d+)\t(.+)$') {
      $id = [int]$matches[1]
      if (-not $turtle.ContainsKey($id)) { $turtle[$id] = New-Object System.Collections.ArrayList }
      [void]$turtle[$id].Add($matches[2].Trim())
    }
  }
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

# Sorted like Lua compares strings (byte order), so the addon can merge a
# list with Creatures.lua in one pass.
function Sort-ByName($list) {
  $arr = $list.ToArray()
  $keys = New-Object string[] $arr.Length
  for ($i = 0; $i -lt $arr.Length; $i++) { $keys[$i] = $arr[$i].name.ToLowerInvariant() + [char]1 + $arr[$i].id.ToString("D8") }
  [Array]::Sort($keys, $arr, [System.Collections.IComparer][StringComparer]::Ordinal)
  return ,$arr
}

$entries = New-Object System.Collections.ArrayList
$usable = New-Object System.Collections.ArrayList
$missing = 0; $added = 0; $total = 0; $turtleNamed = 0
$perModel = @{}
for ($i = 0; $i -lt $display.Count; $i++) {
  $id = $display.Int($i, 0)
  $total++
  $path = $models[$display.Int($i, 1)]
  if (-not $path -or -not (Test-ModelFile $path)) { $missing++; continue }
  [void]$usable.Add($i)
  if ($named.ContainsKey($id)) { continue }
  $skin = ""
  foreach ($f in 6, 7, 8) { $s = $display.Str($i, $f); if ($s) { $skin = $s; break } }
  $e = [pscustomobject]@{ id = $id; path = $path; skin = $skin; extra = $display.Int($i, 3); custom = -not $stock.ContainsKey($id); name = ""; named = $false }
  [void]$entries.Add($e)
  if ($perModel.ContainsKey($path)) { $perModel[$path]++ } else { $perModel[$path] = 1 }
}

$rows = New-Object System.Collections.ArrayList
foreach ($e in $entries) {
  if ($e.custom) { $added++ }
  if ($turtle.ContainsKey($e.id)) {
    # One entry per creature name, like Creatures.lua.
    $turtleNamed++
    foreach ($n in ($turtle[$e.id] | Sort-Object -Unique)) {
      [void]$rows.Add([pscustomobject]@{ id = $e.id; name = $n; named = $true; custom = $e.custom })
    }
    continue
  }
  $parts = $e.path -split '[\\/]'
  $base = [IO.Path]::GetFileNameWithoutExtension($e.path)
  if ($parts[0] -ieq "Character" -and $parts.Count -ge 4) {
    $race = $RACE_DIRS[$parts[1].ToLowerInvariant()]
    if (-not $race) { $race = (Split-Words $parts[1]) -join " " }
    $sex = (Split-Words $parts[2]) -join " "
    if ($e.extra -gt 0 -and $extras.ContainsKey($e.extra)) {
      $x = $extras[$e.extra]
      if ($RACES.ContainsKey($x.race)) { $race = $RACES[$x.race] }
      if ($x.gender -eq 1) { $sex = "Female" } else { $sex = "Male" }
      $name = "$race $sex NPC"
    } else {
      $name = "$race $sex (player model)"
    }
  } else {
    $words = @(Split-Words $base)
    $name = $words -join " "
    if ($perModel[$e.path] -gt 1) {
      $hint = Get-SkinHint $e.skin $base $words
      if ($hint -and $hint -ne $name) { $name = "$name ($hint)" }
    }
  }
  [void]$rows.Add([pscustomobject]@{ id = $e.id; name = $name; named = $false; custom = $e.custom })
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("-- Generated by tools/build_models.ps1 from the client's CreatureDisplayInfo.dbc. Do not edit.`n")
[void]$sb.Append("-- Every display ID that Data/Creatures.lua doesn't name, sorted by name.`n")
[void]$sb.Append("-- One per line: displayID<TAB>kind<TAB>name. Kind: 0 a creature's name (Turtle WoW database),`n")
[void]$sb.Append("-- 1 named after the model file, 2 / 3 the same for models OctoWoW added to stock 1.12.1.`n")
[void]$sb.Append("DmorphOcto_ModelData = [[`n")
foreach ($r in (Sort-ByName $rows)) {
  $kind = 1; if ($r.named) { $kind = 0 }
  if ($r.custom) { $kind += 2 }
  if ($r.name.Contains("]]") -or $r.name.Contains("`t")) { throw "name can't be stored: $($r.name)" }
  [void]$sb.Append("$($r.id)`t$kind`t$($r.name)`n")
}
[void]$sb.Append("]]`n")
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutFile), $sb.ToString(), $utf8)

# Looks: dressed-NPC displays per race and gender, the plainest outfits first
# (they show skin and hair best). Identical looks are listed once.
$looks = @{}
foreach ($i in $usable) {
  $x = $display.Int($i, 3)
  if ($x -le 0 -or -not $extras.ContainsKey($x)) { continue }
  $e = $extras[$x]
  if (-not $RACES.ContainsKey($e.race) -or $e.gender -gt 1) { continue }
  $key = "$($e.race):$($e.gender)"
  if (-not $looks.ContainsKey($key)) { $looks[$key] = @{ seen = @{}; list = New-Object System.Collections.ArrayList } }
  $bucket = $looks[$key]
  if ($bucket.seen.ContainsKey($e.look)) { continue }
  $bucket.seen[$e.look] = $true
  [void]$bucket.list.Add([pscustomobject]@{ id = $display.Int($i, 0); pieces = $e.pieces; features = $e.features })
}
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("-- Generated by tools/build_models.ps1 from the client's CreatureDisplayInfoExtra.dbc. Do not edit.`n")
[void]$sb.Append("-- Per ""race:gender"" (race IDs as in DmorphOcto.RACES, gender 0 male / 1 female): the game's dressed`n")
[void]$sb.Append("-- NPCs of that race, each look once, the fewest clothes first, separated by "";"". Each look is`n")
[void]$sb.Append("-- displayID,skin,face,hairStyle,hairColour,facialHair,pieces of clothing.`n")
[void]$sb.Append("DmorphOcto_LookData = {`n")
$lookCount = 0
foreach ($key in ($looks.Keys | Sort-Object { [int]($_ -split ':')[0] }, { [int]($_ -split ':')[1] })) {
  $ids = @($looks[$key].list | Sort-Object pieces, id | ForEach-Object { "{0},{1},{2}" -f $_.id, $_.features, $_.pieces })
  $lookCount += $ids.Count
  [void]$sb.Append("[""$key""] = ""$($ids -join ';')"",`n")
}
[void]$sb.Append("}`n")
[IO.File]::WriteAllText([IO.Path]::GetFullPath($LooksFile), $sb.ToString(), $utf8)

# Tags for the model filters: bosses and rares (Turtle WoW's creature ranks,
# by display and name) and mounts (models NPCs ride, and model files named like
# mounts: RidingHorse, DrakeMount, MechaStrider, ... but not MountainGiant).
$tagRows = New-Object System.Collections.ArrayList
$mountIds = @{}
if (Test-Path $TagSource) {
  foreach ($line in [IO.File]::ReadAllLines($TagSource)) {
    if ($line -match '^(\d+)\t(2|3|4)\t(.+)$') {
      $tag = "rare"; if ($matches[2] -eq "3") { $tag = "boss" }
      [void]$tagRows.Add("$($matches[1])`t$tag`t$($matches[3].Trim())")
    } elseif ($line -match '^(\d+)\tmount\t') {
      $mountIds[[int]$matches[1]] = $true
    }
  }
}
foreach ($i in $usable) {
  $path = $models[$display.Int($i, 1)]
  $file = [IO.Path]::GetFileNameWithoutExtension($path)
  if ($file -match '(?i)riding|mount(?!ain)|packmule|warhorse|mechastrider|hawkstrider|talbuk') { $mountIds[$display.Int($i, 0)] = $true }
}
foreach ($id in ($mountIds.Keys | Sort-Object)) { [void]$tagRows.Add("$id`tmount`t") }
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("-- Generated by tools/build_models.ps1. Do not edit.`n")
[void]$sb.Append("-- Model filter tags, one per line: displayID<TAB>tag<TAB>name. boss and rare apply to the catalogue`n")
[void]$sb.Append("-- entry with that display and name (Turtle WoW's creature ranks); mount applies to the display.`n")
[void]$sb.Append("DmorphOcto_TagData = [[`n")
foreach ($r in $tagRows) { if (-not $r.Contains("]]")) { [void]$sb.Append("$r`n") } }
[void]$sb.Append("]]`n")
[IO.File]::WriteAllText([IO.Path]::GetFullPath($TagsFile), $sb.ToString(), $utf8)
foreach ($m in $mpqs) { $m.Close() }

"{0} display IDs in the client: {1} named in Creatures.lua, {2} more in Models.lua ({3} with Turtle WoW names, {4} added by OctoWoW), {5} skipped (model file missing). {6} NPC looks." -f `
  $total, $named.Count, $entries.Count, $turtleNamed, $added, $missing, $lookCount

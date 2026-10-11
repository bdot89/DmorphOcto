param(
  [string]$GameDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path,
  [string]$OutFile = (Join-Path $PSScriptRoot "..\Data\Models.lua"),
  [string]$LooksFile = (Join-Path $PSScriptRoot "..\Data\Looks.lua"),
  [string]$Creatures = (Join-Path $PSScriptRoot "..\Data\Creatures.lua"),
  [string]$TurtleNames = (Join-Path $PSScriptRoot "data\turtle_creatures.tsv"),
  [string]$TagsFile = (Join-Path $PSScriptRoot "..\Data\ModelTags.lua"),
  [string]$TagSource = (Join-Path $PSScriptRoot "data\turtle_ranks.tsv"),
  [string]$HiddenFile = (Join-Path $PSScriptRoot "..\Data\HiddenModels.lua"),
  [string]$ClassicTags = (Join-Path $PSScriptRoot "..\Data\ClassicTags.lua")
)
# Builds two files from the client's own DBFilesClient tables (read straight
# from the MPQs, newest patch first), so everything OctoWoW added is included:
#
#   Data/Models.lua  every creature display ID that Data/Creatures.lua (the
#                    1.12.1 world database) doesn't name.
#   Data/Looks.lua   per race and gender, the dressed-NPC displays: the faces,
#                    skin colours and hairstyles the look generator goes through.
#   Data/HiddenModels.lua  the display IDs Data/Creatures.lua names that can't
#                    show in this client, so the addon leaves them out.
#
#   powershell -ExecutionPolicy Bypass -File tools\build_models.ps1 [-GameDir C:\Games\OctoWoW]
#
# A display gets the name of a Turtle WoW creature that uses it
# (tools/data/turtle_creatures.tsv), else its model file's name ("Crystal
# Spider", plus the skin when several displays share the model), else the race
# of a dressed NPC ("Human Male NPC"). Displays that can't show in game are
# left out: no model file in any MPQ, a model file this client can't load (not
# an M2 of version 256-257) or with nothing in it, or a missing skin texture
# (the model would draw white). Morphing into them would make you invisible.
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
$files = New-Object GameFiles (,[Mpq[]]$mpqs)

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
    race = $extraData.Int($i, 1); gender = $extraData.Int($i, 2); pieces = $pieces; gear = ($gear -join ",")
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

# The newest MPQ's copy of a file: its first bytes, or $null.
function Read-Start([string]$name) {
  for ($i = $mpqs.Count - 1; $i -ge 0; $i--) {
    if ($mpqs[$i].Has($name)) {
      try { return $mpqs[$i].ReadStart($name) } catch { return $null }
    }
  }
  return $null
}

function Test-AnyMpq([string]$name) { return $files.Has($name) }

# What's wrong with a model file, from its header: "format" (not an M2),
# "version" (an M2 this client can't load) or "empty" (no vertices or views);
# $null if it looks fine or can't be read.
$modelProblems = @{}
function Get-ModelProblem([string]$path) {
  if ($modelProblems.ContainsKey($path)) { return $modelProblems[$path] }
  $head = Read-Start ([IO.Path]::ChangeExtension($path, ".m2"))
  if (-not $head) { $head = Read-Start $path }
  $problem = $null
  if ($head -and $head.Length -ge 0x54) {
    if (-not ($head[0] -eq 0x4D -and $head[1] -eq 0x44 -and $head[2] -eq 0x32 -and $head[3] -eq 0x30)) {
      $problem = "format"
    } else {
      $version = [BitConverter]::ToUInt32($head, 4)
      if ($version -lt 256 -or $version -gt 257) { $problem = "version" }
      elseif ([BitConverter]::ToUInt32($head, 0x44) -eq 0 -or [BitConverter]::ToUInt32($head, 0x4C) -eq 0) { $problem = "empty" }
    }
  }
  $modelProblems[$path] = $problem
  return $problem
}

# "skin" if the display's first skin texture (next to the model) is missing.
function Get-SkinProblem([int]$row, [string]$path) {
  $skin = $display.Str($row, 6)
  if (-not $skin) { return $null }
  $dir = $path.Substring(0, $path.LastIndexOf('\') + 1)
  if (Test-AnyMpq ($dir + $skin + ".blp")) { return $null }
  return "skin"
}

# Every display's problem, if any. A check that flags more than a quarter of
# what it looks at is switched off instead: that means this script misreads
# the files, not that so much of the game is broken.
$problems = @{}; $seenIds = @{}
$checked = @{ model = 0; skin = 0 }; $flagged = @{ format = 0; version = 0; empty = 0; skin = 0 }
$paths = @{}
for ($i = 0; $i -lt $display.Count; $i++) {
  $id = $display.Int($i, 0)
  $seenIds[$id] = $true
  $path = $models[$display.Int($i, 1)]
  if (-not $path -or -not (Test-ModelFile $path)) { $problems[$id] = "missing"; continue }
  if (-not $paths.ContainsKey($path)) {
    $paths[$path] = $true
    $checked.model++
    $p = Get-ModelProblem $path
    if ($p) { $flagged[$p]++ }
  }
  $p = Get-ModelProblem $path
  if (-not $p) {
    if ($display.Str($i, 6)) { $checked.skin++ }
    $p = Get-SkinProblem $i $path
    if ($p) { $flagged.skin++ }
  }
  if ($p) { $problems[$id] = $p }
}
$off = @{}
$modelFlags = $flagged.format + $flagged.version + $flagged.empty
if ($checked.model -gt 0 -and $modelFlags -gt $checked.model / 4) {
  $off.format = $true; $off.version = $true; $off.empty = $true
  Write-Output ("warning: the model file check flagged {0} of {1} models, so it's off" -f $modelFlags, $checked.model)
}
if ($checked.skin -gt 0 -and $flagged.skin -gt $checked.skin / 4) {
  $off.skin = $true
  Write-Output ("warning: the skin texture check flagged {0} of {1} displays, so it's off" -f $flagged.skin, $checked.skin)
}
foreach ($id in @($problems.Keys)) { if ($off.ContainsKey($problems[$id])) { $problems.Remove($id) } }

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
  if ($problems.ContainsKey($id)) { $missing++; continue }
  [void]$usable.Add($i)
  if ($named.ContainsKey($id)) { continue }
  $skin = ""
  foreach ($f in 6, 7, 8) { $s = $display.Str($i, $f); if ($s) { $skin = $s; break } }
  $e = [pscustomobject]@{ id = $id; path = $path; skin = $skin; extra = $display.Int($i, 3); custom = -not $stock.ContainsKey($id); name = ""; named = $false }
  [void]$entries.Add($e)
  if ($perModel.ContainsKey($path)) { $perModel[$path]++ } else { $perModel[$path] = 1 }
}

# Famous mounts get their name as well (model file -> name), so a search finds them.
$MOUNT_NAMES = @{ "Creature\Phoenix\Phoenix.mdx" = "Ashes of Al'ar (Phoenix)" }

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
# Famous mounts ($MOUNT_NAMES, below) under their own name too.
foreach ($e in $entries) {
  foreach ($key in $MOUNT_NAMES.Keys) {
    if ($e.path -ieq $key) {
      [void]$rows.Add([pscustomobject]@{ id = $e.id; name = $MOUNT_NAMES[$key]; named = $true; custom = $e.custom })
    }
  }
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
  [void]$bucket.list.Add([pscustomobject]@{ id = $display.Int($i, 0); pieces = $e.pieces; features = $e.features; gear = $e.gear })
}
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("-- Generated by tools/build_models.ps1 from the client's CreatureDisplayInfoExtra.dbc. Do not edit.`n")
[void]$sb.Append("-- Per ""race:gender"" (race IDs as in DmorphOcto.RACES, gender 0 male / 1 female): the game's dressed`n")
[void]$sb.Append("-- NPCs of that race, each look once, the fewest clothes first, separated by "";"". Each look is`n")
[void]$sb.Append("-- displayID,skin,face,hairStyle,hairColour,facialHair,pieces of clothing,outfit (looks with the same`n")
[void]$sb.Append("-- outfit number wear the same clothes; 0 = none).`n")
[void]$sb.Append("DmorphOcto_LookData = {`n")
$lookCount = 0
foreach ($key in ($looks.Keys | Sort-Object { [int]($_ -split ':')[0] }, { [int]($_ -split ':')[1] })) {
  $outfits = @{}
  $ids = @($looks[$key].list | Sort-Object pieces, id | ForEach-Object {
    $o = 0
    if ($_.pieces -gt 0) {
      if (-not $outfits.ContainsKey($_.gear)) { $outfits[$_.gear] = $outfits.Count + 1 }
      $o = $outfits[$_.gear]
    }
    "{0},{1},{2},{3}" -f $_.id, $_.features, $_.pieces, $o
  })
  $lookCount += $ids.Count
  [void]$sb.Append("[""$key""] = ""$($ids -join ';')"",`n")
}
[void]$sb.Append("}`n")
[IO.File]::WriteAllText([IO.Path]::GetFullPath($LooksFile), $sb.ToString(), $utf8)

# Tags for the model filters: bosses and rares (Turtle WoW's creature ranks,
# by display and name) and mounts: every model built to be ridden (see below).
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
# Mounts we know: what NPCs ride (above), the 1.12.1 database's mount spells
# (Data/ClassicTags.lua), and models whose file or skin is named like a mount
# (RidingHorse, DrakeMount, SpectralRidingTigerArmored, ... not MountainGiant).
$MOUNT_NAME = '(?i)riding|mount(?!ain)|packmule|warhorse|mechastrider|hawkstrider|talbuk'
# Models OctoWoW brought from later expansions that players ride but whose
# file isn't named like a mount and has no rider point (checked on the
# 11 Oct 2026 client): Al'ar's phoenix, the winged and celestial horses,
# Northrend drakes, the victorious steed, armoured raptor, lava and fel
# horses, Antonidas' horse, nether rays, and the flight masters' wyverns,
# hippogryphs, ghost gryphon and Turtle WoW's riding turtle.
$MOUNT_MODEL = '(?i)\\(phoenix\\phoenix|wingedhorse\\|celestialhorse\\|drake\\northrenddrake|warhorse\\victorius|armoredraptor\\|lavahorse\\|felhorse\\felhorseepic|antonidashorse\\|netherray\\|wyvern\\wyvern\.|hippogryph\\hippogryph\.|gryphon\\gryphon_ghost|turtle\\turtle\.)'
if (Test-Path $ClassicTags) {
  foreach ($line in [IO.File]::ReadAllLines($ClassicTags)) {
    if ($line -match '^(\d+)\tmount\t') { $mountIds[[int]$matches[1]] = $true }
  }
}
$pathOf = @{}
foreach ($i in $usable) {
  $id = $display.Int($i, 0)
  $path = $models[$display.Int($i, 1)]
  $pathOf[$id] = $path
  foreach ($n in @([IO.Path]::GetFileNameWithoutExtension($path), $display.Str($i, 6), $display.Str($i, 7), $display.Str($i, 8))) {
    if ($n -and $n -match $MOUNT_NAME) { $mountIds[$id] = $true }
  }
  if ("\$path" -match $MOUNT_MODEL) { $mountIds[$id] = $true }
}

# The game's own mount spells (Spell.dbc, Turtle WoW's and OctoWoW's shop
# mounts included): a spell that mounts you (aura 78) is named after its
# mount, so a display with that name whose model has the rider point (below)
# is a mount. 1.12.1 Spell.dbc: auras 91-93, English name 120; checked on
# 1.12's own mount spells (Brown Horse, Timber Wolf, ...) before it's used.
$MOUNT_SPELLS = @(458, 470, 472, 580, 5784, 6648, 6653, 6654, 6777, 6898, 6899, 8394, 8395, 10789, 10793,
  10796, 10799, 10873, 10969, 13819, 17462, 17463, 17464, 17465, 18989, 18990, 23214)
$spellNote = "Spell.dbc not read"
$spells = $null
for ($i = $mpqs.Count - 1; $i -ge 0 -and -not $spells; $i--) {
  $bytes = $mpqs[$i].Read("DBFilesClient\Spell.dbc")
  if ($bytes) { $spells = New-Object Dbc (,$bytes) }
}
if ($spells -and $spells.Fields -gt 121) {
  $rowOfSpell = @{}
  for ($r = 0; $r -lt $spells.Count; $r++) { $rowOfSpell[$spells.Int($r, 0)] = $r }
  $present = 0; $mounting = 0
  foreach ($sid in $MOUNT_SPELLS) {
    if (-not $rowOfSpell.ContainsKey($sid)) { continue }
    $present++
    $r = $rowOfSpell[$sid]
    if (($spells.Int($r, 91) -eq 78 -or $spells.Int($r, 92) -eq 78 -or $spells.Int($r, 93) -eq 78) -and $spells.TryStr($r, 120)) { $mounting++ }
  }
  if ($present -ge 8 -and $mounting -ge 0.6 * $present) {
    # Display names: Creatures.lua's and Models.lua's (without the "(skin)" part).
    $displaysNamed = @{}
    function Add-DisplayName([int]$id, [string]$name) {
      $key = (($name -replace ' \(.*$', '') -replace '\s+', ' ').Trim().ToLowerInvariant()
      if (-not $key) { return }
      if (-not $displaysNamed.ContainsKey($key)) { $displaysNamed[$key] = @{} }
      $displaysNamed[$key][$id] = $true
    }
    foreach ($line in [IO.File]::ReadAllLines($Creatures)) { if ($line -match '^(\d+)\t(.+)$') { Add-DisplayName ([int]$matches[1]) $matches[2] } }
    foreach ($r in $rows) { Add-DisplayName $r.id $r.name }
    $mountSpells = 0; $byName = 0
    for ($r = 0; $r -lt $spells.Count; $r++) {
      if (-not ($spells.Int($r, 91) -eq 78 -or $spells.Int($r, 92) -eq 78 -or $spells.Int($r, 93) -eq 78)) { continue }
      $name = $spells.TryStr($r, 120)
      if (-not $name) { continue }
      $mountSpells++
      $key = (($name -replace '^(?i)summon ', '') -replace '\s+', ' ').Trim().ToLowerInvariant()
      # A name many displays share is too common to say which one is the mount.
      if (-not $displaysNamed.ContainsKey($key) -or $displaysNamed[$key].Count -gt 12) { continue }
      foreach ($id in $displaysNamed[$key].Keys) {
        if ($mountIds.ContainsKey($id) -or -not $pathOf.ContainsKey($id)) { continue }
        if ($pathOf[$id] -match '^(?i)creature\\' -and $files.MountPoint($pathOf[$id]) -eq 1) { $mountIds[$id] = $true; $byName++ }
      }
    }
    $spellNote = "{0} mount spells in the game, {1} more displays by their names" -f $mountSpells, $byName
  } else {
    Write-Output ("warning: Spell.dbc doesn't look as expected ({0} of {1} known mount spells read as mounts), so mount spell names aren't used" -f $mounting, $present)
    $spellNote = "Spell.dbc not used"
  }
}

# Every model built to be ridden has attachment point 0, where the rider sits
# (shop mounts like the Spectral Tigers included, whatever they're called). The
# rule is checked on the mounts we know first: if most of their creature models
# have the point and most creature models don't, every creature model that has
# it is a mount. Either way, every display of a known mount's model is one.
$isCreature = '^(?i)creature\\'
$seedPaths = @{}
foreach ($id in $mountIds.Keys) {
  if ($pathOf.ContainsKey($id) -and $pathOf[$id] -match $isCreature) { $seedPaths[$pathOf[$id]] = $true }
}
$point = @{}
foreach ($path in $pathOf.Values) {
  if ($path -match $isCreature -and -not $point.ContainsKey($path)) { $point[$path] = $files.MountPoint($path) }
}
$seedYes = 0; $seedKnown = 0; $allYes = 0; $allKnown = 0
foreach ($path in $point.Keys) {
  $v = $point[$path]
  if ($v -lt 0) { continue }
  $allKnown++; if ($v -eq 1) { $allYes++ }
  if ($seedPaths.ContainsKey($path)) { $seedKnown++; if ($v -eq 1) { $seedYes++ } }
}
$byPoint = $seedKnown -ge 5 -and $seedYes -ge 0.8 * $seedKnown -and $allYes -le 0.5 * $allKnown
$known = $mountIds.Count
$nameOf = @{}
foreach ($r in $rows) { if (-not $nameOf.ContainsKey($r.id)) { $nameOf[$r.id] = $r.name } }
foreach ($line in [IO.File]::ReadAllLines($Creatures)) {
  if ($line -match '^(\d+)\t(.+)$' -and -not $nameOf.ContainsKey([int]$matches[1])) { $nameOf[[int]$matches[1]] = $matches[2] }
}
$examples = @{}
foreach ($id in @($pathOf.Keys)) {
  $path = $pathOf[$id]
  if (-not $mountIds.ContainsKey($id) -and ($seedPaths.ContainsKey($path) -or ($byPoint -and $point[$path] -eq 1))) {
    $mountIds[$id] = $true
    if ($nameOf.ContainsKey($id)) { $examples[($nameOf[$id] -replace ' \(.*$', '')] = $true }
  }
}
if (-not $byPoint) {
  Write-Output ("warning: the rider point was on {0} of {1} known mount models and {2} of {3} creature models, so only known mounts and their other skins count" -f `
    $seedYes, $seedKnown, $allYes, $allKnown)
}
"Mounts: {0} displays ({1} known; {6}; {2} more from the same models or their rider point, which {3} of {4} known mount models have). New, for example: {5}" -f `
  $mountIds.Count, $known, ($mountIds.Count - $known), $seedYes, $seedKnown, ((@($examples.Keys) | Sort-Object | Select-Object -First 12) -join ", "), $spellNote
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

# The display IDs Creatures.lua names that this client can't show: not in its
# CreatureDisplayInfo.dbc at all, or with one of the problems above. Not
# written if that would be more than a quarter of them (same reason as above).
$hidden = New-Object System.Collections.ArrayList
foreach ($id in ($named.Keys | Sort-Object)) {
  if (-not $seenIds.ContainsKey($id) -or $problems.ContainsKey($id)) { [void]$hidden.Add($id) }
}
if ($named.Count -gt 0 -and $hidden.Count -gt $named.Count / 4) {
  Write-Output ("warning: {0} of the {1} named displays would be hidden, so none are" -f $hidden.Count, $named.Count)
  $hidden.Clear()
}
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("-- Generated by tools/build_models.ps1 from the client's files. Do not edit.`n")
[void]$sb.Append("-- Display IDs from Data/Creatures.lua that can't show in this client (no such display, model file`n")
[void]$sb.Append("-- missing, empty or unreadable, skin texture missing), comma-separated. The addon leaves them out.`n")
[void]$sb.Append("DmorphOcto_HiddenModels = ""$($hidden -join ',')""`n")
[IO.File]::WriteAllText([IO.Path]::GetFullPath($HiddenFile), $sb.ToString(), $utf8)

$reasons = @{}
foreach ($id in $problems.Keys) { $reasons[$problems[$id]] = 1 + [int]$reasons[$problems[$id]] }
"Checked against the game files: {0} named displays hidden; left out: {1} no model file, {2} not a loadable M2, {3} empty, {4} missing skin." -f `
  $hidden.Count, [int]$reasons["missing"], ([int]$reasons["format"] + [int]$reasons["version"]), [int]$reasons["empty"], [int]$reasons["skin"]

"{0} display IDs in the client: {1} named in Creatures.lua, {2} more in Models.lua ({3} with Turtle WoW names, {4} added by OctoWoW), {5} skipped (can't show in game). {6} NPC looks." -f `
  $total, $named.Count, $entries.Count, $turtleNamed, $added, $missing, $lookCount

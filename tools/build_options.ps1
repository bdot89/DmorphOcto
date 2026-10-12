param(
  [string]$GameDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path,
  [string]$GlowFile = (Join-Path $PSScriptRoot "..\Data\Glows.lua"),
  [string]$OptionsFile = (Join-Path $PSScriptRoot "..\Data\CharOptions.lua")
)
# Builds two files from the client's own DBFilesClient tables, for the parts of
# DMorph that need DmorphHelper.dll:
#
#   Data/Glows.lua        every weapon enchant glow this client can draw: each
#                         ItemVisuals entry an enchant uses (SpellItemEnchantment)
#                         whose effect models (ItemVisualEffects) are in the MPQs,
#                         with an enchant that shows it and the enchants' names.
#   Data/CharOptions.lua  per race and gender, the skin colours, faces, hair
#                         styles, hair colours and facial hair a player model can
#                         wear (CharSections, CharHairGeosets,
#                         CharacterFacialHairStyles), leaving out any whose
#                         texture isn't in the MPQs.
#
#   powershell -ExecutionPolicy Bypass -File tools\build_options.ps1 [-GameDir C:\Games\OctoWoW]
#
# The tables' columns are checked against what they hold before they're used
# (OctoWoW could have changed them); a table that doesn't look as expected is
# skipped with a warning and its file is written empty.
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
  if ($file.Name -ieq "patch-Z.mpq" -or $file.Name -ieq "patch-Y.mpq") { continue } # the model porting tool's, only on that PC
  # Archives made by the model porting tool (marked with DmorphPort.txt) are only on that PC.
  try { $m = New-Object Mpq $file.FullName; if ($m.Has("DmorphPort.txt")) { continue }; $mpqs += $m } catch { Write-Output ("skipped {0}: {1}" -f $file.Name, $_.Exception.Message) }
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

# How many different texts a field holds. A number field can look like text
# (1 is where the first string starts), but then it's the same few texts.
function Get-TextCount($table, [int]$field) {
  $seen = @{}
  for ($r = 0; $r -lt $table.Count; $r++) {
    $t = $table.TryStr($r, $field)
    if ($null -ne $t) { $seen[$t] = $true }
  }
  return $seen.Count
}

# "Spells\Enchantments\Sparkle_A.mdx" -> "Sparkle_A".
function Get-BaseName([string]$path) {
  $name = ($path -split '[\\/]')[-1]
  $dot = $name.LastIndexOf('.')
  if ($dot -gt 0) { $name = $name.Substring(0, $dot) }
  return $name
}

# Whether a model or texture named in a table is in the MPQs (.mdx models are
# stored as .m2; texture names may leave out .blp).
function Test-GameFile([string]$path) {
  if (-not $path) { return $false }
  $lower = $path.ToLowerInvariant()
  if ($lower.EndsWith(".mdx") -or $lower.EndsWith(".mdl")) { return $files.Has($path.Substring(0, $path.Length - 4) + ".m2") }
  if ($lower.EndsWith(".blp") -or $lower.EndsWith(".m2")) { return $files.Has($path) }
  return $files.Has($path) -or $files.Has($path + ".blp")
}

# When a table can't be read, a line to send in: per field its smallest and
# largest value, how many different values and texts it holds, and with $ids,
# how many of its non-zero values are keys of $ids. Then the first two rows.
function Show-Table($table, [string]$label, $ids) {
  $parts = @(); $texts = @{}
  for ($f = 0; $f -lt $table.Fields; $f++) {
    $min = [int]::MaxValue; $max = [int]::MinValue; $seen = @{}; $hits = 0; $nonZero = 0
    for ($r = 0; $r -lt $table.Count; $r++) {
      $v = $table.Int($r, $f)
      if ($v -lt $min) { $min = $v }
      if ($v -gt $max) { $max = $v }
      $seen[$v] = $true
      if ($v -ne 0) { $nonZero++; if ($ids -and $ids.ContainsKey($v)) { $hits++ } }
    }
    $part = "{0}:{1}..{2}/{3}" -f $f, $min, $max, $seen.Count
    $t = Get-TextCount $table $f
    if ($t -ge 3 -and $f -gt 0) { $part += " text$t"; $texts[$f] = $true }
    if ($ids) { $part += " v$hits/$nonZero" }
    $parts += $part
  }
  Write-Output ("report {0}: {1} rows, {2} fields of {3} bytes: {4}" -f $label, $table.Count, $table.Fields, $table.Size, ($parts -join "; "))
  for ($r = 0; $r -lt [Math]::Min(2, $table.Count); $r++) {
    $values = @()
    for ($f = 0; $f -lt $table.Fields; $f++) {
      $t = $table.TryStr($r, $f)
      if ($t -and $texts.ContainsKey($f)) { $values += """$t""" } else { $values += $table.Int($r, $f) }
    }
    Write-Output ("report {0} row {1}: {2}" -f $label, $r, ($values -join ", "))
  }
}

$utf8 = New-Object System.Text.UTF8Encoding($false)

# Glows ---------------------------------------------------------------------------

# 1.12.1 layouts: SpellItemEnchantment 0 ID, 1-12 effects, 13-21 name (8
# locales and a mask), 22 ItemVisual, 23 flags. ItemVisuals 0 ID, 1-5
# ItemVisualEffects IDs. ItemVisualEffects 0 ID, 1 model. The name is the text
# field with the most different texts. The visual is field 22 if at least 4
# in 5 of its non-zero values are ItemVisuals IDs (some may point at a visual
# the client doesn't have), else the field after the name that does best.
$glows = New-Object System.Collections.ArrayList
$glowNote = ""
$enchants = Read-Newest "DBFilesClient\SpellItemEnchantment.dbc"
$visuals = Read-Newest "DBFilesClient\ItemVisuals.dbc"
$effects = Read-Newest "DBFilesClient\ItemVisualEffects.dbc"
if (-not ($enchants -and $visuals -and $effects)) {
  Write-Output "warning: SpellItemEnchantment, ItemVisuals or ItemVisualEffects.dbc is missing, so no glows"
} else {
  $effectModel = @{}
  for ($r = 0; $r -lt $effects.Count; $r++) {
    $m = $effects.TryStr($r, 1)
    if ($m) { $effectModel[$effects.Int($r, 0)] = $m }
  }
  $visualEffects = @{}
  for ($r = 0; $r -lt $visuals.Count; $r++) {
    $list = @()
    for ($j = 1; $j -lt [Math]::Min(6, $visuals.Fields); $j++) {
      $e = $visuals.Int($r, $j)
      if ($effectModel.ContainsKey($e)) { $list += $effectModel[$e] }
    }
    $visualEffects[$visuals.Int($r, 0)] = $list
  }

  $nameField = -1; $best = 2
  for ($f = 1; $f -lt $enchants.Fields; $f++) {
    $n = Get-TextCount $enchants $f
    if ($n -gt $best) { $best = $n; $nameField = $f }
  }
  # How many different ItemVisuals IDs a field holds, or 0 if fewer than 4 in
  # 5 of its non-zero values are ItemVisuals IDs.
  function Get-VisualScore([int]$f) {
    $nonZero = 0; $hits = 0; $seen = @{}
    for ($r = 0; $r -lt $enchants.Count; $r++) {
      $v = $enchants.Int($r, $f)
      if ($v -eq 0) { continue }
      $nonZero++
      if ($visualEffects.ContainsKey($v)) { $hits++; $seen[$v] = $true }
    }
    if ($hits -lt 0.8 * $nonZero -or $seen.Count -lt 3) { return 0 }
    return $seen.Count
  }
  $visualField = -1
  if ($enchants.Fields -gt 22 -and $nameField -ne 22 -and (Get-VisualScore 22) -gt 0) {
    $visualField = 22
  } else {
    $bestScore = 0
    for ($f = [Math]::Max(1, $nameField + 1); $f -lt $enchants.Fields; $f++) {
      $score = Get-VisualScore $f
      if ($score -gt $bestScore) { $bestScore = $score; $visualField = $f }
    }
  }

  if ($visualField -lt 0) {
    Write-Output "warning: couldn't find the ItemVisual field in SpellItemEnchantment.dbc, so no glows. Please send these lines:"
    Show-Table $enchants "SpellItemEnchantment" $visualEffects
    Show-Table $visuals "ItemVisuals" $null
  } else {
    # visual -> @{ enchant (lowest ID); names }
    $byVisual = @{}; $withGlow = 0
    for ($r = 0; $r -lt $enchants.Count; $r++) {
      $v = $enchants.Int($r, $visualField)
      if ($v -eq 0 -or -not $visualEffects.ContainsKey($v)) { continue }
      $withGlow++
      $id = $enchants.Int($r, 0)
      $name = ""
      if ($nameField -ge 0) { $name = $enchants.TryStr($r, $nameField) }
      if ($name) { $name = ($name -replace '\s+', ' ').Trim() }
      if (-not $byVisual.ContainsKey($v)) { $byVisual[$v] = @{ enchant = $id; names = New-Object System.Collections.ArrayList } }
      $g = $byVisual[$v]
      if ($id -lt $g.enchant) { $g.enchant = $id }
      if ($name -and -not $name.Contains("]]") -and -not $name.Contains("`t") -and -not $g.names.Contains($name)) { [void]$g.names.Add($name) }
    }
    # Glows whose effect models are all missing can't show. More than a
    # quarter missing means the check misreads the files: then keep them all.
    $missing = @($byVisual.Keys | Where-Object { -not (@($visualEffects[$_] | Where-Object { Test-GameFile $_ }).Count) })
    if ($missing.Count -gt $byVisual.Count / 4) {
      Write-Output ("warning: {0} of {1} glows have no effect model in the MPQs, so none are left out" -f $missing.Count, $byVisual.Count)
      $missing = @()
    }
    $skip = @{}
    foreach ($v in $missing) { $skip[$v] = $true }
    foreach ($v in $byVisual.Keys) {
      if ($skip.ContainsKey($v)) { continue }
      $g = $byVisual[$v]
      $models = @($visualEffects[$v] | Where-Object { Test-GameFile $_ } | ForEach-Object { Get-BaseName $_ } | Select-Object -Unique)
      $names = @($g.names | Sort-Object { $_.Length }, { $_ })
      $first = "Glow $v"
      if ($names.Count) { $first = $names[0] }
      [void]$glows.Add([pscustomobject]@{ visual = $v; enchant = $g.enchant; first = $first;
        names = ($names -join "; "); models = ($models -join ", ") })
    }
    $glowNote = "{0} enchants with a glow, {1} glows left out (no effect model)" -f $withGlow, $missing.Count
  }
}

$arr = $glows.ToArray()
$keys = New-Object string[] $arr.Length
for ($i = 0; $i -lt $arr.Length; $i++) { $keys[$i] = $arr[$i].first.ToLowerInvariant() + [char]1 + $arr[$i].visual.ToString("D8") }
[Array]::Sort($keys, $arr, [System.Collections.IComparer][StringComparer]::Ordinal)
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("-- Generated by tools/build_options.ps1 from the client's files. Do not edit.`n")
[void]$sb.Append("-- Every weapon enchant glow this client can draw, one per line:`n")
[void]$sb.Append("-- visualID<TAB>enchantID<TAB>names of the enchants that show it (; between)<TAB>effect models.`n")
[void]$sb.Append("DmorphOcto_GlowData = [[`n")
foreach ($g in $arr) { [void]$sb.Append("$($g.visual)`t$($g.enchant)`t$($g.names)`t$($g.models)`n") }
[void]$sb.Append("]]`n")
[IO.File]::WriteAllText([IO.Path]::GetFullPath($GlowFile), $sb.ToString(), $utf8)

# Character options ---------------------------------------------------------------

# 1.12.1 CharSections: 0 ID, 1 race, 2 gender, 3 section (0 skin, 1 face, 2
# facial hair, 3 hair, 4 underwear), 4 variation, 5 colour, 6-8 textures, 9
# flags (later clients put the textures first and the flags before the
# variation). Skin rows have variation 0 and the skin colour as colour; faces
# have the face as variation and the skin colour as colour; hair has the style
# as variation and the hair colour as colour.
$options = @{} # "race:gender" -> @{ skin; face; hairStyle; hairColour; facial; npc... }
$optionNote = ""
$sections = Read-Newest "DBFilesClient\CharSections.dbc"
$hairGeo = Read-Newest "DBFilesClient\CharHairGeosets.dbc"
$facialGeo = Read-Newest "DBFilesClient\CharacterFacialHairStyles.dbc"

# How well a CharSections layout reads: $null unless at least 9 in 10 rows
# have a section 0-4, a gender 0-1 and a variation and colour 0-255, at least
# 3 in 10 have a texture, and the skin rows have variation 0 (a layout with
# the two the other way round is swapped).
function Test-Layout($table, $c) {
  if ($table.Fields -le [Math]::Max($c.flags, $c.text + 2)) { return $null }
  $good = 0; $textRows = 0; $skins = 0; $zeroVar = 0; $zeroCol = 0
  for ($r = 0; $r -lt $table.Count; $r++) {
    $s = $table.Int($r, 3); $g = $table.Int($r, 2); $v = $table.Int($r, $c.variation); $k = $table.Int($r, $c.colour)
    if ($s -ge 0 -and $s -le 4 -and $g -ge 0 -and $g -le 1 -and $v -ge 0 -and $v -le 255 -and $k -ge 0 -and $k -le 255) { $good++ }
    if ($null -ne $table.TryStr($r, $c.text)) { $textRows++ }
    if ($s -eq 0) {
      $skins++
      if ($v -eq 0) { $zeroVar++ }
      if ($k -eq 0) { $zeroCol++ }
    }
  }
  if ($good -lt 0.9 * $table.Count -or $textRows -lt 0.3 * $table.Count -or $skins -eq 0) { return $null }
  if ((Get-TextCount $table $c.text) -lt 10) { return $null }
  $c = $c.Clone()
  if ($zeroVar -lt 0.8 * $skins) {
    if ($zeroCol -lt 0.8 * $skins) { return $null }
    $v = $c.variation; $c.variation = $c.colour; $c.colour = $v
  }
  return $c
}

# The 1.12.1 layout, then the later one (textures before the flags, variation
# and colour), then whatever the texts say.
function Find-Columns($table) {
  if (-not $table -or $table.Fields -lt 7 -or $table.Count -eq 0) { return $null }
  $layouts = @(
    @{ variation = 4; colour = 5; text = 6; flags = 9 },
    @{ text = 4; flags = 7; variation = 8; colour = 9 }
  )
  for ($f = 4; $f -lt $table.Fields; $f++) {
    if ((Get-TextCount $table $f) -ge 10) {
      $ints = @()
      for ($i = 4; $i -lt $table.Fields; $i++) { if ($i -lt $f -or $i -gt $f + 2) { $ints += $i } }
      if ($ints.Count -ge 3) {
        if ($f -eq 4) { $layouts += @{ flags = $ints[0]; variation = $ints[1]; colour = $ints[2]; text = $f } }
        else { $layouts += @{ variation = $ints[0]; colour = $ints[1]; flags = $ints[2]; text = $f } }
      }
      break
    }
  }
  foreach ($c in $layouts) {
    $found = Test-Layout $table $c
    if ($found) { return $found }
  }
  return $null
}

# Race, gender and variation columns of CharHairGeosets (after an ID) or
# CharacterFacialHairStyles (no ID in 1.12): the first place where they hold
# races, genders and small numbers, mostly one row each.
function Find-Variations($table) {
  if (-not $table -or $table.Count -eq 0) { return $null }
  for ($c = 0; $c -le 1 -and $c + 2 -lt $table.Fields; $c++) {
    $list = @{}; $good = 0
    for ($r = 0; $r -lt $table.Count; $r++) {
      $race = $table.Int($r, $c); $g = $table.Int($r, $c + 1); $v = $table.Int($r, $c + 2)
      if ($race -lt 1 -or $race -gt 63 -or $g -lt 0 -or $g -gt 1 -or $v -lt 0 -or $v -gt 99) { continue }
      $good++
      if (-not $list.ContainsKey("$race`:$g")) { $list["$race`:$g"] = @{} }
      $list["$race`:$g"][$v] = $true
    }
    $distinct = 0
    foreach ($k in $list.Keys) { $distinct += $list[$k].Count }
    if ($good -ge $table.Count * 0.95 -and $distinct -ge $table.Count * 0.9) { return $list }
  }
  return $null
}

$cols = Find-Columns $sections
if (-not $cols) {
  Write-Output "warning: CharSections.dbc is missing or doesn't look as expected, so no character options. Please send these lines:"
  if ($sections) { Show-Table $sections "CharSections" $null }
} else {
  # A row with none of its textures in the MPQs, or a skin row without its
  # first (the body), would draw white: leave it out, unless that's more than
  # a quarter of the rows (then the check is wrong). The game skips a missing
  # extra layer (many beards list an upper layer that was never made), so a
  # row with some of its textures is kept.
  $SECTION_NAMES = @("skin", "face", "facial hair", "hair", "underwear")
  $rows = New-Object System.Collections.ArrayList
  $dropped = 0; $withTexture = 0; $partial = 0; $missingTex = New-Object System.Collections.ArrayList; $droppedBy = @{}
  for ($r = 0; $r -lt $sections.Count; $r++) {
    $tex = @()
    for ($j = 0; $j -lt 3; $j++) { $t = $sections.TryStr($r, $cols.text + $j); if ($t) { $tex += $t } }
    $shows = $true
    if ($tex.Count) {
      $withTexture++
      $absent = @($tex | Where-Object { -not (Test-GameFile $_) })
      $section = $sections.Int($r, 3)
      $shows = $absent.Count -lt $tex.Count -and -not ($section -eq 0 -and $absent -contains $tex[0])
      if (-not $shows) {
        $dropped++
        $what = "other"; if ($section -ge 0 -and $section -le 4) { $what = $SECTION_NAMES[$section] }
        $droppedBy[$what] = 1 + [int]$droppedBy[$what]
        if ($missingTex.Count -lt 3) { [void]$missingTex.Add($absent[0]) }
      } elseif ($absent.Count) {
        $partial++
      }
    }
    [void]$rows.Add([pscustomobject]@{ race = $sections.Int($r, 1); gender = $sections.Int($r, 2); section = $sections.Int($r, 3)
      variation = $sections.Int($r, $cols.variation); colour = $sections.Int($r, $cols.colour)
      flags = $sections.Int($r, $cols.flags); shows = $shows })
  }
  if ($dropped -gt $withTexture / 4) {
    Write-Output ("warning: {0} of {1} CharSections textures aren't in the MPQs, so none are left out" -f $dropped, $withTexture)
    foreach ($row in $rows) { $row.shows = $true }
    $dropped = 0
  }
  # Flag 1 marks what character creation offers (the rest are NPC-only) if
  # skin colour 0, which every race offers, mostly has it.
  $skin0 = @($rows | Where-Object { $_.section -eq 0 -and $_.colour -eq 0 })
  $flagged = @($skin0 | Where-Object { ($_.flags -band 1) -ne 0 }).Count
  $markNpc = $skin0.Count -gt 0 -and $flagged -ge $skin0.Count * 0.8
  $hairStyles = Find-Variations $hairGeo
  $facialStyles = Find-Variations $facialGeo
  if (-not $hairStyles) { Write-Output "warning: CharHairGeosets.dbc is missing or doesn't look as expected; hair styles come from CharSections" }
  if (-not $facialStyles) { Write-Output "warning: CharacterFacialHairStyles.dbc is missing or doesn't look as expected; facial hair comes from CharSections" }

  function Add-Value($set, $key, [int]$value, [bool]$player) {
    if (-not $set.ContainsKey($key)) { $set[$key] = @{} }
    if (-not $set[$key].ContainsKey($value)) { $set[$key][$value] = $false }
    if ($player) { $set[$key][$value] = $true }
  }
  foreach ($row in $rows) {
    if (-not $row.shows) { continue }
    $key = "$($row.race):$($row.gender)"
    if (-not $options.ContainsKey($key)) {
      $options[$key] = @{ skin = @{}; face = @{}; hair = @{}; facialTex = @{} }
    }
    $o = $options[$key]
    $player = (-not $markNpc) -or (($row.flags -band 1) -ne 0)
    switch ($row.section) {
      0 { if ($row.variation -eq 0) { Add-Value $o.skin "all" $row.colour $player } }
      1 { Add-Value $o.face $row.colour $row.variation $player }
      2 { Add-Value $o.facialTex "all" $row.variation $player }
      3 { Add-Value $o.hair $row.variation $row.colour $player }
    }
  }
  $optionNote = "{0} races and genders" -f $options.Count
  if ($dropped) {
    $by = ($droppedBy.Keys | Sort-Object | ForEach-Object { "$($droppedBy[$_]) $_" }) -join ", "
    $optionNote += ", {0} of {1} looks left out ({2}; no texture, e.g. {3})" -f $dropped, $withTexture, $by, ($missingTex -join ", ")
  }
  if ($partial) { $optionNote += ", {0} kept without an extra layer the game doesn't have" -f $partial }
}

# A Lua list of numbers, and the NPC-only ones of a value set as a Lua set.
function Format-List($values) { return "{ " + ((@($values) | Sort-Object { [int]$_ }) -join ", ") + " }" }
function Format-Npc($set) {
  $npc = @($set.Keys | Where-Object { -not $set[$_] } | Sort-Object { [int]$_ })
  if (-not $npc.Count) { return "{}" }
  return "{ " + (($npc | ForEach-Object { "[$_] = true" }) -join ", ") + " }"
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("-- Generated by tools/build_options.ps1 from the client's CharSections, CharHairGeosets and`n")
[void]$sb.Append("-- CharacterFacialHairStyles tables. Do not edit. Per ""race:gender"" (gender 0 male, 1 female),`n")
[void]$sb.Append("-- the values a player model can wear: skin colours, faces per skin colour, hair styles, hair`n")
[void]$sb.Append("-- colours per hair style (anyHairColour for styles with no texture of their own), facial`n")
[void]$sb.Append("-- hair. npc* are the values character creation doesn't offer.`n")
[void]$sb.Append("DmorphOcto_CharOptions = {`n")
foreach ($key in ($options.Keys | Sort-Object { [int]($_ -split ':')[0] }, { [int]($_ -split ':')[1] })) {
  $o = $options[$key]
  if (-not $o.skin.ContainsKey("all")) { continue }
  $skins = $o.skin["all"]
  # Hair styles: the geoset table's, else the ones with hair textures.
  $styles = @{}
  if ($hairStyles -and $hairStyles.ContainsKey($key)) { foreach ($v in $hairStyles[$key].Keys) { $styles[$v] = $true } }
  else { foreach ($v in $o.hair.Keys) { $styles[$v] = $true } }
  # Each value set maps a value to whether character creation offers it.
  $stylePlayer = @{}
  foreach ($v in $styles.Keys) {
    $stylePlayer[$v] = $true
    if ($o.hair.ContainsKey($v) -and -not @($o.hair[$v].Values | Where-Object { $_ }).Count) { $stylePlayer[$v] = $false }
  }
  $anyColour = @{}
  foreach ($v in $o.hair.Keys) { foreach ($c in $o.hair[$v].Keys) { if (-not $anyColour.ContainsKey($c) -or $o.hair[$v][$c]) { $anyColour[$c] = $o.hair[$v][$c] } } }
  if (-not $anyColour.Count) { $anyColour[0] = $true }
  $facial = @{}
  if ($facialStyles -and $facialStyles.ContainsKey($key)) { foreach ($v in $facialStyles[$key].Keys) { $facial[$v] = $true } }
  elseif ($o.facialTex.ContainsKey("all")) { foreach ($v in $o.facialTex["all"].Keys) { $facial[$v] = $o.facialTex["all"][$v] } }
  $facial[0] = $true
  $facePlayer = @{}
  foreach ($s in $o.face.Keys) { foreach ($f in $o.face[$s].Keys) { if (-not $facePlayer.ContainsKey($f) -or $o.face[$s][$f]) { $facePlayer[$f] = $o.face[$s][$f] } } }

  [void]$sb.Append("`t[""$key""] = {`n")
  [void]$sb.Append("`t`tskin = $(Format-List $skins.Keys), npcSkin = $(Format-Npc $skins),`n")
  [void]$sb.Append("`t`tface = {")
  foreach ($s in ($o.face.Keys | Sort-Object { [int]$_ })) { if ($skins.ContainsKey($s)) { [void]$sb.Append(" [$s] = $(Format-List $o.face[$s].Keys),") } }
  [void]$sb.Append(" }, npcFace = $(Format-Npc $facePlayer),`n")
  [void]$sb.Append("`t`thairStyle = $(Format-List $styles.Keys), npcHairStyle = $(Format-Npc $stylePlayer),`n")
  [void]$sb.Append("`t`thairColour = {")
  foreach ($v in ($o.hair.Keys | Sort-Object { [int]$_ })) { if ($styles.ContainsKey($v)) { [void]$sb.Append(" [$v] = $(Format-List $o.hair[$v].Keys),") } }
  [void]$sb.Append(" }, anyHairColour = $(Format-List $anyColour.Keys), npcHairColour = $(Format-Npc $anyColour),`n")
  [void]$sb.Append("`t`tfacialHair = $(Format-List $facial.Keys),`n")
  [void]$sb.Append("`t},`n")
}
[void]$sb.Append("}`n")
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OptionsFile), $sb.ToString(), $utf8)

"Glows: {0} ({1}). Character options: {2}." -f $glows.Count, $glowNote, $optionNote

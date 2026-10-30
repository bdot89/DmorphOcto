param(
  [string]$GameDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path,
  [string]$OutFile = (Join-Path $PSScriptRoot "..\Data\ExtraWear.lua")
)
# Builds Data/ExtraWear.lua from the client's own spell tables: every look a
# spell keeps on a character while its aura lasts (Shadowform's dark body, Ice
# Barrier, Power Word: Shield, webs, cyclones...). DMorph's Extra wear tab puts
# them on through DmorphHelper_SetAura (v17): the game draws a spell's state
# look for the auras it finds in the unit's aura fields.
#
#   powershell -ExecutionPolicy Bypass -File tools\build_extrawear.ps1 [-GameDir C:\Games\OctoWoW]
#
# Spell.dbc field 115 is the spell's SpellVisual (checked on Shadowform 15473 ->
# 3619, Retail's ID too), SpellVisual field 4 its state kit, SpellVisualKit
# fields 3-13 its effect models (SpellVisualEffectName field 2 = file). One
# line per state kit (spells sharing a look count once), named after the
# plainest spell that has it. A table that doesn't read as expected writes an
# empty list with a warning.
# Runs on Windows PowerShell 5.1, no Python or Lua needed.

$ErrorActionPreference = "Stop"
Add-Type -Path (Join-Path $PSScriptRoot "MpqDbc.cs")

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

function Test-GameFile([string]$path) {
  if (-not $path) { return $false }
  $lower = $path.ToLowerInvariant()
  if ($lower.EndsWith(".mdx") -or $lower.EndsWith(".mdl")) { return $files.Has($path.Substring(0, $path.Length - 4) + ".m2") }
  return $files.Has($path)
}

function Get-BaseName([string]$path) {
  $name = ($path -split '[\\/]')[-1]
  $dot = $name.LastIndexOf('.')
  if ($dot -gt 0) { $name = $name.Substring(0, $dot) }
  return $name
}

# Names that are a developer's, not a player's.
$UGLY = '(?i)dnd|test|copy|visual|jeff|^tag:|zzold|qa |\(|\[|deprecated|unused|placeholder|^\s*$'

$spell = Read-Newest "DBFilesClient\Spell.dbc"
$vis = Read-Newest "DBFilesClient\SpellVisual.dbc"
$kit = Read-Newest "DBFilesClient\SpellVisualKit.dbc"
$eff = Read-Newest "DBFilesClient\SpellVisualEffectName.dbc"
$lines = New-Object System.Collections.ArrayList
$note = ""
$ok = $spell -and $vis -and $kit -and $eff -and $spell.Fields -gt 120 -and $vis.Fields -gt 4 -and $kit.Fields -gt 13 -and $eff.Fields -gt 2
if ($ok) {
  $visRow = @{}; for ($r = 0; $r -lt $vis.Count; $r++) { $visRow[$vis.Int($r, 0)] = $r }
  $kitRow = @{}; for ($r = 0; $r -lt $kit.Count; $r++) { $kitRow[$kit.Int($r, 0)] = $r }
  $effFile = @{}; for ($r = 0; $r -lt $eff.Count; $r++) { $effFile[$eff.Int($r, 0)] = $eff.TryStr($r, 2) }
  # The layout check: Shadowform (15473) must lead to a state kit with a model.
  $check = $false
  for ($r = 0; $r -lt $spell.Count; $r++) {
    if ($spell.Int($r, 0) -eq 15473) {
      $v = $spell.Int($r, 115)
      $check = ($spell.TryStr($r, 120) -eq "Shadowform") -and $visRow.ContainsKey($v) -and $kitRow.ContainsKey($vis.Int($visRow[$v], 4))
    }
  }
  if (-not $check) { $ok = $false }
}
if ($ok) {
  $looks = @{}
  for ($r = 0; $r -lt $spell.Count; $r++) {
    $v = $spell.Int($r, 115)
    if (-not $visRow.ContainsKey($v)) { continue }
    $s = $vis.Int($visRow[$v], 4)
    if ($s -le 0 -or -not $kitRow.ContainsKey($s)) { continue }
    $name = $spell.TryStr($r, 120)
    if (-not $looks.ContainsKey($s)) {
      $models = New-Object System.Collections.ArrayList
      foreach ($f in 3..13) {
        $e = $kit.Int($kitRow[$s], $f)
        if ($e -gt 0 -and $effFile.ContainsKey($e) -and (Test-GameFile $effFile[$e])) { [void]$models.Add((Get-BaseName $effFile[$e])) }
      }
      $looks[$s] = @{ spells = New-Object System.Collections.ArrayList; models = @($models | Select-Object -Unique) }
    }
    [void]$looks[$s].spells.Add([pscustomobject]@{ id = $spell.Int($r, 0); name = "$name" })
  }
  foreach ($s in $looks.Keys) {
    $all = @($looks[$s].spells)
    $nice = @($all | Where-Object { $_.name -notmatch $UGLY })
    # The name most of its spells share (Shadowform, not one boss's copy), then the shortest.
    $pool = @($(if ($nice.Count) { $nice } else { $all }))
    $count = @{}; foreach ($p in $pool) { $count[$p.name] = 1 + [int]$count[$p.name] }
    $pick = @($pool | Sort-Object { -$count[$_.name] }, { $_.name.Length }, id)[0]
    $others = @($nice | ForEach-Object { $_.name } | Where-Object { $_ -ne $pick.name } | Select-Object -Unique | Select-Object -First 4)
    $name = $pick.name -replace "`t", " "
    if (-not $name) { $name = "Look $s" }
    [void]$lines.Add([pscustomobject]@{ key = $name.ToLowerInvariant() + [char]1 + $pick.id.ToString("D8"); text =
      "$($pick.id)`t$name`t$(($others -join '; ') -replace "`t", ' ')`t$($looks[$s].models -join ', ')" })
  }
  $note = "{0} looks from {1} spells" -f $lines.Count, $spell.Count
} else {
  Write-Output "warning: the spell tables don't read as expected (Shadowform check failed), so Data/ExtraWear.lua is empty"
}

$arr = $lines.ToArray()
$keys = New-Object string[] $arr.Length
for ($i = 0; $i -lt $arr.Length; $i++) { $keys[$i] = $arr[$i].key }
[Array]::Sort($keys, $arr, [System.Collections.IComparer][StringComparer]::Ordinal)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("-- Generated by tools/build_extrawear.ps1 from the client's files. Do not edit.`n")
[void]$sb.Append("-- Every look a spell keeps on a character while its aura lasts, one per line:`n")
[void]$sb.Append("-- spellID<TAB>name<TAB>other spells with this look (; between)<TAB>effect models.`n")
[void]$sb.Append("DmorphOcto_ExtraWearData = [[`n")
foreach ($l in $arr) { [void]$sb.Append($l.text + "`n") }
[void]$sb.Append("]]`n")
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutFile), $sb.ToString(), $utf8)

# Data/ShotVisuals.lua (2.35.0): missiles for the Arrows list (DmorphHelper v18
# swaps your ranged attacks' visual; seen in game 30 Oct: 225 the fire wand
# bolt flies, 5 (bow) has no missile of its own). Every spell with a travel
# speed (Spell.dbc field 37: Fireball 133 = 24, Frostbolt 116 = 28) flies its
# visual (field 115): one line per visual, named after the plainest spell name
# most of its spells share.
$shots = New-Object System.Collections.ArrayList
if ($ok) {
  $byVisual = @{}
  for ($r = 0; $r -lt $spell.Count; $r++) {
    $speed = [BitConverter]::ToSingle([BitConverter]::GetBytes($spell.Int($r, 37)), 0)
    $v = $spell.Int($r, 115)
    if ($speed -le 0 -or $v -le 0 -or -not $visRow.ContainsKey($v)) { continue }
    $n = $spell.TryStr($r, 120)
    if (-not $n -or $n -match $UGLY) { continue }
    if (-not $byVisual.ContainsKey($v)) { $byVisual[$v] = @{} }
    $byVisual[$v][$n] = 1 + [int]$byVisual[$v][$n]
  }
  foreach ($v in $byVisual.Keys) {
    $names = $byVisual[$v]
    $best = @($names.Keys | Sort-Object { -$names[$_] }, { $_.Length })[0]
    [void]$shots.Add([pscustomobject]@{ key = $best.ToLowerInvariant() + [char]1 + $v.ToString("D6"); text = "$v`t$($best -replace "`t", ' ')" })
  }
}
$sarr = @($shots | Sort-Object key)
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("-- Generated by tools/build_extrawear.ps1 from the client's files. Do not edit.`n")
[void]$sb.Append("-- Every missile a ranged attack can fly: spellVisualID<TAB>missile model.`n")
[void]$sb.Append("DmorphOcto_ShotVisualData = [[`n")
foreach ($s in $sarr) { [void]$sb.Append($s.text + "`n") }
[void]$sb.Append("]]`n")
[IO.File]::WriteAllText([IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\Data\ShotVisuals.lua")), $sb.ToString(), $utf8)
"Shot visuals: $($sarr.Count) missiles"
"Extra wear: $note -> $OutFile"

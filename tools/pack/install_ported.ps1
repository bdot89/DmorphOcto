param(
  [string]$GameDir = "",
  [switch]$Remove,
  [string[]]$SearchRoots = @()   # tests: search these instead of every drive
)
# Installs a ported models pack made by DMorph's "Pack Ported.bat": this
# script sits in the pack, next to manifest.txt, the patch-?.MPQ files and
# Ported.lua. It checks every file against manifest.txt first, then copies
# the patches into <game>\Data and Ported.lua into its own small addon,
# Interface\AddOns\DMorph_Ported (DMorph loads it first: OptionalDeps), and
# installs DmorphHelper with DMorph's own installer. The list used to go in
# DmorphOcto\Data, where replacing the DmorphOcto folder to update DMorph
# deleted it (a friend's pack "had gone"); an old copy there is removed. A
# patch file of the same name that isn't a ported one (OctoWoW's own) is
# never replaced; ported patches from an older pack that this one doesn't
# have are removed.
#
# The easy way: close the game and double-click "Install Ported.bat" in the
# pack folder. Or:
#
#   powershell -ExecutionPolicy Bypass -File install_ported.ps1 [-GameDir C:\path\to\OctoWoW]
#   powershell -ExecutionPolicy Bypass -File install_ported.ps1 -Remove

$ErrorActionPreference = "Stop"
trap {
  Write-Host ""
  Write-Host ("Not done: " + $_.Exception.Message) -ForegroundColor Red
  exit 1
}
$pack = [IO.Path]::GetFullPath($PSScriptRoot)
$manifestPath = Join-Path $pack "manifest.txt"
# DMorph keeps this installer in tools\pack to put in packs: run from there, it has nothing to install.
if (-not $Remove -and -not (Test-Path $manifestPath) -and $pack -match '\\DmorphOcto\\tools(\\pack)?$') {
  throw "this is DMorph's own copy of the installer (it goes into packs), not a pack. Open the pack folder you downloaded (it has manifest.txt, Ported.lua and patch-?.mpq files in it) and double-click ""Install Ported.bat"" there. No pack? Ask whoever made it for the link (download the whole folder)."
}
Add-Type -Path (Join-Path $pack "MpqDbc.cs")
function Test-Ported([string]$path) {
  $m = $null
  try { $m = New-Object Mpq $path; return $m.Has("DmorphPort.txt") } catch { return $false } finally { if ($m) { $m.Close() } }
}
function Test-Game([string]$dir) {
  return $dir -and (Test-Path (Join-Path $dir "WoW.exe")) -and (Test-Path (Join-Path $dir "Data"))
}
# An answer typed in the window, trimmed; $null when there's no one to ask
# (Read-Host throws once its input has run out).
function Ask([string]$prompt) {
  try { return ([string](Read-Host $prompt)).Trim() } catch { return $null }
}

# The game folder: -GameDir, a folder above this pack, the running game, or
# a search of every fixed drive two folders deep (C:\WOW, D:\Games\OctoWoW...)
# and the Desktop, Documents and Downloads folders; games with DMorph in them
# come first. Several: picked by number. None (a friend's C:\WOW wasn't in
# the old list of usual places, and an empty answer stopped the install):
# asked for, and asked again for an answer that isn't a game folder.
if (-not $GameDir) {
  $found = New-Object System.Collections.ArrayList
  $dir = $pack
  while ($dir) {
    if (Test-Game $dir) { [void]$found.Add($dir); break }
    $parent = [IO.Path]::GetDirectoryName($dir)
    if ($parent -eq $dir) { $dir = $null } else { $dir = $parent }
  }
  if ($found.Count -eq 0) {
    foreach ($p in @(Get-Process -Name "WoW" -ErrorAction SilentlyContinue)) {
      try { $d = [IO.Path]::GetDirectoryName($p.Path); if ((Test-Game $d) -and -not $found.Contains($d)) { [void]$found.Add($d) } } catch { }
    }
    $roots = @($SearchRoots)
    if ($roots.Count -eq 0) {
      $roots = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq "Fixed" } | ForEach-Object { $_.RootDirectory.FullName })
      foreach ($special in @([Environment]::GetFolderPath("Desktop"), [Environment]::GetFolderPath("MyDocuments"), (Join-Path $env:USERPROFILE "Downloads"))) {
        if ($special -and (Test-Path $special)) { $roots += $special }
      }
    }
    $skip = @("Windows", '$Recycle.Bin', "System Volume Information", "ProgramData", "Recovery", "PerfLogs")
    foreach ($root in $roots) {
      $level = @(Get-Item -LiteralPath $root -ErrorAction SilentlyContinue)
      for ($depth = 0; $depth -le 2 -and $level.Count -gt 0; $depth++) {
        $next = New-Object System.Collections.ArrayList
        foreach ($d in $level) {
          if ((Test-Game $d.FullName) -and -not $found.Contains($d.FullName)) { [void]$found.Add($d.FullName); continue }
          if ($depth -lt 2) {
            foreach ($c in @(Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue)) {
              if ($skip -notcontains $c.Name) { [void]$next.Add($c) }
            }
          }
        }
        $level = @($next)
      }
    }
  }
  $withDmorph = @($found | Where-Object { Test-Path (Join-Path $_ "Interface\AddOns\DmorphOcto\DmorphOcto.toc") })
  if ($withDmorph.Count -gt 0) { $found = $withDmorph }
  if ($found.Count -eq 1) {
    $answer = Ask ("Install into {0}? (Y/n)" -f $found[0])
    if ($answer -match '^\s*(y|yes)?\s*$') { $GameDir = $found[0] }
  } elseif ($found.Count -gt 1) {
    "Game folders found:"
    for ($i = 0; $i -lt $found.Count; $i++) { "  {0}. {1}" -f ($i + 1), $found[$i] }
    $answer = Ask "Type the number of the one to install into (or press Enter to type another folder)"
    $n = 0
    if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $found.Count) { $GameDir = $found[$n - 1] }
  }
  for ($try = 1; -not $GameDir -and $try -le 3; $try++) {
    $answer = Ask "Type or paste your OctoWoW folder, the one with WoW.exe in it (for example C:\WOW), then press Enter"
    if ($answer -eq $null) { break }
    $answer = $answer.Trim('"').Trim()
    if (-not $answer) {
      Write-Host "Nothing was typed. Tip: you can also drag the game folder into this window, then press Enter." -ForegroundColor Yellow
    } elseif (Test-Game $answer) {
      $GameDir = $answer
    } else {
      Write-Host "$answer isn't the game folder: it needs WoW.exe and a Data folder in it. Try again." -ForegroundColor Yellow
    }
  }
  if (-not $GameDir) { throw "no game folder was given. Run this again and type the folder with WoW.exe in it (for example C:\WOW)." }
}
$GameDir = [IO.Path]::GetFullPath($GameDir)
if (-not (Test-Game $GameDir)) { throw "$GameDir isn't the game folder: it needs WoW.exe and a Data folder." }
"Game folder: $GameDir"
$dataDir = Join-Path $GameDir "Data"
$addon = Join-Path $GameDir "Interface\AddOns\DmorphOcto"
$listDir = Join-Path $GameDir "Interface\AddOns\DMorph_Ported"
$listTarget = Join-Path $listDir "Ported.lua"
$oldList = Join-Path $addon "Data\Ported.lua"

$running = @(Get-Process -Name "WoW" -ErrorAction SilentlyContinue | Where-Object {
  $path = $null
  try { $path = $_.Path } catch { }
  $path -and ([IO.Path]::GetDirectoryName($path) -ieq $GameDir)
})
if ($running.Count -gt 0) { throw "The game is running. Close it completely, then run this again." }

$installed = @(Get-ChildItem $dataDir -File | Where-Object { $_.Name -match '^patch-.\.mpq$' -and (Test-Ported $_.FullName) })

if ($Remove) {
  foreach ($f in $installed) {
    try { Remove-Item $f.FullName } catch { throw "Couldn't delete $($f.FullName). Close the game first, then run this again." }
    "Removed Data\$($f.Name)"
  }
  if (Test-Path (Join-Path $listDir "DMorph_Ported.toc")) { Remove-Item $listDir -Recurse; "Removed the DMorph_Ported addon (the pack's list)" }
  if (Test-Path $oldList) { Remove-Item $oldList; "Removed DMorph's Data\Ported.lua" }
  ""
  "The ported models are removed. DmorphHelper stays (DMorph uses it for glows, looks and size)."
  return
}

# The pack: manifest.txt lists every file with its size and SHA-256.
if (-not (Test-Path $manifestPath)) {
  throw "there's no pack in $pack (no manifest.txt). To install one, double-click ""Install Ported.bat"" inside the downloaded pack folder (download the whole folder). To make one (only on the PC that made the models), double-click ""Pack Ported.bat"" in the DmorphOcto folder."
}
$bundle = ""; $need = ""
$files = New-Object System.Collections.ArrayList
foreach ($line in [IO.File]::ReadAllLines($manifestPath)) {
  if ($line -match '^#' -or -not $line.Trim()) { continue }
  $f = $line.Split("`t")
  if ($f[0] -eq "bundle") { $bundle = $f[1] }
  elseif ($f[0] -eq "dmorph") { $need = $f[1] }
  elseif ($f.Count -eq 3) { [void]$files.Add(@{ Name = $f[0]; Size = [int64]$f[1]; Hash = $f[2] }) }
}
$patches = @($files | Where-Object { $_.Name -match '^patch-.\.mpq$' })
if ($patches.Count -eq 0 -or -not ($files | Where-Object { $_.Name -eq "Ported.lua" })) {
  throw "manifest.txt doesn't list any patches and Ported.lua. Download the whole pack folder again."
}
"Pack $bundle"

if (-not (Test-Path (Join-Path $addon "DmorphOcto.toc"))) {
  throw "DMorph isn't installed in $addon. Install DMorph first (github.com/bdot89/DmorphOcto), then run this again."
}
$have = ""
foreach ($line in [IO.File]::ReadAllLines((Join-Path $addon "DmorphOcto.toc"))) {
  if ($line -match '^##\s*Version:\s*(\S+)') { $have = $matches[1] }
}
if ($need -and $have) {
  $older = $false
  try { $older = [version]$have -lt [version]$need } catch { }
  if ($older) { throw "This pack needs DMorph $need or newer; you have $have. Update DMorph (download it again), then run this again." }
}

# Every file is checked before anything in the game folder changes.
"Checking the pack's files (a few minutes for big packs)..."
$bad = New-Object System.Collections.ArrayList
$i = 0
foreach ($f in $files) {
  $i++
  $path = Join-Path $pack $f.Name
  Write-Host ("[{0}/{1}] {2}" -f $i, $files.Count, $f.Name)
  if (-not (Test-Path $path)) { [void]$bad.Add("$($f.Name) is missing"); continue }
  if ((Get-Item $path).Length -ne $f.Size) { [void]$bad.Add("$($f.Name) has the wrong size (download not finished?)"); continue }
  if ((Get-FileHash $path -Algorithm SHA256).Hash -ne $f.Hash) { [void]$bad.Add("$($f.Name) is damaged") }
}
if ($bad.Count -gt 0) {
  foreach ($b in $bad) { Write-Host ("  " + $b) -ForegroundColor Red }
  throw "the pack isn't complete. Download those files again (nothing was installed)."
}

# What happens to each patch, worked out before anything is copied.
$copy = New-Object System.Collections.ArrayList
$space = [int64]0
foreach ($f in $patches) {
  $target = Join-Path $dataDir $f.Name
  if (Test-Path $target) {
    $item = Get-Item $target
    if (-not (Test-Ported $target)) {
      throw "$target is one of the game's own patches, and the pack has a file with the same name. Nothing was installed. Tell whoever sent the pack (the porting tool must use another letter)."
    }
    if ($item.Length -eq $f.Size -and (Get-FileHash $target -Algorithm SHA256).Hash -eq $f.Hash) { "Data\$($f.Name) is already installed."; continue }
    $space -= $item.Length
  }
  [void]$copy.Add($f)
  $space += $f.Size
}
$stale = @($installed | Where-Object { $n = $_.Name; -not ($patches | Where-Object { $_.Name -ieq $n }) })
foreach ($s in $stale) { $space -= $s.Length }
$drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($dataDir))
if ($drive.AvailableFreeSpace -lt $space + 50MB) {
  throw ("the game's drive needs {0:N1} GB more free space (it has {1:N1} GB). Nothing was installed." -f ($space / 1GB), ($drive.AvailableFreeSpace / 1GB))
}

# Ported patches from an older pack would mix with this one's list.
foreach ($s in $stale) {
  try { Remove-Item $s.FullName } catch { throw "Couldn't delete the old $($s.FullName). Close the game first, then run this again." }
  "Removed the old Data\$($s.Name) (not in this pack)."
}
foreach ($f in $copy) {
  $target = Join-Path $dataDir $f.Name
  Write-Host ("Copying {0} ({1:N0} MB)..." -f $f.Name, ($f.Size / 1MB))
  try { Copy-Item (Join-Path $pack $f.Name) $target -Force } catch { throw "Couldn't copy $($f.Name) into $dataDir. Close the game, then run this again." }
}
# The list goes in its own addon, so updating DMorph (replacing its folder)
# can't delete it; a copy in DmorphOcto\Data would load after it and win.
if (-not (Test-Path $listDir)) { New-Item -ItemType Directory $listDir | Out-Null }
Copy-Item (Join-Path $pack "Ported.lua") $listTarget -Force
$toc = @(
  "## Interface: 11200",
  "## Title: DMorph |cffb46bffported pack|r",
  "## Notes: The list of later-expansion looks in your ported pack (its patch files are in the game's Data folder). Put in by the pack's Install Ported.bat; DMorph updates don't touch it.",
  "## Author: bdot89",
  "## Version: $bundle",
  "Ported.lua"
)
# How DMorph's previews frame each ported model (newer packs have it).
$framesTarget = Join-Path $listDir "PortedFrames.lua"
if ($files | Where-Object { $_.Name -eq "PortedFrames.lua" }) {
  Copy-Item (Join-Path $pack "PortedFrames.lua") $framesTarget -Force
  $toc += "PortedFrames.lua"
} elseif (Test-Path $framesTarget) {
  Remove-Item $framesTarget
}
[IO.File]::WriteAllLines((Join-Path $listDir "DMorph_Ported.toc"), [string[]]$toc, (New-Object System.Text.UTF8Encoding $false))
if (Test-Path $oldList) { Remove-Item $oldList }
"Put Ported.lua in Interface\AddOns\DMorph_Ported (DMorph updates don't touch it)."

# DmorphHelper shows the ported weapons and armour; DMorph's own installer
# puts it in (or says it's already the newest).
""
$helper = Join-Path $addon "tools\install_helper.ps1"
$helperOk = $false
if (Test-Path $helper) {
  & $helper -GameDir $GameDir
  $helperOk = ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null)
}
if (-not $helperOk) {
  Write-Host "DmorphHelper isn't installed: double-click ""Install DmorphHelper.bat"" in the DmorphOcto folder (ported weapons and armour need it)." -ForegroundColor Yellow
}
""
"The ported models are installed (pack $bundle). Start the game from OctoLauncher."
"Friends with the same pack see each other's ported looks. To take it out again, double-click ""Remove Ported.bat"" in the pack folder."

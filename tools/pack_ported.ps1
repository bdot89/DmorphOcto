param(
  [string]$GameDir = "",
  [string]$Out = ""
)
# Packs the model porting tool's output so friends can install it: every
# Data\patch-?.MPQ with the tool's DmorphPort.txt marker inside, this addon's
# Data\Ported.lua, the installer (Install/Remove Ported.bat + install_ported.ps1),
# MpqDbc.cs for it, and manifest.txt (each file's size and SHA-256). Files
# are copied as they are: MPQs are already compressed.
#
# The easy way: double-click "Pack Ported.bat" in the DmorphOcto folder. Or:
#
#   powershell -ExecutionPolicy Bypass -File tools\pack_ported.ps1 [-Out D:\DmorphPorted] [-GameDir C:\path\to\OctoWoW]
#
# The pack goes to Desktop\DmorphPorted unless -Out says otherwise. Upload
# that folder (Google Drive, OneDrive, MEGA); the friend downloads it and
# double-clicks "Install Ported.bat" in it. Pack again after every porting
# run: a friend needs exactly the same patches and Ported.lua.

$ErrorActionPreference = "Stop"
trap {
  Write-Host ""
  Write-Host ("Not done: " + $_.Exception.Message) -ForegroundColor Red
  exit 1
}
$addon = [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot, ".."))

# The game folder: the nearest folder above this one with WoW.exe in it.
if (-not $GameDir) {
  $dir = $addon
  while ($dir -and -not (Test-Path (Join-Path $dir "WoW.exe"))) {
    $parent = [IO.Path]::GetDirectoryName($dir)
    if ($parent -eq $dir) { $dir = $null } else { $dir = $parent }
  }
  if (-not $dir) {
    throw "Couldn't find the game folder (the one with WoW.exe) above $addon. Run this with -GameDir C:\path\to\OctoWoW."
  }
  $GameDir = $dir
}
"Game folder: $GameDir"
$dataDir = Join-Path $GameDir "Data"
if (-not (Test-Path $dataDir)) { throw "There's no Data folder in $GameDir." }

Add-Type -Path (Join-Path $PSScriptRoot "MpqDbc.cs")
function Test-Ported([string]$path) {
  $m = $null
  try { $m = New-Object Mpq $path; return $m.Has("DmorphPort.txt") } catch { return $false } finally { if ($m) { $m.Close() } }
}

$patches = @(Get-ChildItem $dataDir -File | Where-Object { $_.Name -match '^patch-.\.mpq$' -and (Test-Ported $_.FullName) } | Sort-Object Name)
# Packing is for the PC that made the models; a friend who was sent a pack installs it instead.
$sentAPack = "Pack Ported.bat is only for the PC that made the ported models. Were you sent a pack? Then open the pack folder you downloaded and double-click ""Install Ported.bat"" in it instead."
if ($patches.Count -eq 0) {
  throw "No ported patches in $dataDir (patch-?.MPQ files with DmorphPort.txt inside). $sentAPack"
}
# The list: the DMorph_Ported addon (where packs install it), else DMorph's Data folder.
$list = Join-Path ([IO.Path]::GetDirectoryName($addon)) "DMorph_Ported\Ported.lua"
if (-not (Test-Path $list)) { $list = Join-Path $addon "Data\Ported.lua" }
if (-not (Test-Path $list)) { throw "Ported.lua is missing (Interface\AddOns\DMorph_Ported or DmorphOcto\Data). $sentAPack" }
# How the previews frame each ported model (tools\build_frames.ps1 -Ported), if made.
$frames = Join-Path ([IO.Path]::GetDirectoryName($list)) "PortedFrames.lua"
$extra = @()
if (Test-Path $frames) { $extra = @($frames) }

$version = ""
foreach ($line in [IO.File]::ReadAllLines((Join-Path $addon "DmorphOcto.toc"))) {
  if ($line -match '^##\s*Version:\s*(\S+)') { $version = $matches[1] }
}

if (-not $Out) {
  $desktop = [Environment]::GetFolderPath("Desktop")
  if (-not $desktop) { $desktop = $HOME }
  $Out = Join-Path $desktop "DmorphPorted"
}
$Out = [IO.Path]::GetFullPath($Out)
# Only a folder this script made before (it has manifest.txt) is emptied.
if (Test-Path $Out) {
  $old = @(Get-ChildItem $Out -Force)
  if ($old.Count -gt 0) {
    if (-not (Test-Path (Join-Path $Out "manifest.txt"))) {
      throw "$Out already exists and isn't an earlier pack. Empty it, or pick another folder with -Out."
    }
    $old | Remove-Item -Recurse -Force
  }
} else {
  [void](New-Item -ItemType Directory $Out)
}

$total = 0
foreach ($p in $patches) { $total += $p.Length }
$total += (Get-Item $list).Length
foreach ($e in $extra) { $total += (Get-Item $e).Length }
$drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($Out))
if ($drive.AvailableFreeSpace -lt $total + 50MB) {
  throw ("{0} needs {1:N1} GB free, it has {2:N1} GB. Free some space or pick another drive with -Out." -f $Out, ($total / 1GB), ($drive.AvailableFreeSpace / 1GB))
}

$entries = New-Object System.Collections.ArrayList
$files = @($patches | ForEach-Object { $_.FullName }) + @($list) + $extra
$i = 0
foreach ($src in $files) {
  $i++
  $name = [IO.Path]::GetFileName($src)
  Write-Host ("[{0}/{1}] {2} ({3:N0} MB)" -f $i, $files.Count, $name, ((Get-Item $src).Length / 1MB))
  $dest = Join-Path $Out $name
  Copy-Item $src $dest
  # The copy is hashed: that's what the friend gets.
  $hash = (Get-FileHash $dest -Algorithm SHA256).Hash
  [void]$entries.Add(("{0}`t{1}`t{2}" -f $name, (Get-Item $dest).Length, $hash))
}

# One ID for the whole pack, from every file's name and hash.
$sha = [Security.Cryptography.SHA256]::Create()
$bundle = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($entries -join "`n")))) -replace '-', '').Substring(0, 12)

$manifest = @(
  "# DMorph ported models pack. Install it with ""Install Ported.bat"" in this folder.",
  "# Every file below must be here, unchanged. Don't mix files from different packs.",
  "bundle`t$bundle",
  "dmorph`t$version",
  ("made`t" + (Get-Date -Format "yyyy-MM-dd HH:mm"))
) + $entries
[IO.File]::WriteAllLines((Join-Path $Out "manifest.txt"), [string[]]$manifest)
Copy-Item (Join-Path $PSScriptRoot "pack\install_ported.ps1") $Out
Copy-Item (Join-Path $PSScriptRoot "MpqDbc.cs") $Out
# The pack's double-click files live in tools\pack, so nobody runs them from DMorph's own folder.
Copy-Item (Join-Path $PSScriptRoot "pack\Install Ported.bat") $Out
Copy-Item (Join-Path $PSScriptRoot "pack\Remove Ported.bat") $Out

""
"Packed {0} patches + Ported.lua, {1:N1} GB, into:" -f $patches.Count, ($total / 1GB)
"  $Out"
"Pack $bundle (DMorph $version)."
""
"Upload that whole folder (Google Drive, OneDrive or MEGA) and send your friend the link."
"They need DMorph $version or newer, then double-click ""Install Ported.bat"" in the folder."

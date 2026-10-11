param(
  [string]$GameDir = "",
  [switch]$Remove
)
# Puts DmorphHelper.dll (helper\ in this folder) into the game, for weapon
# glows and real skin, face and hair changes: copies it next to the game's
# exe and adds it to dlls.txt right after VanillaHelpers.dll. VanillaFixes,
# which OctoLauncher starts the game with, loads every DLL listed there, and
# OctoLauncher keeps lines it didn't write. dlls.txt is backed up first, to
# dlls.txt.dmorph-backup.
#
# The easy way: close the game and double-click "Install DmorphHelper.bat"
# (or "Remove DmorphHelper.bat") in the DmorphOcto folder. Or:
#
#   powershell -ExecutionPolicy Bypass -File tools\install_helper.ps1
#   powershell -ExecutionPolicy Bypass -File tools\install_helper.ps1 -Remove
#
# The game folder is found by going up from this folder to the one with
# WoW.exe (normally <game>\Interface\AddOns\DmorphOcto\tools); elsewhere, add
# -GameDir C:\path\to\OctoWoW. Run it again after a DMorph update: it only
# copies the DLL when it changed. If the game doesn't start afterwards, run it
# with -Remove (or delete the DmorphHelper.dll line from dlls.txt).

$ErrorActionPreference = "Stop"
# Problems are shown as one plain line (the .bat keeps the window open).
trap {
  Write-Host ""
  Write-Host ("Not done: " + $_.Exception.Message) -ForegroundColor Red
  exit 1
}
$name = "DmorphHelper.dll"
$source = [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot, "..", "helper", $name))

# The game folder: the nearest folder above this one with WoW.exe in it.
if (-not $GameDir) {
  $dir = [IO.Path]::GetFullPath($PSScriptRoot)
  while ($dir -and -not (Test-Path (Join-Path $dir "WoW.exe"))) {
    $parent = [IO.Path]::GetDirectoryName($dir)
    if ($parent -eq $dir) { $dir = $null } else { $dir = $parent }
  }
  if (-not $dir) {
    throw "Couldn't find the game folder (the one with WoW.exe) above $PSScriptRoot. Put DmorphOcto in <game>\Interface\AddOns, or run this with -GameDir C:\path\to\OctoWoW."
  }
  $GameDir = $dir
}
$target = Join-Path $GameDir $name
$list = Join-Path $GameDir "dlls.txt"
"Game folder: $GameDir"

# Only this game folder's WoW.exe matters. Windows often hides a running
# game's path; then a DLL the game has in use simply can't be replaced (that
# is reported below), and dlls.txt is only read when the game starts.
$running = @(Get-Process -Name "WoW" -ErrorAction SilentlyContinue | Where-Object {
  $path = $null
  try { $path = $_.Path } catch { }
  $path -and ([IO.Path]::GetDirectoryName($path) -ieq $GameDir)
})
if ($running.Count -gt 0) {
  throw "The game is running. Close it completely, then run this again."
}
if (-not (Test-Path $list)) {
  throw "There's no dlls.txt in $GameDir. Start the game once from OctoLauncher with the vanillaHelpers mod ticked (that makes it), close it, then run this again."
}
$lines = @([IO.File]::ReadAllLines($list) | Where-Object { $_.Trim() -ine $name })
$backup = "$list.dmorph-backup"
if (-not (Test-Path $backup)) { Copy-Item $list $backup }

if ($Remove) {
  [IO.File]::WriteAllLines($list, [string[]]$lines)
  if (Test-Path $target) {
    try { Remove-Item $target } catch { throw "Couldn't delete $target. Close the game first, then run this again." }
  }
  "DmorphHelper is removed: it's out of dlls.txt and the game folder."
  return
}

if (-not (Test-Path $source)) { throw "$source is missing. Get the whole DmorphOcto folder (download it again) and try again." }
$same = (Test-Path $target) -and ((Get-FileHash $source).Hash -eq (Get-FileHash $target).Hash)
if ($same) {
  "$name in the game folder is already the newest one."
} else {
  try { Copy-Item $source $target -Force } catch { throw "Couldn't copy $name into $GameDir. Close the game first, then run this again." }
  # A DLL from a downloaded zip carries Windows' "from the internet" mark.
  try { Unblock-File $target } catch { }
  "Copied $name into the game folder."
}

$out = New-Object System.Collections.ArrayList
$placed = $false
foreach ($line in $lines) {
  [void]$out.Add($line)
  if (-not $placed -and $line.Trim() -ieq "VanillaHelpers.dll") { [void]$out.Add($name); $placed = $true }
}
if (-not $placed) {
  [void]$out.Add($name)
  Write-Output "warning: VanillaHelpers.dll isn't in dlls.txt. DmorphHelper needs it: tick the vanillaHelpers mod in OctoLauncher."
}
[IO.File]::WriteAllLines($list, [string[]]$out.ToArray())
"Added $name to dlls.txt (after VanillaHelpers.dll)."
""
"DmorphHelper is installed. Start the game from OctoLauncher as usual (if it's open, close it and start it again)."
"In game, the DMorph window's Setup button shows whether it's running (or type /dmorph check)."
"If the game won't start, double-click ""Remove DmorphHelper.bat""."

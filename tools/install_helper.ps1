param(
  [string]$GameDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path,
  [switch]$Remove
)
# Puts DmorphHelper.dll (helper\ in this folder) into the game, for weapon
# glows and real skin, face and hair changes: copies it next to the game's
# exe and adds it to dlls.txt right after VanillaHelpers.dll. VanillaFixes,
# which OctoLauncher starts the game with, loads every DLL listed there, and
# OctoLauncher keeps lines it didn't write. dlls.txt is backed up first, to
# dlls.txt.dmorph-backup.
#
#   powershell -ExecutionPolicy Bypass -File tools\install_helper.ps1
#   powershell -ExecutionPolicy Bypass -File tools\install_helper.ps1 -Remove
#
# Run it with the game closed. It expects to sit in
# <game>\Interface\AddOns\DmorphOcto\tools; elsewhere, add -GameDir
# C:\path\to\OctoWoW. If the game doesn't start afterwards, run it again with
# -Remove (or delete the DmorphHelper.dll line from dlls.txt).

$ErrorActionPreference = "Stop"
$name = "DmorphHelper.dll"
$source = [IO.Path]::Combine($PSScriptRoot, "..", "helper", $name)
$target = Join-Path $GameDir $name
$list = Join-Path $GameDir "dlls.txt"

if (-not (Test-Path $list)) {
  throw "There's no dlls.txt in $GameDir. Is that the game folder? (pass -GameDir C:\path\to\OctoWoW) VanillaHelpers is loaded from dlls.txt, so it must be there."
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

if (-not (Test-Path $source)) { throw "$source is missing. Get the whole DmorphOcto folder (git pull) and try again." }
try { Copy-Item $source $target -Force } catch { throw "Couldn't copy $name into $GameDir. Close the game first, then run this again." }

$out = New-Object System.Collections.ArrayList
$placed = $false
foreach ($line in $lines) {
  [void]$out.Add($line)
  if (-not $placed -and $line.Trim() -ieq "VanillaHelpers.dll") { [void]$out.Add($name); $placed = $true }
}
if (-not $placed) {
  [void]$out.Add($name)
  Write-Output "warning: VanillaHelpers.dll isn't in dlls.txt. DmorphHelper needs it: enable the vanillaHelpers mod in OctoLauncher."
}
[IO.File]::WriteAllLines($list, [string[]]$out.ToArray())
"DmorphHelper is installed: $target, and in dlls.txt."
"Start the game as usual. In game, /dmorph status should say ""DmorphHelper v1 is loaded""."
"If the game won't start, run this again with -Remove."

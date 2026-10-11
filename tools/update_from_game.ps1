# Reads the game's own files and brings the addon's lists in line with them:
# every model and item set in the client, the models and items that can't
# show in it hidden (Data/HiddenModels.lua, Data/HiddenItems.lua), and the
# weapon glows and skin, face and hair choices (Data/Glows.lua,
# Data/CharOptions.lua; they need DmorphHelper.dll in game). Run it with
# the game closed, from the addon folder, after installing or updating:
#
#   powershell -ExecutionPolicy Bypass -File tools\update_from_game.ps1
#
# It expects to sit in <game>\Interface\AddOns\DmorphOcto\tools; elsewhere,
# add -GameDir C:\path\to\OctoWoW. Then /reload in game.
param(
  [string]$GameDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
)
$ErrorActionPreference = "Stop"
"Reading the game files in $GameDir ..."
& (Join-Path $PSScriptRoot "build_models.ps1") -GameDir $GameDir
& (Join-Path $PSScriptRoot "build_items.ps1") -GameDir $GameDir
& (Join-Path $PSScriptRoot "build_options.ps1") -GameDir $GameDir
"Done. /reload in game to see the new lists."

@echo off
title DMorph: remove DmorphHelper
echo Removing DmorphHelper from the game folder and dlls.txt...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install_helper.ps1" -Remove
echo.
pause

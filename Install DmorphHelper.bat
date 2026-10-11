@echo off
title DMorph: install DmorphHelper
echo Installing DmorphHelper (weapon glows and real skin, face and hair for DMorph)...
echo Close the game first if it is running.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install_helper.ps1"
echo.
pause

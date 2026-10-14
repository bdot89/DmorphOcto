@echo off
title DMorph: pack ported models
echo Packing the ported models (patches + Ported.lua) to send to friends...
echo This is only for the PC that made the models. Were you sent a pack? Close this,
echo open the pack folder you downloaded and double-click "Install Ported.bat" in it.
echo This copies a few GB: it can take a few minutes.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\pack_ported.ps1" %*
echo.
pause

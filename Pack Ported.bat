@echo off
title DMorph: pack ported models
echo Packing the ported models (patches + Ported.lua) to send to friends...
echo This copies a few GB: it can take a few minutes.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\pack_ported.ps1" %*
echo.
pause

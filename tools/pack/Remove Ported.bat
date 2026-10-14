@echo off
title DMorph: remove ported models
echo Removing the ported models (patches and Ported.lua) from OctoWoW...
echo Close the game first if it is running.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_ported.ps1" -Remove %*
echo.
pause

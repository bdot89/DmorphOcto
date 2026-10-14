@echo off
title DMorph: install ported models
echo Installing the ported models in this folder into OctoWoW...
echo Close the game first if it is running.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_ported.ps1" %*
echo.
pause

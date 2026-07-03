@echo off
chcp 65001 >nul
title Hardware Test Kit
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Testar-Equipamento.ps1" %*
pause

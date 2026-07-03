@echo off
chcp 65001 >nul
title Teste de Teclado - Notebook
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  ". .\lib\Core.ps1; . .\lib\Tests-Keyboard.ps1; Invoke-KeyboardTest; Read-Host 'Pressione Enter para sair'"
pause

@echo off
setlocal
title Communication Lab - Qwen3.5-9B
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_communication_lab_qwen.ps1" %*
set "launch_result=%errorlevel%"
if not "%launch_result%"=="0" pause
exit /b %launch_result%

@echo off
setlocal
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "__SCRIPT_DIR__\claudio.ps1" %*
endlocal

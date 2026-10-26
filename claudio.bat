@echo off
setlocal
rem Pass the raw arguments via the environment so they are parsed only once, by podman.
rem Unquoted on purpose: quoting would shift the quote state of %* and expose & | < >.
set CLAUDIO_ARGS=%*
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "__SCRIPT_DIR__\claudio.ps1"
endlocal

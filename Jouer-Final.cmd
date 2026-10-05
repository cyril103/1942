@echo off
setlocal
if exist "%~dp0dist\PacificStrike\PacificStrike.exe" (
    start "Pacific Strike" "%~dp0dist\PacificStrike\PacificStrike.exe"
) else (
    call "%~dp0Jouer.cmd"
)

@echo off
setlocal
set "GODOT_EXE=D:\godot\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT_EXE%" (
    echo Godot 4.7.2 est introuvable. Ouvrez game\project.godot dans Godot 4.7.2.
    pause
    exit /b 1
)
start "Pacific Strike - Campagne 1942" "%GODOT_EXE%" --path "%~dp0game"

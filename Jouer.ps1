$ErrorActionPreference = 'Stop'
$gameDirectory = Join-Path $PSScriptRoot 'game'
$godotBinary = 'D:/godot/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64.exe'
if (-not (Test-Path -LiteralPath $godotBinary)) {
    throw 'Godot 4.7.2 est introuvable. Ouvrez game/project.godot dans Godot 4.7.2 puis appuyez sur F5.'
}
& $godotBinary --path $gameDirectory

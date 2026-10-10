param(
    [string]$Script = 'res://tests/test_ocean_phase_contract.gd',
    [string[]]$TestArguments = @(),
    [switch]$Rendered,
    [string]$GodotBinary = 'D:/godot/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
# Keep test preferences, saves and temporary exports away from the player's data.
$runtime = Join-Path $PSScriptRoot 'tools/runtime-coast'
foreach ($folder in @('roaming','local','temp')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $runtime $folder) | Out-Null
}
$env:APPDATA = Join-Path $runtime 'roaming'
$env:LOCALAPPDATA = Join-Path $runtime 'local'
$env:TEMP = Join-Path $runtime 'temp'
$env:TMP = $env:TEMP
$arguments = @('--audio-driver','Dummy','--path',(Join-Path $PSScriptRoot 'game'),'--script',$Script)
if ($Rendered) {
    $arguments += @('--windowed','--resolution','1920x1080')
} else {
    $arguments += '--headless'
}
if ($TestArguments.Count) { $arguments += @('--') + $TestArguments }
& $GodotBinary @arguments
exit $LASTEXITCODE

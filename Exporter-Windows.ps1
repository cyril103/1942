param([string]$GodotBinary = 'D:/godot/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$projectPath = Join-Path $PSScriptRoot 'game'
$outputDirectory = Join-Path $PSScriptRoot 'dist/PacificStrike'
$templatePath = Join-Path $PSScriptRoot 'tools/godot-export/templates/windows_release_x86_64.exe'
if (-not (Test-Path -LiteralPath $GodotBinary)) { throw 'Godot 4.7.2 introuvable : renseignez -GodotBinary.' }
if (-not (Test-Path -LiteralPath $templatePath)) { throw 'Extraire les templates Windows x64 officiels 4.7.2 dans tools/godot-export/templates.' }
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
& $GodotBinary --headless --path $projectPath --export-release 'Windows Desktop' (Join-Path $outputDirectory 'PacificStrike.exe')
if ($LASTEXITCODE -ne 0) { throw 'Export Godot en échec.' }
$licenseDirectory = Join-Path $outputDirectory 'Licences'
New-Item -ItemType Directory -Force -Path $licenseDirectory | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'docs/licenses/Godot-LICENSE.txt'),(Join-Path $PSScriptRoot 'docs/licenses/Godot-COPYRIGHT.txt') -Destination $licenseDirectory
Get-ChildItem -LiteralPath (Join-Path $projectPath 'assets/ui/fonts') -Filter '*.txt' | Copy-Item -Destination $licenseDirectory
Copy-Item -LiteralPath (Join-Path $projectPath 'assets/audio/engine/CREDITS.md') -Destination (Join-Path $licenseDirectory 'Moteur-avion.md')
Copy-Item -LiteralPath (Join-Path $projectPath 'assets/audio/weapons/CREDITS.md') -Destination (Join-Path $licenseDirectory 'Tirs-explosions.md')
Copy-Item -LiteralPath (Join-Path $projectPath 'assets/campaign/music/CREDITS.txt') -Destination (Join-Path $licenseDirectory 'Musique.txt')
Copy-Item -LiteralPath (Join-Path $projectPath 'assets/campaign/music/Juhani-INFO.txt') -Destination $licenseDirectory
Copy-Item -LiteralPath (Join-Path $projectPath 'assets/environment/raid-v2/CREDITS.md') -Destination (Join-Path $licenseDirectory 'Terrains-terrestres.md')
Copy-Item -LiteralPath (Join-Path $projectPath 'assets/ground-forces/CREDITS.md') -Destination (Join-Path $licenseDirectory 'Installations-militaires.md')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'docs/manuel-joueur.txt') -Destination (Join-Path $outputDirectory 'LISEZ-MOI.txt')
Compress-Archive -LiteralPath $outputDirectory -DestinationPath (Join-Path $PSScriptRoot 'dist/PacificStrike-Windows-x64.zip') -Force
Get-FileHash -LiteralPath (Join-Path $outputDirectory 'PacificStrike.exe') -Algorithm SHA256 | Format-List

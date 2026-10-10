param([string]$GodotBinary = 'D:/godot/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$projectPath = Join-Path $PSScriptRoot 'game'
$outputDirectory = Join-Path $PSScriptRoot 'dist/PacificStrike'
$templatePath = Join-Path $PSScriptRoot 'tools/godot-export/templates/windows_release_x86_64.exe'
if (-not (Test-Path -LiteralPath $GodotBinary)) { throw 'Godot 4.7.2 introuvable : renseignez -GodotBinary.' }
if (-not (Test-Path -LiteralPath $templatePath)) { throw 'Extraire les templates Windows x64 officiels 4.7.2 dans tools/godot-export/templates.' }
$presetText = Get-Content -LiteralPath (Join-Path $projectPath 'export_presets.cfg') -Raw
function Read-ExportProperty([string]$property) {
    $match = [regex]::Match($presetText, '(?m)^' + [regex]::Escape($property) + '="([^"]+)"\r?$')
    if (-not $match.Success) { throw ('Metadonnee manquante dans le preset : ' + $property) }
    return $match.Groups[1].Value
}
$expectedMetadata = @{
    FileVersion = Read-ExportProperty 'application/file_version'
    ProductVersion = Read-ExportProperty 'application/product_version'
    ProductName = Read-ExportProperty 'application/product_name'
    FileDescription = Read-ExportProperty 'application/file_description'
}
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$exportOutput = @(& $GodotBinary --headless --audio-driver Dummy --path $projectPath --export-release 'Windows Desktop' (Join-Path $outputDirectory 'PacificStrike.exe') 2>&1)
$exportExitCode = $LASTEXITCODE
$exportOutput | ForEach-Object { Write-Output $_ }
if ($exportExitCode -ne 0 -or ($exportOutput -match '(^|\s)(SCRIPT ERROR:|ERROR:)')) { throw 'Export Godot en échec : consulter les diagnostics moteur avant de distribuer le jeu.' }
$executable = Join-Path $outputDirectory 'PacificStrike.exe'
$metadata = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($executable)
foreach ($property in $expectedMetadata.Keys) {
    if ($metadata.$property -ne $expectedMetadata[$property]) {
        throw ('Metadonnee Windows incorrecte : ' + $property + ' = ' + $metadata.$property + ' ; attendu : ' + $expectedMetadata[$property])
    }
}
$licenseDirectory = Join-Path $outputDirectory 'Licences'
New-Item -ItemType Directory -Force -Path $licenseDirectory | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'docs/licenses/Godot-LICENSE.txt'),(Join-Path $PSScriptRoot 'docs/licenses/Godot-COPYRIGHT.txt') -Destination $licenseDirectory
Get-ChildItem -LiteralPath (Join-Path $projectPath 'assets/ui/fonts') -Filter '*.txt' | Copy-Item -Destination $licenseDirectory
Copy-Item -LiteralPath (Join-Path $projectPath 'assets/audio/engine/CREDITS.md') -Destination (Join-Path $licenseDirectory 'Moteur-avion.md')
Copy-Item -LiteralPath (Join-Path $projectPath 'assets/audio/weapons/CREDITS.md') -Destination (Join-Path $licenseDirectory 'Tirs-explosions.md')
Copy-Item -LiteralPath (Join-Path $projectPath 'assets/campaign/music/CREDITS.txt') -Destination (Join-Path $licenseDirectory 'Musique.txt')
Copy-Item -LiteralPath (Join-Path $projectPath 'assets/campaign/music/Juhani-INFO.txt') -Destination $licenseDirectory
Copy-Item -LiteralPath (Join-Path $projectPath 'assets/environment/raid-v2/CREDITS.md') -Destination (Join-Path $licenseDirectory 'Terrains-terrestres.md')
Copy-Item -LiteralPath (Join-Path $projectPath 'assets/environment/raid-v3/CREDITS.txt') -Destination (Join-Path $licenseDirectory 'Terrains-volcaniques-arctiques.txt')
Copy-Item -LiteralPath (Join-Path $projectPath 'assets/environment/raid-v4/CREDITS.txt') -Destination (Join-Path $licenseDirectory 'Paysages-1.10.txt')
Copy-Item -LiteralPath (Join-Path $projectPath 'assets/ground-forces/CREDITS.md') -Destination (Join-Path $licenseDirectory 'Installations-militaires.md')
Copy-Item -LiteralPath (Join-Path $projectPath 'assets/ground-forces/MOBILE-AA-CREDITS.md') -Destination (Join-Path $licenseDirectory 'DCA-mobile.md')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'docs/manuel-joueur.txt') -Destination (Join-Path $outputDirectory 'LISEZ-MOI.txt')
Compress-Archive -LiteralPath $outputDirectory -DestinationPath (Join-Path $PSScriptRoot 'dist/PacificStrike-Windows-x64.zip') -Force
Get-FileHash -LiteralPath $executable -Algorithm SHA256 | Format-List
$metadata | Select-Object ProductName,FileDescription,FileVersion,ProductVersion | Format-List

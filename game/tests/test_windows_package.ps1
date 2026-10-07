param(
    [string]$PackageZip = (Join-Path $PSScriptRoot '../../dist/PacificStrike-Windows-x64.zip'),
    [string]$BuiltExecutable = (Join-Path $PSScriptRoot '../../dist/PacificStrike/PacificStrike.exe'),
    [string]$ExpectedVersion = '1.7.0.0',
    [switch]$SkipRuntime
)
$ErrorActionPreference = 'Stop'
$checks = 0
function Check-Package([bool]$condition, [string]$message) {
    $script:checks += 1
    if (-not $condition) { throw $message }
}
$scratchBase = Join-Path ([System.IO.Path]::GetTempPath()) 'PacificStrike-package-validation'
$scratch = Join-Path $scratchBase ('windows-package-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
Expand-Archive -LiteralPath $PackageZip -DestinationPath $scratch
$executables = @(Get-ChildItem -LiteralPath $scratch -Recurse -File -Filter 'PacificStrike.exe')
Check-Package ($executables.Count -eq 1) 'Le ZIP doit contenir un seul executable PacificStrike.exe.'
$exe = $executables[0].FullName
$directory = $executables[0].DirectoryName
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
Check-Package ($hash -eq (Get-FileHash -LiteralPath $BuiltExecutable -Algorithm SHA256).Hash) 'Executable extrait different de celui controle avant compression.'
$metadata = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
Check-Package ($metadata.ProductName -eq 'Pacific Strike') 'Nom produit Windows incorrect.'
Check-Package ($metadata.FileDescription -eq 'Pacific Strike - Campagne 1942') 'Description Windows incorrecte.'
Check-Package ($metadata.FileVersion -eq $ExpectedVersion) 'Version fichier Windows incorrecte.'
Check-Package ($metadata.ProductVersion -eq $ExpectedVersion) 'Version produit Windows incorrecte.'
Check-Package (Test-Path -LiteralPath (Join-Path $directory 'LISEZ-MOI.txt')) 'Manuel absent du ZIP.'
$requiredCredits = @('Godot-LICENSE.txt','Godot-COPYRIGHT.txt','Musique.txt','Juhani-INFO.txt','Moteur-avion.md','Tirs-explosions.md','Terrains-terrestres.md','Installations-militaires.md','barlowcondensed-OFL.txt','blackopsone-OFL.txt','DSEG-LICENSE.txt')
foreach ($credit in $requiredCredits) {
    Check-Package (Test-Path -LiteralPath (Join-Path $directory ('Licences/' + $credit))) ('Attribution absente : ' + $credit)
}
Check-Package ((Get-Content -LiteralPath (Join-Path $directory 'LISEZ-MOI.txt') -Raw).Contains('Version ' + ($ExpectedVersion -replace '\.0$',''))) 'Version du manuel incoherente.'

# These are the same canonical file properties exposed by the Explorer shell.
# This read does not claim a manual visual check of the Explorer window.
$shell = New-Object -ComObject Shell.Application
$folder = $shell.Namespace($directory)
$item = $folder.ParseName('PacificStrike.exe')
$shellDescription = $item.ExtendedProperty('System.FileDescription')
$shellVersion = $item.ExtendedProperty('System.FileVersion')
Check-Package ($shellDescription -eq $metadata.FileDescription) 'Description du shell Windows incoherente.'
Check-Package ($shellVersion -eq $ExpectedVersion) 'Version du shell Windows incoherente.'
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($item) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($folder) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null

Add-Type -AssemblyName System.Drawing
$icon = [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
Check-Package ($null -ne $icon) 'Icone executable absente.'
$iconBitmap = $icon.ToBitmap()
$iconBitmap.Save((Join-Path $scratch 'executable-icon.png'),[System.Drawing.Imaging.ImageFormat]::Png)
$iconBitmap.Dispose()
$icon.Dispose()

$runtime = @()
if (-not $SkipRuntime) {
    # Launch the normal main scene using only arguments supported by release
    # templates. --script and --path overrides are disabled in official builds.
    # No test driver or project resource is copied to the empty working folder.
    $emptyDirectory = Join-Path $scratch 'isolated-working-directory'
    New-Item -ItemType Directory -Path $emptyDirectory | Out-Null
    $runLog = Join-Path $scratch 'standalone-startup.log'
    $arguments = @('--windowed','--resolution','1280x720','--quit-after','180','--log-file',('"' + $runLog + '"'))
    $stdout = Join-Path $scratch 'standalone-stdout.log'
    $stderr = Join-Path $scratch 'standalone-stderr.log'
    $process = Start-Process -FilePath $exe -WorkingDirectory $emptyDirectory -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    if (-not $process.WaitForExit(60000)) {
        # The process handle belongs to the executable just extracted above.
        Stop-Process -Id $process.Id -Force
        throw 'Le lancement autonome ne s''est pas termine dans les 60 secondes.'
    }
    $process.WaitForExit()
    $process.Refresh()
    Check-Package ($process.ExitCode -eq 0) ('Echec de lancement autonome ; code ' + $process.ExitCode + ' ; diagnostic ' + (Get-Content -LiteralPath $stderr -Raw))
    Check-Package (Test-Path -LiteralPath $runLog) 'Journal moteur absent du lancement autonome.'
    $log = (Get-Content -LiteralPath $runLog -Raw) + (Get-Content -LiteralPath $stderr -Raw)
    Check-Package ($log -notmatch '(?m)(SCRIPT ERROR|ERROR:|WARNING:)') 'Diagnostic moteur pendant le lancement autonome.'
    Check-Package ($log -match 'OpenGL API') 'Initialisation du rendu OpenGL absente.'
    Check-Package (@(Get-ChildItem -LiteralPath $emptyDirectory -Force).Count -eq 0) 'Le dossier de travail autonome doit rester vide.'
    $runtime += @{ scenario = 'normal_main_scene_startup'; frames = 180; exit_code = $process.ExitCode; log = $runLog; script_suites = 'NOT_RUN_IN_RELEASE_EXECUTABLE' }
}
$report = @{
    version = $ExpectedVersion; product = $metadata.ProductName; description = $metadata.FileDescription
    executable_sha256 = $hash; checks = $checks; failures = @(); extracted_directory = $directory
    shell_file_description = $shellDescription; shell_file_version = $shellVersion
    explorer_visual_check = 'NOT_PERFORMED'; runtime = $runtime
}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'windows-package-results.json') -Encoding UTF8
$report | ConvertTo-Json -Depth 5

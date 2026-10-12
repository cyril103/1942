param(
    [string]$PackageZip = (Join-Path $PSScriptRoot '../../dist/PacificStrike-Windows-x64.zip'),
    [string]$BuiltExecutable = (Join-Path $PSScriptRoot '../../dist/PacificStrike/PacificStrike.exe'),
    [string]$ExpectedVersion = '',
    [string]$ExpectedDescription = '',
    [string]$ExportPreset = (Join-Path $PSScriptRoot '../export_presets.cfg'),
    [switch]$SkipRuntime
)
$ErrorActionPreference = 'Stop'
$checks = 0
function Check-Package([bool]$condition, [string]$message) {
    $script:checks += 1
    if (-not $condition) { throw $message }
}
# Read the same Windows Desktop metadata used by the exporter, rather than
# silently validating a historical release. Explicit overrides remain useful
# for an archived package whose preset is no longer the working version.
function Read-WindowsExportMetadata([string]$PresetPath) {
    $presetText = Get-Content -LiteralPath $PresetPath -Raw
    $sections = [regex]::Matches($presetText, '(?ms)^\[preset\.(?<index>\d+)\]\r?\n(?<body>.*?)(?=^\[|\z)')
    $windows = @($sections | Where-Object { $_.Groups['body'].Value -match '(?m)^name="Windows Desktop"\r?$' })
    if ($windows.Count -ne 1) { throw 'Le preset doit contenir exactement un export Windows Desktop.' }
    $sectionName = '[preset.' + $windows[0].Groups['index'].Value + '.options]'
    $options = [regex]::Match($presetText, '(?ms)^' + [regex]::Escape($sectionName) + '\r?\n(?<body>.*?)(?=^\[|\z)')
    if (-not $options.Success) { throw 'Options du preset Windows Desktop absentes.' }
    $properties = @{}
    foreach ($property in @('application/file_version','application/product_version','application/product_name','application/file_description')) {
        $match = [regex]::Match($options.Groups['body'].Value, '(?m)^' + [regex]::Escape($property) + '="([^"]+)"\r?$')
        if (-not $match.Success) { throw ('Metadonnee Windows absente du preset : ' + $property) }
        $properties[$property] = $match.Groups[1].Value
    }
    return $properties
}
$presetMetadata = Read-WindowsExportMetadata $ExportPreset
$expectedProductVersion = $ExpectedVersion
if ([string]::IsNullOrWhiteSpace($ExpectedVersion)) {
    $ExpectedVersion = $presetMetadata['application/file_version']
    $expectedProductVersion = $presetMetadata['application/product_version']
}
if ([string]::IsNullOrWhiteSpace($ExpectedDescription)) {
    $ExpectedDescription = $presetMetadata['application/file_description']
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
Check-Package ($metadata.ProductName -eq $presetMetadata['application/product_name']) 'Nom produit Windows incorrect.'
Check-Package ($metadata.FileDescription -eq $ExpectedDescription) 'Description Windows incorrecte.'
Check-Package ($metadata.FileVersion -eq $ExpectedVersion) 'Version fichier Windows incorrecte.'
Check-Package ($metadata.ProductVersion -eq $expectedProductVersion) 'Version produit Windows incorrecte.'
Check-Package (Test-Path -LiteralPath (Join-Path $directory 'LISEZ-MOI.txt')) 'Manuel absent du ZIP.'
Check-Package (Test-Path -LiteralPath (Join-Path $directory 'README-English.txt')) 'Manuel anglais absent du ZIP.'
$requiredCredits = @('Godot-LICENSE.txt','Godot-COPYRIGHT.txt','Musique.txt','Juhani-INFO.txt','Moteur-avion.md','Tirs-explosions.md','Terrains-terrestres.md','Terrains-volcaniques-arctiques.txt','Installations-militaires.md','DCA-mobile.md','barlowcondensed-OFL.txt','blackopsone-OFL.txt','DSEG-LICENSE.txt')
foreach ($credit in $requiredCredits) {
    Check-Package (Test-Path -LiteralPath (Join-Path $directory ('Licences/' + $credit))) ('Attribution absente : ' + $credit)
}
Check-Package (Test-Path -LiteralPath (Join-Path $directory 'Licences/Paysages-1.10.txt')) 'Provenance des paysages 1.10 absente.'
Check-Package (Test-Path -LiteralPath (Join-Path $directory 'Licences/Signatures-sonores-2.4.txt')) 'Provenance des signatures sonores absente.'
Check-Package ((Get-Content -LiteralPath (Join-Path $directory 'LISEZ-MOI.txt') -Raw).Contains('Version ' + ($ExpectedVersion -replace '\.0$',''))) 'Version du manuel incoherente.'
Check-Package ((Get-Content -LiteralPath (Join-Path $directory 'README-English.txt') -Raw).Contains('Version ' + ($ExpectedVersion -replace '\.0$',''))) 'Version du manuel anglais incoherente.'
$audioProvenance = Get-Content -LiteralPath (Join-Path $directory 'Licences/Signatures-sonores-2.4.txt') -Raw
foreach ($cue in @('boss.wav','danger.wav','radio.wav','radio_important.wav','reward.wav')) {
    Check-Package ($audioProvenance.Contains($cue)) ('Signature sonore absente de la provenance : ' + $cue)
}

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
    # User-requested silence: no audio device is opened during automated tests.
    $arguments = @('--audio-driver','Dummy','--windowed','--resolution','1280x720','--log-file',('"' + $runLog + '"'))
    $stdout = Join-Path $scratch 'standalone-stdout.log'
    $stderr = Join-Path $scratch 'standalone-stderr.log'
    $process = Start-Process -FilePath $exe -WorkingDirectory $emptyDirectory -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $null = $process.Handle
    # Exercise the actual WM_CLOSE -> App._quit path. --quit-after forcibly
    # bypasses the game's stop/drain sequence and can retain an audio playback.
    $startupClock = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $process.HasExited -and $startupClock.Elapsed.TotalSeconds -lt 30) {
        $process.Refresh()
        if ($process.MainWindowHandle -ne [IntPtr]::Zero -and $startupClock.Elapsed.TotalSeconds -ge 3) { break }
        Start-Sleep -Milliseconds 100
    }
    $closeRequested = -not $process.HasExited -and $process.CloseMainWindow()
    if (-not $closeRequested) {
        if (-not $process.HasExited) { $process.Kill() }
        throw 'Impossible de demander la fermeture normale du processus extrait.'
    }
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
    $runtime += @{ scenario = 'normal_main_scene_startup_and_window_close'; minimum_startup_seconds = 3; elapsed_seconds = $startupClock.Elapsed.TotalSeconds; close_requested = $closeRequested; exit_code = $process.ExitCode; log = $runLog; script_suites = 'NOT_RUN_IN_RELEASE_EXECUTABLE' }
}
$report = @{
    version = $ExpectedVersion; product_version = $expectedProductVersion; product = $metadata.ProductName; description = $metadata.FileDescription
    expected_description = $ExpectedDescription; export_preset = [System.IO.Path]::GetFullPath($ExportPreset)
    executable_sha256 = $hash; checks = $checks; failures = @(); extracted_directory = $directory
    shell_file_description = $shellDescription; shell_file_version = $shellVersion
    explorer_visual_check = 'NOT_PERFORMED'; runtime = $runtime
}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'windows-package-results.json') -Encoding UTF8
$report | ConvertTo-Json -Depth 5

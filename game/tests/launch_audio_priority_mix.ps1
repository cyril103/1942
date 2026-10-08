[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$GodotExe,
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot '..'),
    [string]$MainPack = '',
    [string]$OutputDirectory = '',
    [string]$MuteHelper = (Join-Path $PSScriptRoot 'mute_test_audio.ps1'),
    [ValidateRange(90, 600)][int]$TimeoutSeconds = 180
)

# This starts one owned Godot recorder, never a performance benchmark.
# It NEVER unmutes Windows or changes the system/device master volume.
# The existing COM helper mutes only verified PIDs belonging to this launch.
# An atomically published PID/token acknowledgement precedes every game voice.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-FullExistingPath([string]$PathValue) {
    return (Resolve-Path -LiteralPath $PathValue -ErrorAction Stop).ProviderPath
}

function Quote-NativeArgument([string]$Value) {
    # Windows CommandLineToArgvW escaping, including trailing backslashes.
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (2 * $slashes + 1)))
            [void]$builder.Append('"')
        } else {
            [void]$builder.Append(('\' * $slashes))
            [void]$builder.Append($character)
        }
        $slashes = 0
    }
    [void]$builder.Append(('\' * (2 * $slashes)))
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Get-ProcessIdentity([uint32]$IdentityId) {
    return Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $IdentityId" -ErrorAction Stop
}

function Read-SharedText([string]$PathValue) {
    # Start-Process can still own the redirected writer while we read the
    # handshake. Permit its existing write handle as well as this reader.
    $stream = [System.IO.FileStream]::new($PathValue, [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $reader = [System.IO.StreamReader]::new($stream)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function Test-Identity($Current, $Expected) {
    return $null -ne $Current -and
        [uint32]$Current.ProcessId -eq [uint32]$Expected.ProcessId -and
        [string]$Current.ExecutablePath -eq [string]$Expected.ExecutablePath -and
        $Current.CreationDate.ToUniversalTime().Ticks -eq $Expected.CreationDate.ToUniversalTime().Ticks
}

function Update-OwnedChildren {
    # PID alone is insufficient: only descendants of still-identical owners
    # with an expected Godot executable and creation time are admitted.
    foreach ($owner in @($ownedProcesses.Values)) {
        if (-not (Test-Identity (Get-ProcessIdentity ([uint32]$owner.ProcessId)) $owner)) { continue }
        foreach ($child in @(Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId = $($owner.ProcessId)")) {
            if ($allowedExecutables -notcontains [string]$child.ExecutablePath) { continue }
            if ($child.CreationDate.ToUniversalTime() -lt $launchUtc) { continue }
            if (-not $ownedProcesses.ContainsKey([uint32]$child.ProcessId)) {
                $ownedProcesses[[uint32]$child.ProcessId] = $child
            }
        }
    }
}

function Stop-OnlyOwnedProcesses {
    # Children first. Never Stop-Process -Name or stop a PID after reuse.
    foreach ($owner in @($ownedProcesses.Values | Sort-Object CreationDate -Descending)) {
        try {
            if (Test-Identity (Get-ProcessIdentity ([uint32]$owner.ProcessId)) $owner) {
                Stop-Process -Id ([int]$owner.ProcessId) -Force -ErrorAction Stop
            }
        } catch {
            Write-Warning "Cannot safely stop owned process $($owner.ProcessId): $($_.Exception.Message)"
        }
    }
}

$resolvedGodot = Get-FullExistingPath $GodotExe
$resolvedProject = Get-FullExistingPath $ProjectDirectory
$resolvedHelper = Get-FullExistingPath $MuteHelper
$resolvedPack = ''
$packHash = ''
if (-not [string]::IsNullOrWhiteSpace($MainPack)) {
    $resolvedPack = Get-FullExistingPath $MainPack
    if (-not (Test-Path -LiteralPath $resolvedPack -PathType Leaf)) { throw 'MainPack must be an existing pack file.' }
    $packHash = (Get-FileHash -LiteralPath $resolvedPack -Algorithm SHA256).Hash
}
if (-not (Test-Path -LiteralPath (Join-Path $resolvedProject 'project.godot') -PathType Leaf)) {
    throw 'ProjectDirectory must contain project.godot.'
}
if (-not (Test-Path -LiteralPath (Join-Path $resolvedProject 'tests/record_audio_priority_mix.gd') -PathType Leaf)) {
    throw 'The production recorder must be installed before this launch.'
}
if ([System.IO.Path]::GetExtension($resolvedGodot) -ne '.exe') { throw 'GodotExe must be a Windows executable.' }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot ("../../tools/review/audio-recording-" + [guid]::NewGuid().ToString('N'))
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $resolvedOutput) { throw 'OutputDirectory must be a new directory; no old evidence will be overwritten.' }
[void](New-Item -ItemType Directory -Path $resolvedOutput)
$recorderSnapshot = Join-Path $resolvedOutput 'record_audio_priority_mix.gd'
Copy-Item -LiteralPath (Join-Path $resolvedProject 'tests/record_audio_priority_mix.gd') -Destination $recorderSnapshot
[System.IO.File]::WriteAllText((Join-Path $resolvedOutput 'launch-identity.json'),
    (@{main_pack = $resolvedPack; pack_sha256 = $packHash;
        external_recorder = $recorderSnapshot; recorder_sha256 = (Get-FileHash -LiteralPath $recorderSnapshot -Algorithm SHA256).Hash;
        driver = 'WASAPI'; audible_output = 'MUTE_ACK_REQUIRED_BEFORE_VOICES';
        runtime = 'Godot editor and optional embedded release pack; not direct release-template execution'} | ConvertTo-Json),
    [System.Text.UTF8Encoding]::new($false))
$stdoutPath = Join-Path $resolvedOutput 'godot-stdout.log'
$stderrPath = Join-Path $resolvedOutput 'godot-stderr.log'
$ackPath = Join-Path $resolvedOutput 'windows-session-mute-ack.json'
$token = [guid]::NewGuid().ToString('N')
$allowedExecutables = @($resolvedGodot)
if ($resolvedGodot -match '_console\.exe$') {
    $guiExecutable = $resolvedGodot -replace '_console\.exe$', '.exe'
    if (Test-Path -LiteralPath $guiExecutable -PathType Leaf) { $allowedExecutables += $guiExecutable }
}
$ownedProcesses = @{}
$launchUtc = [DateTime]::UtcNow
$renderProcess = $null
$launchProcess = $null
$completed = $false
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
# Fail before launching anything if the process identity API is unavailable.
$null = Get-ProcessIdentity ([uint32][System.Diagnostics.Process]::GetCurrentProcess().Id)
try {
    $arguments = @('--path', $resolvedProject, '--audio-driver', 'WASAPI')
    if ($resolvedPack) { $arguments += @('--main-pack', $resolvedPack) }
    $arguments += @('--script', $recorderSnapshot, '--',
        "--output-dir=$resolvedOutput", "--mute-ack-file=$ackPath", "--mute-token=$token")
    $argumentText = ($arguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' '
    $launchProcess = Start-Process -FilePath $resolvedGodot -ArgumentList $argumentText -WorkingDirectory $resolvedProject `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    [void]$launchProcess.Handle
    $initialIdentity = Get-ProcessIdentity ([uint32]$launchProcess.Id)
    if ($null -eq $initialIdentity -or [string]$initialIdentity.ExecutablePath -ne $resolvedGodot) {
        throw 'Cannot establish the identity of the launched Godot process.'
    }
    $ownedProcesses[[uint32]$launchProcess.Id] = $initialIdentity
    $renderIdentity = $null
    while ($stopwatch.Elapsed.TotalSeconds -lt [Math]::Min(65, $TimeoutSeconds)) {
        Update-OwnedChildren
        if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) {
            $outputText = Read-SharedText $stdoutPath
            $match = [regex]::Match($outputText, '(?m)^Audio capture awaiting Windows mute ack: pid=(\d+) path=(.*?) token=(\S+)\r?$')
            if ($match.Success) {
                $renderId = [uint32]$match.Groups[1].Value
                if ($match.Groups[2].Value -ne $ackPath -or $match.Groups[3].Value.TrimEnd("`r") -ne $token) {
                    throw 'Recorder requested an unexpected acknowledgement path or token.'
                }
                if (-not $ownedProcesses.ContainsKey($renderId)) { throw 'Recorder PID is outside this launch ancestry.' }
                $renderIdentity = Get-ProcessIdentity $renderId
                if (-not (Test-Identity $renderIdentity $ownedProcesses[$renderId])) { throw 'Recorder process identity changed.' }
                $renderProcess = Get-Process -Id ([int]$renderId)
                [void]$renderProcess.Handle
                break
            }
        }
        Start-Sleep -Milliseconds 100
    }
    if ($null -eq $renderIdentity) { throw 'No valid, owned recorder handshake appeared before the timeout.' }
    $muteEvidence = @()
    while ($stopwatch.Elapsed.TotalSeconds -lt [Math]::Min(65, $TimeoutSeconds)) {
        if (-not (Test-Identity (Get-ProcessIdentity ([uint32]$renderIdentity.ProcessId)) $renderIdentity)) {
            throw 'Recorder exited or changed identity before its mute acknowledgement.'
        }
        if ($null -eq ('TestSessionAudio' -as [type])) {
            $observed = @(& $resolvedHelper -ProcessIds @([uint32]$renderIdentity.ProcessId))
        } else {
            $observed = @([TestSessionAudio]::Silence(@([uint32]$renderIdentity.ProcessId)))
        }
        $expectedLine = '^pid=' + [regex]::Escape([string]$renderIdentity.ProcessId) + ' role=\d+ volume=0(?:[\.,]0+)? muted=True$'
        if ($observed.Count -gt 0) {
            if (@($observed | Where-Object { [string]$_ -notmatch $expectedLine }).Count -ne 0) { throw 'Windows session mute/zero-volume verification failed.' }
            $muteEvidence = $observed
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if ($muteEvidence.Count -eq 0) { throw 'No Windows audio session could be verified muted before the recorder timeout.' }
    $ack = @{pid = [uint32]$renderIdentity.ProcessId; muted = $true; volume = 0; token = $token}
    $temporaryAck = $ackPath + '.new'
    [System.IO.File]::WriteAllText($temporaryAck, ($ack | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryAck -Destination $ackPath
    [System.IO.File]::WriteAllText((Join-Path $resolvedOutput 'windows-session-mute-evidence.json'),
        (@{ack = $ack; observed_sessions = $muteEvidence; process_path = $renderIdentity.ExecutablePath;
            process_creation_utc = $renderIdentity.CreationDate.ToUniversalTime().ToString('o');
            helper_sha256 = (Get-FileHash -LiteralPath $resolvedHelper -Algorithm SHA256).Hash;
            unmuted_by_launcher = $false} | ConvertTo-Json -Depth 5),
        [System.Text.UTF8Encoding]::new($false))
    while (-not $renderProcess.HasExited -and $stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) { Start-Sleep -Milliseconds 100 }
    if (-not $renderProcess.HasExited) { throw 'Recorder timed out after acknowledgement.' }
    $renderProcess.WaitForExit()
    # Get-Process can leave ExitCode unavailable for a non-child renderer.
    # The console was launched here; its exit code and the report/log gates
    # remain required, and an available failing renderer code is rejected.
    if ($null -ne $renderProcess.ExitCode -and $renderProcess.ExitCode -ne 0) { throw "Recorder exited with code $($renderProcess.ExitCode). Inspect the isolated logs." }
    if (-not $launchProcess.WaitForExit(5000)) { throw 'Godot console wrapper did not terminate after its recorder.' }
    if ($null -eq $launchProcess.ExitCode -or $launchProcess.ExitCode -ne 0) { throw "Godot console wrapper returned no successful exit code: $($launchProcess.ExitCode)." }
    $engineOutput = (Read-SharedText $stdoutPath) + "`n" + (Read-SharedText $stderrPath)
    if ($engineOutput -match '(?m)^(?:SCRIPT ERROR:|ERROR:|WARNING:)') { throw 'Godot reported an error or warning; inspect the isolated logs.' }
    $reportPath = Join-Path $resolvedOutput 'audio-priority-recording-results.json'
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw 'Recorder produced no complete report.' }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    if ($report.failures.Count -ne 0 -or $report.recordings.Count -ne 4 -or $report.checks -lt 101) { throw 'Recorder coverage/failures are not acceptable.' }
    if ($report.mute_ack.pid -ne $renderIdentity.ProcessId -or $report.mute_ack.token -ne $token -or
        $report.mute_ack.muted -ne $true -or $report.mute_ack.volume -ne 0) { throw 'Report acknowledgement does not match this muted process.' }
    $actualIds = @($report.recordings | ForEach-Object { $_.profile.id }) -join ','
    if ($actualIds -ne 'full,music-only,effects-only,user-sliders') { throw 'Recorder did not finish all four distinct profiles.' }
    foreach ($clip in $report.recordings) {
        if ($clip.peak_pcm16 -le 100 -or $clip.peak_pcm16 -ge 32760 -or $clip.saturated_samples -ne 0 -or $clip.duration -lt 7.75) {
            throw 'A recorded clip failed the original non-silence, saturation or duration guard.'
        }
    }
    if ($resolvedPack -and (Get-FileHash -LiteralPath $resolvedPack -Algorithm SHA256).Hash -ne $packHash) {
        throw 'Embedded pack changed during recording.'
    }
    $completed = $true
    Write-Output "Silent physical-mixer recording completed: $reportPath"
} finally {
    if (-not $completed) { Stop-OnlyOwnedProcesses }
    $stopwatch.Stop()
}

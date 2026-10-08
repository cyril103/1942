#requires -Version 5.1
<#
.SYNOPSIS
Runs the external full-mission probe against an embedded Windows game pack.
.DESCRIPTION
One rendered benchmark at a time. Process private bytes, working set and lifetime
peak working set are sampled at a target of 1 Hz. These are not engine allocation
monitors or VRAM readings. The Dummy audio driver keeps these performance tests
silent; use the separate muted-Windows audio recorder for actual PCM validation.
-DryRun validates files/arguments without launching,
hashing the pack, creating output files or taking process samples.
#>
[CmdletBinding()]
param(
    [string]$GodotConsole = 'D:/godot/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe',
    [string]$PackExecutable = (Join-Path $PSScriptRoot '../../dist/PacificStrike/PacificStrike.exe'),
    [string]$BenchmarkScript = (Join-Path $PSScriptRoot 'benchmark_full_mission.gd'),
    [string[]]$BenchmarkDependencies = @(),
    [string]$GodotRenderExecutable = '',
    [ValidateRange(1, 32)][int]$Mission = 31,
    [ValidateRange(0, 2)][int]$Quality = 1,
    [ValidateRange(1, 20)][int]$Repeats = 2,
    [ValidateRange(10, 300)][int]$DurationSeconds = 140,
    [ValidateRange(640, 7680)][int]$Width = 1920,
    [ValidateRange(360, 4320)][int]$Height = 1080,
    [ValidateRange(0, 30000)][int]$TimeoutSeconds = 0,
    [string]$BuildId = 'unidentified',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../../tools/review/process-memory'),
    [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-MeasurementFile([string]$Path, [string]$Label, [string]$Extension) {
    $taskItem = Get-Item -LiteralPath $Path
    if ($taskItem.PSProvider.Name -ne 'FileSystem' -or $taskItem.PSIsContainer -or $taskItem.Extension -ine $Extension) {
        throw "$Label must be an existing $Extension file: $Path"
    }
    return $taskItem.FullName
}

function ConvertTo-WindowsArgument([string]$Argument) {
    # Start-Process joins ArgumentList items; it does not quote each path. Apply
    # the CommandLineToArgvW/MS CRT escaping rules without invoking a shell.
    if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s"]') { return $Argument }
    $taskBuilder = New-Object System.Text.StringBuilder
    [void]$taskBuilder.Append('"')
    $taskSlashes = 0
    foreach ($taskCharacter in $Argument.ToCharArray()) {
        if ($taskCharacter -eq [char]92) { $taskSlashes += 1; continue }
        if ($taskCharacter -eq [char]34) {
            [void]$taskBuilder.Append([string]::new([char]92, 2 * $taskSlashes + 1))
        } elseif ($taskSlashes -gt 0) {
            [void]$taskBuilder.Append([string]::new([char]92, $taskSlashes))
        }
        [void]$taskBuilder.Append($taskCharacter)
        $taskSlashes = 0
    }
    if ($taskSlashes -gt 0) { [void]$taskBuilder.Append([string]::new([char]92, 2 * $taskSlashes)) }
    [void]$taskBuilder.Append('"')
    return $taskBuilder.ToString()
}

function Get-ProcessIdentity([int]$ProcessId) {
    return Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$ProcessId" -OperationTimeoutSec 5
}

function Test-RecordIdentity($Record, $Identity) {
    if ($null -eq $Identity) { return $false }
    if ([int]$Identity.ProcessId -ne $Record.Id) { return $false }
    $taskCreated = ([datetime]$Identity.CreationDate).ToUniversalTime()
    # CIM's creation time has microsecond precision; the retained kernel handle
    # also protects against PID reuse between this check and Kill()/sampling.
    return [math]::Abs(($taskCreated - $Record.CreatedUtc).TotalMilliseconds) -lt 1
}

function Update-RecordExit($Record) {
    if ($null -ne $Record.ExitUtc) { return }
    if ($Record.Process.HasExited) {
        $Record.ExitUtc = $Record.Process.ExitTime.ToUniversalTime()
        $Record.ExitCode = $Record.Process.ExitCode
    }
}

function Get-EngineCandidates {
    $taskCandidates = @($script:taskOwned.Values | Where-Object {
        $null -eq $_.ExitUtc -and ($_.Executable -ieq $script:taskRenderPath -or $_.Executable -ieq $script:taskConsolePath)
    })
    if ($taskCandidates.Count -eq 0) { return @() }
    # Prefer the real child rendering executable. The console launcher is kept
    # as a separate record. A console that does not fork can itself be the engine.
    $taskRendered = @($taskCandidates | Where-Object { $_.Id -ne $script:taskRootId })
    if ($taskRendered.Count -gt 0) { return $taskRendered }
    return $taskCandidates
}

function Find-OwnedDescendants {
    $taskQueue = New-Object 'System.Collections.Generic.Queue[object]'
    foreach ($taskRecord in @($script:taskOwned.Values)) { $taskQueue.Enqueue($taskRecord) }
    while ($taskQueue.Count -gt 0) {
        $taskParent = $taskQueue.Dequeue()
        Update-RecordExit $taskParent
        # A retained original handle supplies the parent's real exit time even
        # when a short-lived console wrapper disappeared before its first poll.
        if ($null -eq $taskParent.ExitUtc) {
            $taskParentIdentity = Get-ProcessIdentity $taskParent.Id
            if (-not (Test-RecordIdentity $taskParent $taskParentIdentity)) {
                Update-RecordExit $taskParent
                if ($null -eq $taskParent.ExitUtc) { continue }
            }
        }
        $taskChildren = @(Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId=$($taskParent.Id)" -OperationTimeoutSec 5)
        foreach ($taskChild in $taskChildren) {
            $taskChildId = [int]$taskChild.ProcessId
            $taskChildCreated = ([datetime]$taskChild.CreationDate).ToUniversalTime()
            if ($taskChildCreated -lt $taskParent.CreatedUtc.AddMilliseconds(-1)) { continue }
            if ($null -ne $taskParent.ExitUtc -and $taskChildCreated -gt $taskParent.ExitUtc.AddMilliseconds(1)) { continue }
            if ($script:taskOwned.ContainsKey($taskChildId)) { continue }
            if ($script:taskOwned.Count -ge 64) { throw 'Owned process tree exceeded its 64-record safety limit.' }
            $taskChildProcess = Get-Process -Id $taskChildId -ErrorAction SilentlyContinue
            if ($null -eq $taskChildProcess) { continue }
            try {
                # Acquire and retain THIS process handle before checking again.
                [void]$taskChildProcess.Handle
                $taskVerified = Get-ProcessIdentity $taskChildId
                if ($null -eq $taskVerified -or [int]$taskVerified.ParentProcessId -ne $taskParent.Id -or [math]::Abs((([datetime]$taskVerified.CreationDate).ToUniversalTime() - $taskChildCreated).TotalMilliseconds) -ge 1) {
                    $taskChildProcess.Dispose()
                    continue
                }
                if ([math]::Abs(($taskChildProcess.StartTime.ToUniversalTime() - $taskChildCreated).TotalMilliseconds) -ge 1) {
                    $taskChildProcess.Dispose()
                    continue
                }
                $taskChildPath = [string]$taskVerified.ExecutablePath
                if ([string]::IsNullOrWhiteSpace($taskChildPath)) { $taskChildPath = [string]$taskChildProcess.Path }
                $taskRecord = [pscustomobject]@{
                    Id = $taskChildId; ParentId = $taskParent.Id; ParentCreatedUtc = $taskParent.CreatedUtc
                    CreatedUtc = $taskChildCreated; Executable = $taskChildPath; Depth = $taskParent.Depth + 1
                    Process = $taskChildProcess; ExitUtc = $null; ExitCode = $null; Samples = 0
                    ObservedPrivatePeak = [long]0; ObservedWorkingSetPeak = [long]0; ReportedWorkingSetPeak = [long]0
                    TerminationRequested = $false
                }
                $script:taskOwned[$taskChildId] = $taskRecord
                $taskQueue.Enqueue($taskRecord)
            } catch {
                $taskChildProcess.Dispose()
                throw
            }
        }
    }
}

function Read-OwnedMemory {
    $taskRows = New-Object 'System.Collections.Generic.List[object]'
    $taskEngineIds = @(Get-EngineCandidates | ForEach-Object { $_.Id })
    foreach ($taskRecord in @($script:taskOwned.Values | Sort-Object Depth, Id)) {
        Update-RecordExit $taskRecord
        if ($null -ne $taskRecord.ExitUtc) { continue }
        $taskIdentity = Get-ProcessIdentity $taskRecord.Id
        if (-not (Test-RecordIdentity $taskRecord $taskIdentity)) {
            Update-RecordExit $taskRecord
            if ($null -ne $taskRecord.ExitUtc) { continue }
            throw "Live owned process identity no longer matches: $($taskRecord.Id)."
        }
        $taskCurrent = Get-Process -Id $taskRecord.Id -ErrorAction SilentlyContinue
        if ($null -eq $taskCurrent) { Update-RecordExit $taskRecord; continue }
        try {
            if ([math]::Abs(($taskCurrent.StartTime.ToUniversalTime() - $taskRecord.CreatedUtc).TotalMilliseconds) -ge 1) {
                throw "Get-Process returned a reused PID: $($taskRecord.Id)."
            }
            $taskCurrent.Refresh()
            $taskPrivate = [long]$taskCurrent.PrivateMemorySize64
            $taskWorking = [long]$taskCurrent.WorkingSet64
            $taskPeakWorking = [long]$taskCurrent.PeakWorkingSet64
            $taskRecord.Samples += 1
            $taskRecord.ObservedPrivatePeak = [math]::Max($taskRecord.ObservedPrivatePeak, $taskPrivate)
            $taskRecord.ObservedWorkingSetPeak = [math]::Max($taskRecord.ObservedWorkingSetPeak, $taskWorking)
            $taskRecord.ReportedWorkingSetPeak = [math]::Max($taskRecord.ReportedWorkingSetPeak, $taskPeakWorking)
            [void]$taskRows.Add([ordered]@{
                pid = $taskRecord.Id; parent_pid = $taskRecord.ParentId
                created_utc = $taskRecord.CreatedUtc.ToString('o'); executable = $taskRecord.Executable
                is_engine_candidate = ($taskRecord.Id -in $taskEngineIds)
                private_memory_bytes = $taskPrivate; working_set_bytes = $taskWorking
                peak_working_set_process_bytes = $taskPeakWorking
                sampled_utc = (Get-Date).ToUniversalTime().ToString('o')
            })
        } catch {
            if (-not $taskRecord.Process.HasExited) { throw }
            Update-RecordExit $taskRecord
        } finally {
            $taskCurrent.Dispose()
        }
    }
    return $taskRows.ToArray()
}

function Stop-OwnedProcesses {
    # Only verified records acquired from our launch handle and its time-bounded
    # parent-child chain. Never enumerate/kill all processes named "Godot".
    for ($taskAttempt = 0; $taskAttempt -lt 3; $taskAttempt++) {
        try { Find-OwnedDescendants } catch { [void]$script:taskCleanupErrors.Add($_.Exception.Message) }
        foreach ($taskRecord in @($script:taskOwned.Values | Sort-Object Depth -Descending)) {
            try {
                Update-RecordExit $taskRecord
                if ($null -ne $taskRecord.ExitUtc) { continue }
                $taskIdentity = Get-ProcessIdentity $taskRecord.Id
                if (-not (Test-RecordIdentity $taskRecord $taskIdentity)) {
                    [void]$script:taskCleanupErrors.Add("Refused to stop a PID with mismatched identity: $($taskRecord.Id).")
                    continue
                }
                $taskRecord.TerminationRequested = $true
                # Kill uses the retained original process handle; no PID-reuse
                # race can redirect the operation to an unrelated new process.
                $taskRecord.Process.Kill()
            } catch {
                if (-not $taskRecord.Process.HasExited) { [void]$script:taskCleanupErrors.Add($_.Exception.Message) }
            }
        }
        Start-Sleep -Milliseconds 200
    }
    foreach ($taskRecord in @($script:taskOwned.Values)) {
        try {
            if (-not $taskRecord.Process.HasExited) { [void]$taskRecord.Process.WaitForExit(2000) }
            Update-RecordExit $taskRecord
            if ($null -eq $taskRecord.ExitUtc) { [void]$script:taskCleanupErrors.Add("Owned process remains alive: $($taskRecord.Id).") }
        } catch { [void]$script:taskCleanupErrors.Add($_.Exception.Message) }
    }
}

if ($env:OS -ne 'Windows_NT') { throw 'This observer requires Windows process/CIM APIs.' }
$script:taskConsolePath = Resolve-MeasurementFile $GodotConsole 'Godot console editor' '.exe'
$taskPackPath = Resolve-MeasurementFile $PackExecutable 'Embedded game pack' '.exe'
$taskSourcePath = Resolve-MeasurementFile $BenchmarkScript 'External benchmark script' '.gd'
$taskDependencyPaths = @()
$taskSnapshotNames = @([System.IO.Path]::GetFileName($taskSourcePath))
foreach ($taskDependency in $BenchmarkDependencies) {
    $taskResolvedDependency = Resolve-MeasurementFile $taskDependency 'External benchmark dependency' '.gd'
    $taskDependencyName = [System.IO.Path]::GetFileName($taskResolvedDependency)
    if ($taskSnapshotNames -contains $taskDependencyName) { throw "Duplicate snapshot filename: $taskDependencyName" }
    $taskSnapshotNames += $taskDependencyName
    $taskDependencyPaths += $taskResolvedDependency
}
if ([string]::IsNullOrWhiteSpace($GodotRenderExecutable)) {
    $script:taskRenderPath = $script:taskConsolePath -replace '(?i)([_\-.]console)\.exe$', '.exe'
} else {
    $script:taskRenderPath = Resolve-MeasurementFile $GodotRenderExecutable 'Godot rendering child' '.exe'
}
$taskOutputBase = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$taskRunId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$taskRunDirectory = Join-Path $taskOutputBase $taskRunId
$taskWorkingDirectory = Join-Path $taskRunDirectory 'working'
$taskSnapshotScript = Join-Path $taskRunDirectory ([System.IO.Path]::GetFileName($taskSourcePath))
$taskMemoryPath = Join-Path $taskRunDirectory 'process-memory.json'
$taskEnginePath = Join-Path $taskRunDirectory ('full-mission-{0:00}-q{1}-{2}x{3}.json' -f $Mission, $Quality, $Width, $Height)
$taskEngineLog = Join-Path $taskRunDirectory 'engine.log'
$taskStdout = Join-Path $taskRunDirectory 'stdout.log'
$taskStderr = Join-Path $taskRunDirectory 'stderr.log'
$taskEffectiveTimeout = $TimeoutSeconds
if ($taskEffectiveTimeout -eq 0) { $taskEffectiveTimeout = [int][math]::Ceiling($Repeats * ($DurationSeconds * 2.5 + 30) + 120) }
$taskArguments = @(
    '--main-pack', $taskPackPath, '--script', $taskSnapshotScript, '--audio-driver', 'Dummy',
    '--windowed', '--resolution', ('{0}x{1}' -f $Width, $Height), '--log-file', $taskEngineLog, '--',
    "--mission=$Mission", "--quality=$Quality", "--repeats=$Repeats", "--duration=$DurationSeconds",
    ('--size={0}x{1}' -f $Width, $Height), "--build-id=$BuildId", "--output-dir=$taskRunDirectory"
)
$taskArgumentLine = (@($taskArguments | ForEach-Object { ConvertTo-WindowsArgument $_ }) -join ' ')
$taskPlan = [ordered]@{
    schema = 1; dry_run = [bool]$DryRun; godot_console = $script:taskConsolePath
    expected_render_executable = $script:taskRenderPath; embedded_pack = $taskPackPath
    source_script = $taskSourcePath; external_script_snapshot = $taskSnapshotScript
    external_dependency_sources = $taskDependencyPaths
    arguments = $taskArguments; windows_argument_line = $taskArgumentLine
    working_directory = $taskWorkingDirectory; output_directory = $taskRunDirectory
    process_memory_report = $taskMemoryPath; engine_report = $taskEnginePath
    timeout_seconds = $taskEffectiveTimeout; target_sample_interval_seconds = 1.0
    pack_sha256 = 'NOT_COMPUTED_IN_DRY_RUN'
    launch_policy = 'Start-Process -WindowStyle Hidden; only this launch and verified descendants'
}
if ($DryRun) { $taskPlan | ConvertTo-Json -Depth 8; return }

# Check CIM permission before launching anything; a denied observer must never
# leave an untracked Godot child running. DryRun intentionally skips this read.
$taskObserverIdentity = Get-ProcessIdentity $PID
if ($null -eq $taskObserverIdentity -or [int]$taskObserverIdentity.ProcessId -ne $PID) {
    throw 'CIM process identity preflight failed before launch.'
}

$script:taskOwned = @{}
$script:taskRootId = 0
$script:taskCleanupErrors = New-Object 'System.Collections.Generic.List[string]'
$taskSamples = New-Object 'System.Collections.Generic.List[object]'
$taskErrors = New-Object 'System.Collections.Generic.List[string]'
$taskClock = [System.Diagnostics.Stopwatch]::new()
$taskState = 'initializing'
$taskPackHash = $null
$taskSourceHash = $null
$taskDependencySnapshots = @()
$taskConsoleHash = $null
$taskEngineReport = $null
$taskStartedUtc = (Get-Date).ToUniversalTime()
$taskObservedChild = $false
try {
    New-Item -ItemType Directory -Path $taskWorkingDirectory -Force | Out-Null
    Copy-Item -LiteralPath $taskSourcePath -Destination $taskSnapshotScript
    foreach ($taskDependencyPath in $taskDependencyPaths) {
        $taskDependencyDestination = Join-Path $taskRunDirectory ([System.IO.Path]::GetFileName($taskDependencyPath))
        Copy-Item -LiteralPath $taskDependencyPath -Destination $taskDependencyDestination
        $taskDependencySnapshots += [ordered]@{ source = $taskDependencyPath; snapshot = $taskDependencyDestination; sha256 = (Get-FileHash -LiteralPath $taskDependencyDestination -Algorithm SHA256).Hash }
    }
    $taskPackHash = (Get-FileHash -LiteralPath $taskPackPath -Algorithm SHA256).Hash
    $taskSourceHash = (Get-FileHash -LiteralPath $taskSnapshotScript -Algorithm SHA256).Hash
    $taskConsoleHash = (Get-FileHash -LiteralPath $script:taskConsolePath -Algorithm SHA256).Hash
    $taskLauncher = Start-Process -FilePath $script:taskConsolePath -ArgumentList $taskArgumentLine -WorkingDirectory $taskWorkingDirectory -WindowStyle Hidden -RedirectStandardOutput $taskStdout -RedirectStandardError $taskStderr -PassThru
    [void]$taskLauncher.Handle
    $script:taskRootId = $taskLauncher.Id
    $taskRootCreated = $taskLauncher.StartTime.ToUniversalTime()
    $taskRootRecord = [pscustomobject]@{
        Id = $taskLauncher.Id; ParentId = $null; ParentCreatedUtc = $null
        CreatedUtc = $taskRootCreated; Executable = $script:taskConsolePath; Depth = 0
        Process = $taskLauncher; ExitUtc = $null; ExitCode = $null; Samples = 0
        ObservedPrivatePeak = [long]0; ObservedWorkingSetPeak = [long]0; ReportedWorkingSetPeak = [long]0
        TerminationRequested = $false
    }
    $script:taskOwned[$taskLauncher.Id] = $taskRootRecord
    $taskClock.Start()
    $taskState = 'running'
    $taskNextSample = 0.0
    while ($true) {
        $taskPollStarted = $taskClock.Elapsed.TotalMilliseconds
        Find-OwnedDescendants
        foreach ($taskRecord in @($script:taskOwned.Values)) { Update-RecordExit $taskRecord }
        $taskCandidates = @(Get-EngineCandidates)
        if (@($taskCandidates | Where-Object { $_.Id -ne $script:taskRootId }).Count -gt 0) { $taskObservedChild = $true }
        if ($taskCandidates.Count -gt 1) { throw 'Multiple live Godot engine candidates: primary process is ambiguous.' }
        $taskRows = @(Read-OwnedMemory)
        [void]$taskSamples.Add([ordered]@{
            utc = (Get-Date).ToUniversalTime().ToString('o'); elapsed_seconds = $taskClock.Elapsed.TotalSeconds
            target_elapsed_seconds = $taskNextSample; primary_engine_pid = $(if ($taskCandidates.Count -eq 1) { $taskCandidates[0].Id } else { $null })
            processes = $taskRows; observer_poll_ms = $taskClock.Elapsed.TotalMilliseconds - $taskPollStarted
        })
        $taskAlive = @($script:taskOwned.Values | Where-Object { $null -eq $_.ExitUtc })
        if ($taskAlive.Count -eq 0) {
            # Console can create its renderer AFTER the first child query and
            # exit before Update-RecordExit. Scan once more with its retained
            # creation/exit bounds before declaring the entire tree finished.
            Find-OwnedDescendants
            foreach ($taskRecord in @($script:taskOwned.Values)) { Update-RecordExit $taskRecord }
            $taskAlive = @($script:taskOwned.Values | Where-Object { $null -eq $_.ExitUtc })
            if ($taskAlive.Count -eq 0) { $taskState = 'processes_exited'; break }
        }
        if ($taskClock.Elapsed.TotalSeconds -ge $taskEffectiveTimeout) { $taskState = 'timeout'; throw "Owned benchmark exceeded $taskEffectiveTimeout seconds." }
        # A monotonic target avoids adding CIM/observer time to every interval.
        $taskNextSample += 1.0
        if ($taskNextSample -lt $taskClock.Elapsed.TotalSeconds) { $taskNextSample = [math]::Floor($taskClock.Elapsed.TotalSeconds) + 1.0 }
        $taskWaitMs = [int][math]::Max(1, [math]::Ceiling(($taskNextSample - $taskClock.Elapsed.TotalSeconds) * 1000))
        Start-Sleep -Milliseconds $taskWaitMs
    }
    $taskEngineRecords = @($script:taskOwned.Values | Where-Object { $_.Executable -ieq $script:taskRenderPath -and $_.Id -ne $script:taskRootId })
    if ($taskEngineRecords.Count -eq 0) {
        if ($script:taskOwned.Count -eq 1 -and -not $taskObservedChild) { $taskEngineRecords = @($taskRootRecord) }
        else { throw 'A child process was observed but no verified rendering executable matched the requested Godot path.' }
    }
    if (@($taskEngineRecords | Where-Object { $_.Samples -gt 0 }).Count -eq 0) { throw 'No verified engine process was sampled.' }
    foreach ($taskRecord in @($script:taskOwned.Values)) {
        if ($null -ne $taskRecord.ExitCode -and $taskRecord.ExitCode -ne 0) { throw "Owned PID $($taskRecord.Id) exited with code $($taskRecord.ExitCode)." }
    }
    if (-not (Test-Path -LiteralPath $taskEnginePath -PathType Leaf)) { throw "Expected engine benchmark JSON is missing: $taskEnginePath" }
    $taskEngineReport = Get-Content -LiteralPath $taskEnginePath -Raw | ConvertFrom-Json
    if (@($taskEngineReport.failures).Count -gt 0) { throw 'Engine benchmark reported failures; see the separate engine report.' }
    if (@($taskEngineReport.passes).Count -ne $Repeats) { throw 'Engine benchmark completed a different number of passes.' }
    $taskDiagnostic = ''
    foreach ($taskLogPath in @($taskEngineLog, $taskStdout, $taskStderr)) {
        if (Test-Path -LiteralPath $taskLogPath -PathType Leaf) { $taskDiagnostic += [System.IO.File]::ReadAllText($taskLogPath) + "`n" }
    }
    if ($taskDiagnostic -match '(?m)(SCRIPT ERROR|ERROR:|WARNING:)') { throw 'Engine logs contain errors/warnings; see the retained logs.' }
    if ((Get-FileHash -LiteralPath $taskPackPath -Algorithm SHA256).Hash -ne $taskPackHash) { throw 'Embedded pack changed during measurement.' }
    if ((Get-FileHash -LiteralPath $taskSnapshotScript -Algorithm SHA256).Hash -ne $taskSourceHash) { throw 'External probe snapshot changed during measurement.' }
    foreach ($taskDependencySnapshot in $taskDependencySnapshots) {
        if ((Get-FileHash -LiteralPath $taskDependencySnapshot.snapshot -Algorithm SHA256).Hash -ne $taskDependencySnapshot.sha256) { throw 'External dependency snapshot changed during measurement.' }
    }
    $taskState = 'completed'
} catch {
    [void]$taskErrors.Add($_.Exception.Message)
    if ($taskState -ne 'timeout') { $taskState = 'error' }
} finally {
    if ($taskState -in @('initializing', 'running', 'processes_exited')) {
        $taskState = 'interrupted'
        [void]$taskErrors.Add('Observer left its runtime before reaching a completed/error/timeout state.')
    }
    if ($taskState -ne 'completed' -and $script:taskOwned.Count -gt 0) { Stop-OwnedProcesses }
    $taskClock.Stop()
    $taskProcessReports = @()
    foreach ($taskRecord in @($script:taskOwned.Values | Sort-Object Depth, Id)) {
        try { Update-RecordExit $taskRecord } catch { [void]$script:taskCleanupErrors.Add($_.Exception.Message) }
        $taskProcessReports += [ordered]@{
            pid = $taskRecord.Id; parent_pid = $taskRecord.ParentId; depth = $taskRecord.Depth
            created_utc = $taskRecord.CreatedUtc.ToString('o')
            parent_created_utc = $(if ($null -ne $taskRecord.ParentCreatedUtc) { $taskRecord.ParentCreatedUtc.ToString('o') } else { $null })
            executable = $taskRecord.Executable; exit_code = $taskRecord.ExitCode
            exited_utc = $(if ($null -ne $taskRecord.ExitUtc) { $taskRecord.ExitUtc.ToString('o') } else { $null })
            termination_requested = $taskRecord.TerminationRequested; samples = $taskRecord.Samples
            observed_peak_private_bytes = $taskRecord.ObservedPrivatePeak
            observed_peak_working_set_bytes = $taskRecord.ObservedWorkingSetPeak
            reported_lifetime_peak_working_set_bytes = $taskRecord.ReportedWorkingSetPeak
        }
    }
    $taskReport = [ordered]@{
        schema = 1; state = $taskState; started_utc = $taskStartedUtc.ToString('o'); ended_utc = (Get-Date).ToUniversalTime().ToString('o')
        observer_wall_seconds = $taskClock.Elapsed.TotalSeconds; timeout_seconds = $taskEffectiveTimeout
        parameters = @{mission = $Mission; quality = $Quality; repeats = $Repeats; duration_seconds = $DurationSeconds; size = @($Width, $Height); build_id = $BuildId; audio_driver = 'Dummy'}
        godot_console = $script:taskConsolePath; godot_console_sha256 = $taskConsoleHash
        expected_render_executable = $script:taskRenderPath
        runtime_type = 'Godot console editor + embedded data pack; not direct release-template execution'
        embedded_pack = $taskPackPath; pack_sha256 = $taskPackHash
        source_script = $taskSourcePath; external_script_snapshot = $taskSnapshotScript; script_sha256 = $taskSourceHash
        external_dependencies = $taskDependencySnapshots
        launch_arguments = $taskArguments; windows_argument_line = $taskArgumentLine
        root_pid = $script:taskRootId; render_child_observed = $taskObservedChild
        observer_pid = [System.Diagnostics.Process]::GetCurrentProcess().Id
        process_identification = 'Retained launch handle + ParentProcessId + creation/exit time bounds + identity checks; rendering path preferred over console launcher'
        sample_target_hz = 1.0; memory_units = 'bytes'; samples = $taskSamples.ToArray(); processes = $taskProcessReports
        engine_report_path = $taskEnginePath; engine_report_present = (Test-Path -LiteralPath $taskEnginePath -PathType Leaf)
        engine_memory_is_distinct = $true; physical_vram_measured = $false
        memory_limits = @('PrivateMemorySize64 is private committed process memory, not resident RAM.', 'WorkingSet64 includes shared resident pages; do not sum it across processes as unique RAM.', 'PeakWorkingSet64 is the OS lifetime peak, while private/working-set maxima here are observed only at 1Hz.', 'Engine static/render allocation monitors remain in the separate benchmark JSON; none is physical VRAM occupancy.', 'A 1Hz observer can miss short allocation spikes. Process/CIM polling adds observer load.', 'No human play, leak diagnosis, second hardware configuration or guaranteed FPS follows from these samples.')
        errors = $taskErrors.ToArray(); cleanup_errors = $script:taskCleanupErrors.ToArray()
        stdout_path = $taskStdout; stderr_path = $taskStderr; engine_log_path = $taskEngineLog
    }
    if (Test-Path -LiteralPath $taskRunDirectory -PathType Container) {
        $taskJson = $taskReport | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText($taskMemoryPath, $taskJson, [System.Text.UTF8Encoding]::new($false))
    }
    foreach ($taskRecord in @($script:taskOwned.Values)) { $taskRecord.Process.Dispose() }
}
Write-Output $taskMemoryPath
if ($taskState -ne 'completed' -or $script:taskCleanupErrors.Count -gt 0) {
    throw "Process memory measurement ended with state '$taskState'; see $taskMemoryPath."
}

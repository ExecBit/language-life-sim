param(
    [ValidateRange(0.0, 2.0)][double]$Temperature = 0.1,
    [string]$GodotPath = $env:GODOT_BIN,
    [switch]$Check,
    [string[]]$GodotArguments = @()
)

$ErrorActionPreference = 'Stop'
$launchExitCode = 0
$savedEnvironment = @{}
try {
    $projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $profile = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\data\communication\qwen9.json') -Raw | ConvertFrom-Json
    foreach ($asset in @($profile.executable, $profile.weights)) {
        $assetPath = Join-Path $projectRoot ($asset -replace '^res://', '')
        if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
            throw "Missing local asset: $assetPath. Run python implementations/communication_lab/tools/setup_lfm3.py --model qwen9 from the project directory."
        }
    }
    if (-not $GodotPath) {
        $wingetRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
        $installed = Get-ChildItem -Path (Join-Path $wingetRoot 'GodotEngine.GodotEngine_*\Godot*_console.exe') -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($installed) { $GodotPath = $installed.FullName }
        else {
            $command = Get-Command godot -CommandType Application -ErrorAction SilentlyContinue
            if ($command) { $GodotPath = $command.Source }
        }
    }
    if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
        throw 'Godot engine not found. Supply -GodotPath with the installed Godot console executable.'
    }
    $settings = @{
        COMMLAB_LANGUAGE_MODEL = 'qwen9'
        COMMLAB_LANGUAGE_MODEL_ENABLED = '1'
        COMMLAB_PROMPT_VERSION = 'context-v2'
        COMMLAB_TEMPERATURE = $Temperature.ToString([Globalization.CultureInfo]::InvariantCulture)
    }
    foreach ($key in $settings.Keys) {
        $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $settings[$key], 'Process')
    }
    Write-Host "Communication Lab | Qwen3.5-9B | temperature $($settings.COMMLAB_TEMPERATURE) | context-v2"
    Write-Host "Godot: $GodotPath"
    Write-Host 'E: talk to Astera. F2: model request and dialogue graph. Model loads on the first submitted line.'
    if (-not $Check) {
        $engineArguments = @('--path', $projectRoot, '--rendering-method', 'gl_compatibility',
            'res://implementations/communication_lab/communication_lab.tscn') + $GodotArguments
        & $GodotPath @engineArguments
        $launchExitCode = $LASTEXITCODE
    }
    else { Write-Host 'CHECK PASS: engine and local model assets found; no game or inference process started.' }
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    $launchExitCode = 1
}
finally {
    foreach ($key in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key], 'Process')
    }
}
exit $launchExitCode

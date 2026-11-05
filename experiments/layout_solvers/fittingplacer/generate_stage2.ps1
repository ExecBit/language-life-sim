param(
    [Parameter(Mandatory = $true)][ValidateSet('A', 'B')][string]$Variant,
    [string]$GodotExe = (Get-Command Godot_v4.7.1-stable_win64_console.exe -ErrorAction Stop).Source
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path $PSScriptRoot).Path
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$env:APPDATA = Join-Path $repoRoot '.local/godot_user'
$upstream = Join-Path $repoRoot '.local/FittingPlacer'
$expectedCommit = '1cdb703197b41d418e7ce686e74c7aad835ddb37'
if (-not (Test-Path (Join-Path $upstream '.git'))) {
    git clone https://github.com/david-dot/FittingPlacer.git $upstream
    if ($LASTEXITCODE -ne 0) { throw 'Could not clone FittingPlacer.' }
}
$actualCommit = (git -C $upstream rev-parse HEAD).Trim()
if ($actualCommit -ne $expectedCommit) {
    git -C $upstream fetch --depth 1 origin $expectedCommit
    if ($LASTEXITCODE -ne 0) { throw 'Could not fetch the pinned FittingPlacer revision.' }
    git -C $upstream checkout --detach $expectedCommit
    if ($LASTEXITCODE -ne 0) { throw 'Could not select the pinned FittingPlacer revision.' }
}
Write-Host "FittingPlacer upstream commit verified: $actualCommit"
$project = Join-Path $root 'godot_preview'
$brief = Join-Path $project "stage2-$Variant-brief.json"
$layout = Join-Path $project "stage2-$Variant-layout.json"
$semantics = Join-Path $PSScriptRoot 'tavern.xml'
$runner = Join-Path $PSScriptRoot 'runner/Runner.csproj'
dotnet run --project $runner -- --stage2 $brief $layout $semantics
if ($LASTEXITCODE -ne 0) { throw "Stage 2 FittingPlacer generation failed ($LASTEXITCODE)." }
& $GodotExe --headless --path $project --import
if ($LASTEXITCODE -ne 0) { throw "Godot import failed ($LASTEXITCODE)." }
foreach ($view in @('top', 'hall_dining', 'hall_bar')) {
    $capture = Join-Path $project "screenshots/stage2-$Variant-$view.png"
    & $GodotExe --path $project res://preview.tscn -- "--stage2" "--view=$view" "--layout=stage2-$Variant-layout.json" "--capture=$capture"
    if ($LASTEXITCODE -ne 0) { throw "Godot $view capture failed ($LASTEXITCODE)." }
}

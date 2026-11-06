param(
    [Parameter(Mandatory = $true)][ValidateSet('A', 'B')][string]$Variant,
    [string]$GodotExe = (Get-Command Godot_v4.7.1-stable_win64_console.exe -ErrorAction Stop).Source
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path $PSScriptRoot).Path
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$env:APPDATA = Join-Path $repoRoot '.local/godot_user'
$solverRoot = Join-Path $repoRoot '.local/FittingPlacer'
$solverCommit = '1cdb703197b41d418e7ce686e74c7aad835ddb37'
if (-not (Test-Path (Join-Path $solverRoot 'Main'))) {
    New-Item -ItemType Directory -Force (Split-Path $solverRoot -Parent) | Out-Null
    git clone --no-checkout https://github.com/david-dot/FittingPlacer.git $solverRoot
    if ($LASTEXITCODE -ne 0) { throw 'Could not fetch the pinned FittingPlacer source.' }
}
git -C $solverRoot cat-file -e "$solverCommit^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
    git -C $solverRoot fetch origin $solverCommit
    if ($LASTEXITCODE -ne 0) { throw 'Could not fetch the pinned FittingPlacer commit.' }
}
git -C $solverRoot checkout --detach $solverCommit
if ($LASTEXITCODE -ne 0) { throw 'Could not select the pinned FittingPlacer commit.' }
$project = Join-Path $root 'godot_preview'
$brief = Join-Path $project "stage5-$Variant-brief.json"
$layout = Join-Path $project "stage5-$Variant-layout.json"
$runner = Join-Path $root 'runner/Runner.csproj'
$semantics = Join-Path $root 'tavern.xml'
$screenshots = Join-Path $project 'screenshots'
New-Item -ItemType Directory -Force $screenshots | Out-Null

dotnet run --project $runner -- --stage3 $brief $layout $semantics
if ($LASTEXITCODE -ne 0) { throw "Stage 5 FittingPlacer generation failed ($LASTEXITCODE)." }
& $GodotExe --headless --path $project --import
if ($LASTEXITCODE -ne 0) { throw "Godot import failed ($LASTEXITCODE)." }
foreach ($view in @('top','entrance','hall_dining','hall_bar','lounge','kitchen','storeroom')) {
    $capture = Join-Path $screenshots "stage5-$Variant-$view.png"
    & $GodotExe --path $project res://preview.tscn -- '--stage3' "--view=$view" "--layout=stage5-$Variant-layout.json" "--capture=$capture"
    if ($LASTEXITCODE -ne 0) { throw "Godot $view capture failed ($LASTEXITCODE)." }
}

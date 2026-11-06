param(
    [ValidateSet('A', 'B')][string]$Variant = 'B',
    [string]$SolverRoot
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$pipeline = Join-Path $repo 'experiments/layout_solvers/fittingplacer'
if (-not $SolverRoot) { $SolverRoot = Join-Path $repo '.local/FittingPlacer' }
if (-not (Test-Path (Join-Path $SolverRoot 'Main'))) {
    throw 'Run the existing generate_stage5.ps1 once to fetch the pinned solver, or pass -SolverRoot.'
}
$pinned = git -C $SolverRoot rev-parse HEAD
if ($pinned -ne '1cdb703197b41d418e7ce686e74c7aad835ddb37') { throw 'Expected the pinned FittingPlacer commit.' }
New-Item -ItemType Directory -Force (Join-Path $repo '.local') | Out-Null
$candidate = Join-Path $repo '.local/tavern-candidate.json'
dotnet run --project (Join-Path $pipeline 'runner/Runner.csproj') "-p:FittingPlacerRoot=$SolverRoot" -- --stage3 (Join-Path $pipeline "godot_preview/stage5-$Variant-brief.json") $candidate (Join-Path $pipeline 'tavern.xml')
if ($LASTEXITCODE -ne 0) { throw 'Tavern generation failed; playable layout was not replaced.' }
Copy-Item $candidate (Join-Path $repo 'data/room/tavern_generated.json')
Write-Output "Installed generated variant $Variant. Run the game with F5."

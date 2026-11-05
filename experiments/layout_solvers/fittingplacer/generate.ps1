param([int]$Seed = 4242)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$upstream = Join-Path $repoRoot '.local/FittingPlacer'
$expectedCommit = '1cdb703197b41d418e7ce686e74c7aad835ddb37'

if (-not (Test-Path (Join-Path $upstream '.git'))) {
    git clone https://github.com/david-dot/FittingPlacer.git $upstream
    if ($LASTEXITCODE -ne 0) { throw 'Could not clone upstream FittingPlacer.' }
}
$actualCommit = (git -C $upstream rev-parse HEAD).Trim()
if ($actualCommit -ne $expectedCommit) {
    git -C $upstream fetch --depth 1 origin $expectedCommit
    if ($LASTEXITCODE -ne 0) { throw 'Could not fetch the pinned FittingPlacer commit.' }
    git -C $upstream checkout --detach $expectedCommit
    if ($LASTEXITCODE -ne 0) { throw 'Could not select the pinned FittingPlacer commit.' }
}

$project = Join-Path $PSScriptRoot 'runner/Runner.csproj'
$inputXml = Join-Path $PSScriptRoot 'tavern.xml'
$outputJson = Join-Path $PSScriptRoot 'godot_preview/layout.json'
dotnet run --project $project -- $inputXml $outputJson $Seed
if ($LASTEXITCODE -ne 0) { throw "FittingPlacer generation failed with exit code $LASTEXITCODE." }

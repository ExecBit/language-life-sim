param(
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
    git -C $upstream fetch --depth 1 origin $expectedCommit
    if ($LASTEXITCODE -ne 0) { throw 'Could not fetch the pinned FittingPlacer revision.' }
    git -C $upstream checkout --detach $expectedCommit
    if ($LASTEXITCODE -ne 0) { throw 'Could not select the pinned FittingPlacer revision.' }
} else {
    Write-Host "Reusing existing ignored FittingPlacer checkout (expected pinned revision $expectedCommit)."
}
$project = Join-Path $root 'godot_preview'
$brief = Join-Path $project 'stage1_brief.json'
$layout = Join-Path $project 'stage1_layout.json'
$semantics = Join-Path $PSScriptRoot 'tavern.xml'
$runner = Join-Path $PSScriptRoot 'runner/Runner.csproj'
dotnet run --project $runner -- $brief $layout $semantics
if ($LASTEXITCODE -ne 0) { throw "Stage 1 FittingPlacer generation failed ($LASTEXITCODE)." }
& $GodotExe --headless --path $project --import
if ($LASTEXITCODE -ne 0) { throw "Godot import failed ($LASTEXITCODE)." }
foreach ($view in @('top', 'doorway')) {
    $capture = Join-Path $project "screenshots/stage1-$view.png"
    & $GodotExe --path $project res://preview.tscn -- "--stage1" "--view=$view" "--capture=$capture"
    if ($LASTEXITCODE -ne 0) { throw "Godot $view capture failed ($LASTEXITCODE)." }
}

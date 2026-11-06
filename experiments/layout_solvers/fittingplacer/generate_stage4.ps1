param(
    [Parameter(Mandatory = $true)][ValidateSet('A', 'B')][string]$Variant,
    [switch]$NegativeTest,
    [string]$GodotExe = (Get-Command Godot_v4.7.1-stable_win64_console.exe -ErrorAction Stop).Source
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path $PSScriptRoot).Path
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$env:APPDATA = Join-Path $repoRoot '.local/godot_user'
$project = Join-Path $root 'godot_preview'
$runner = Join-Path $root 'runner/Runner.csproj'
$semantics = Join-Path $root 'tavern.xml'
$brief = Join-Path $project "stage3-$Variant-brief.json"
$layout = Join-Path $project "stage4-$Variant-layout.json"
if ($NegativeTest) { dotnet run --project $runner -- --stage4-negative $brief $layout $semantics }
else { dotnet run --project $runner -- --stage4 $brief $layout $semantics }
if ($LASTEXITCODE -ne 0) { throw "Stage 4 validation failed ($LASTEXITCODE)." }
if ($NegativeTest) { exit 0 }
& $GodotExe --headless --path $project --import
if ($LASTEXITCODE -ne 0) { throw "Godot import failed ($LASTEXITCODE)." }
foreach ($view in @('top','entrance','hall_dining','hall_bar','hall_kitchen_doorway','lounge','kitchen_storeroom_doorway','storeroom')) {
    $capture = Join-Path $project "screenshots/stage4-$Variant-$view.png"
    & $GodotExe --path $project res://preview.tscn -- '--stage4' "--view=$view" "--layout=stage4-$Variant-layout.json" "--capture=$capture"
    if ($LASTEXITCODE -ne 0) { throw "Godot $view capture failed ($LASTEXITCODE)." }
}

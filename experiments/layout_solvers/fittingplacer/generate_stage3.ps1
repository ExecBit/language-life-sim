param(
    [Parameter(Mandatory = $true)][ValidateSet('A', 'B')][string]$Variant,
    [string]$GodotExe = (Get-Command Godot_v4.7.1-stable_win64_console.exe -ErrorAction Stop).Source
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path $PSScriptRoot).Path
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$env:APPDATA = Join-Path $repoRoot '.local/godot_user'
$project = Join-Path $root 'godot_preview'
$sourceFurniture = Join-Path $repoRoot 'assets/kaykit/furniture'
$previewAssets = Join-Path $project 'assets'
foreach ($asset in @('couch.gltf','couch.bin','cabinet_medium.gltf','cabinet_medium.bin','table_medium.gltf','table_medium.bin','furniturebits_texture.png')) {
    Copy-Item -LiteralPath (Join-Path $sourceFurniture $asset) -Destination $previewAssets -Force
}
Copy-Item -LiteralPath (Join-Path $sourceFurniture 'LICENSE.txt') -Destination (Join-Path $previewAssets 'FURNITURE_LICENSE.txt') -Force
$brief = Join-Path $project "stage3-$Variant-brief.json"
$layout = Join-Path $project "stage3-$Variant-layout.json"
$runner = Join-Path $root 'runner/Runner.csproj'
$semantics = Join-Path $root 'tavern.xml'
dotnet run --project $runner -- --stage3 $brief $layout $semantics
if ($LASTEXITCODE -ne 0) { throw "Stage 3 FittingPlacer generation failed ($LASTEXITCODE)." }
& $GodotExe --headless --path $project --import
if ($LASTEXITCODE -ne 0) { throw "Godot import failed ($LASTEXITCODE)." }
foreach ($view in @('top','hall_overview','hall_dining','hall_bar','lounge','kitchen_storeroom_doorway','storeroom')) {
    $capture = Join-Path $project "screenshots/stage3-$Variant-$view.png"
    & $GodotExe --path $project res://preview.tscn -- '--stage3' "--view=$view" "--layout=stage3-$Variant-layout.json" "--capture=$capture"
    if ($LASTEXITCODE -ne 0) { throw "Godot $view capture failed ($LASTEXITCODE)." }
}

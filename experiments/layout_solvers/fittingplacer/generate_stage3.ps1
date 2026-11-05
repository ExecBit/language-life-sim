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
$sourceFurniture = Join-Path $repoRoot 'assets/kaykit/furniture'
$previewAssets = Join-Path $project 'assets'
foreach ($asset in @('couch.gltf','couch.bin','cabinet_medium.gltf','cabinet_medium.bin','table_medium.gltf','table_medium.bin','furniturebits_texture.png')) {
    Copy-Item -LiteralPath (Join-Path $sourceFurniture $asset) -Destination $previewAssets -Force
}
$furnitureLicense = Join-Path $previewAssets 'FURNITURE_LICENSE.txt'
Copy-Item -LiteralPath (Join-Path $sourceFurniture 'LICENSE.txt') -Destination $furnitureLicense -Force
$licenseLines = [IO.File]::ReadAllLines($furnitureLicense) | ForEach-Object { $_.TrimEnd() }
[IO.File]::WriteAllText($furnitureLicense, (($licenseLines -join "`n").TrimEnd() + "`n"), [Text.UTF8Encoding]::new($false))
$brief = Join-Path $project "stage4-$Variant-brief.json"
$layout = Join-Path $project "stage4-$Variant-layout.json"
$runner = Join-Path $root 'runner/Runner.csproj'
$semantics = Join-Path $root 'tavern.xml'
if ($NegativeTest) { $env:STAGE4_BLOCK_SERVICE_DOOR = '1' }
try { dotnet run --project $runner -- --stage4 $brief $layout $semantics }
finally { Remove-Item Env:STAGE4_BLOCK_SERVICE_DOOR -ErrorAction SilentlyContinue }
if ($NegativeTest) {
    if ($LASTEXITCODE -eq 0) { throw 'Stage 4 negative test unexpectedly succeeded.' }
    Write-Host 'STAGE4 NEGATIVE TEST PASS: blocked doorway rejected with diagnostic.'
    exit 0
}
if ($LASTEXITCODE -ne 0) { throw "Stage 4 FittingPlacer generation failed ($LASTEXITCODE)." }
& $GodotExe --headless --path $project --import
if ($LASTEXITCODE -ne 0) { throw "Godot import failed ($LASTEXITCODE)." }
foreach ($view in @('top','entrance','hall_dining','hall_bar','hall_kitchen_doorway','lounge','kitchen_storeroom_doorway','storeroom')) {
    $capture = Join-Path $project "screenshots/stage4-$Variant-$view.png"
    & $GodotExe --path $project res://preview.tscn -- '--stage4' "--view=$view" "--layout=stage4-$Variant-layout.json" "--capture=$capture"
    if ($LASTEXITCODE -ne 0) { throw "Godot $view capture failed ($LASTEXITCODE)." }
}

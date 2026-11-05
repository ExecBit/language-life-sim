param(
    [string]$GodotExe = (Get-Command Godot_v4.7.1-stable_win64_console.exe -ErrorAction Stop).Source
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$godotProject = Join-Path $PSScriptRoot 'godot_preview'
$screenshots = Join-Path $godotProject 'screenshots'
$localAppData = Join-Path $repoRoot '.local/godot_user'
New-Item -ItemType Directory -Force $screenshots, $localAppData | Out-Null
$env:APPDATA = $localAppData

& (Join-Path $PSScriptRoot 'generate.ps1')
if ($LASTEXITCODE -ne 0) { throw 'FittingPlacer generation failed.' }

& $GodotExe --headless --editor --path $godotProject --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot 4.7.1 asset import failed.' }

foreach ($view in @('top', 'entrance', 'bar', 'dining', 'kitchen')) {
    $capture = Join-Path $screenshots "$view.png"
    & $GodotExe --path $godotProject --scene res://preview.tscn -- "--view=$view" "--capture=$capture"
    if ($LASTEXITCODE -ne 0) { throw "Godot capture failed for view '$view'." }
}

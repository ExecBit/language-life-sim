param(
    [string]$GodotExe = (Get-Command Godot_v4.7.1-stable_win64_console.exe -ErrorAction Stop).Source,
    [int[]]$Seeds = @(4242, 8675309)
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$godotProject = Join-Path $PSScriptRoot 'godot_preview'
$screenshots = Join-Path $godotProject 'screenshots'
$localAppData = Join-Path $repoRoot '.local/godot_user'
New-Item -ItemType Directory -Force $screenshots, $localAppData | Out-Null
$env:APPDATA = $localAppData

foreach ($seed in $Seeds) {
    & (Join-Path $PSScriptRoot 'generate.ps1') $seed
    if ($LASTEXITCODE -ne 0) { throw "FittingPlacer generation failed for seed $seed." }

    foreach ($view in @('top', 'entrance', 'kitchen')) {
        $capture = Join-Path $screenshots "$seed-$view.png"
        & $GodotExe --path $godotProject --scene res://preview.tscn -- "--view=$view" "--capture=$capture"
        if ($LASTEXITCODE -ne 0) { throw "Godot capture failed for seed $seed view '$view'." }
    }
}

if ($Seeds -contains 4242) {
    & (Join-Path $PSScriptRoot 'generate.ps1') 4242
    if ($LASTEXITCODE -ne 0) { throw 'Could not restore the seed 4242 preview layout.' }
}

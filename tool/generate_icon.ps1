$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectRoot 'assets\brand\app-icon.ico'
$destination = Join-Path $projectRoot 'windows\runner\resources\app_icon.ico'
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw 'The approved NearLink app icon is missing from assets/brand.'
}
Copy-Item -LiteralPath $source -Destination $destination -Force
Write-Output 'NearLink N logo synchronized to the Windows app and tray icon.'

param([string]$Version = '0.2.5')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path -LiteralPath (Join-Path $source 'mutual_transfer.exe'))) {
    throw 'Build the Windows Release application first.'
}
$packageName = "NearLink-$Version-windows-x64"
$outputRoot = Join-Path $projectRoot 'outputs'
$destination = Join-Path $outputRoot $packageName
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Get-ChildItem -LiteralPath $source | Where-Object { $_.Extension -ne '.pdb' } | Copy-Item -Destination $destination -Recurse -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md'), (Join-Path $projectRoot 'DESIGN.md'), (Join-Path $projectRoot 'PRODUCT.md') -Destination $destination -Force
$packageDocs = Join-Path $destination 'docs'
New-Item -ItemType Directory -Path $packageDocs -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\PROTOCOL.md') -Destination $packageDocs -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\PERFORMANCE.md') -Destination $packageDocs -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\INSTALLATION.md') -Destination $packageDocs -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\NETWORK_TROUBLESHOOTING.md') -Destination $packageDocs -Force
$notificationLicense = Join-Path $destination 'licenses\flutter_local_notifications_windows'
New-Item -ItemType Directory -Path $notificationLicense -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'third_party\flutter_local_notifications_windows\LICENSE') -Destination $notificationLicense -Force
$iconLicense = Join-Path $destination 'licenses\lucide_icons_flutter'
New-Item -ItemType Directory -Path $iconLicense -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'windows\runner\resources\lucide-LICENSE') -Destination (Join-Path $iconLicense 'LICENSE') -Force
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path -LiteralPath $vswhere) {
    $installation = & $vswhere -latest -products '*' -property installationPath
    if ($installation) {
        $redistRoot = Join-Path $installation 'VC\Redist\MSVC'
        $crt = Get-ChildItem -LiteralPath $redistRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | ForEach-Object {
            Get-ChildItem -Path (Join-Path $_.FullName 'x64\Microsoft.VC*.CRT') -Directory -ErrorAction SilentlyContinue
        } | Select-Object -First 1
        if ($crt) {
            Get-ChildItem -LiteralPath $crt.FullName -Filter '*.dll' | Copy-Item -Destination $destination -Force
        }
    }
}
$archivePath = Join-Path $outputRoot "$packageName.zip"
Compress-Archive -LiteralPath $destination -DestinationPath $archivePath -Force
Write-Output $destination
Write-Output $archivePath

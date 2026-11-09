param([string]$Flutter = 'D:\uad360\flutter\flutter_runtime_sdk\bin\flutter.bat')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sdkRoot = Join-Path $projectRoot 'build\android-tools\sdk'
$javaRoot = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'build\android-tools') -Directory -Filter 'jdk-*' |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $javaRoot -or -not (Test-Path -LiteralPath (Join-Path $sdkRoot 'platform-tools\adb.exe'))) {
    throw 'Run tool/prepare_android.ps1 first.'
}
$env:JAVA_HOME = $javaRoot
$env:ANDROID_HOME = $sdkRoot
$env:ANDROID_SDK_ROOT = $sdkRoot
# A nonexistent Unix-socket directory makes Java fall back to TCP on this host.
$env:JAVA_TOOL_OPTIONS = (($env:JAVA_TOOL_OPTIONS, '-Djdk.net.unixdomain.tmpdir=./.nearlink-tcp-only') -join ' ').Trim()
Push-Location $projectRoot
try {
    & $Flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }
    $version = ((Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:\s*(.+)$').Matches.Groups[1].Value -split '\+')[0]
    $destination = Join-Path $projectRoot "outputs\NearLink-$version-android-preview.apk"
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath 'build\app\outputs\flutter-apk\app-release.apk' -Destination $destination -Force
    Get-FileHash -LiteralPath $destination -Algorithm SHA256
} finally { Pop-Location }

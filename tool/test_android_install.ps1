$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sdkRoot = Join-Path $projectRoot 'build\android-tools\sdk'
$javaRoot = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'build\android-tools') -Directory -Filter 'jdk-*' |
    Select-Object -First 1 -ExpandProperty FullName
if (!$javaRoot -or !(Test-Path -LiteralPath $sdkRoot)) {
    throw 'Run tool/prepare_android.ps1 first.'
}
$env:JAVA_HOME = $javaRoot
$env:ANDROID_HOME = $sdkRoot
$env:ANDROID_SDK_ROOT = $sdkRoot
$env:JAVA_TOOL_OPTIONS = (($env:JAVA_TOOL_OPTIONS, '-Djdk.net.unixdomain.tmpdir=./.nearlink-tcp-only') -join ' ').Trim()
Push-Location (Join-Path $projectRoot 'android')
try {
    & '.\gradlew.bat' ':app:testDebugUnitTest' '--console=plain'
    if ($LASTEXITCODE -ne 0) { throw 'Android installer unit tests failed.' }
} finally { Pop-Location }

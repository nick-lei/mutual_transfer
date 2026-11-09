param([switch]$WithEmulator)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolsRoot = Join-Path $projectRoot 'build\android-tools'
$sdkRoot = Join-Path $toolsRoot 'sdk'
New-Item -ItemType Directory -Path $toolsRoot, $sdkRoot -Force | Out-Null

function Get-VerifiedArchive($Url, $Path, $Checksum, $Algorithm) {
    if (-not (Test-Path -LiteralPath $Path) -or
        (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash -ne $Checksum) {
        & curl.exe --fail --location --silent --show-error --retry 3 --retry-all-errors --connect-timeout 30 --output $Path $Url
        if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url" }
    }
    if ((Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash -ne $Checksum) {
        throw "Archive checksum mismatch: $Path"
    }
}

$javaHome = Get-ChildItem -LiteralPath $toolsRoot -Directory -Filter 'jdk-*' | Select-Object -First 1 -ExpandProperty FullName
if (-not $javaHome) {
    $jdkUrl = 'https://aka.ms/download-jdk/microsoft-jdk-21-windows-x64.zip'
    $checksumContent = (Invoke-WebRequest -UseBasicParsing "$jdkUrl.sha256sum.txt").Content
    if ($checksumContent -is [byte[]]) { $checksumContent = [Text.Encoding]::UTF8.GetString($checksumContent) }
    $jdkChecksum = ($checksumContent.Trim() -split '\s+')[0]
    $archive = Join-Path $toolsRoot 'jdk.zip'
    Get-VerifiedArchive $jdkUrl $archive $jdkChecksum 'SHA256'
    Expand-Archive -LiteralPath $archive -DestinationPath $toolsRoot -Force
    $javaHome = Get-ChildItem -LiteralPath $toolsRoot -Directory -Filter 'jdk-*' | Select-Object -First 1 -ExpandProperty FullName
}
$env:JAVA_HOME = $javaHome
$env:ANDROID_HOME = $sdkRoot
$env:ANDROID_SDK_ROOT = $sdkRoot
$env:JAVA_TOOL_OPTIONS = (($env:JAVA_TOOL_OPTIONS, '-Djdk.net.unixdomain.tmpdir=./.nearlink-tcp-only') -join ' ').Trim()
$sdkManager = Join-Path $sdkRoot 'cmdline-tools\19.0\bin\sdkmanager.bat'
if (-not (Test-Path -LiteralPath $sdkManager)) {
    [xml]$repository = (Invoke-WebRequest -UseBasicParsing 'https://dl.google.com/android/repository/repository2-1.xml').Content
    $archiveNode = $repository.SelectNodes("//*[local-name()='remotePackage' and @path='cmdline-tools;19.0']/*[local-name()='archives']/*[local-name()='archive']") |
        Where-Object { $_.'host-os' -eq 'windows' } | Select-Object -First 1
    $url = 'https://dl.google.com/android/repository/' + [string]$archiveNode.complete.url
    $archive = Join-Path $toolsRoot 'commandline-tools-19.zip'
    Get-VerifiedArchive $url $archive ([string]$archiveNode.complete.checksum) 'SHA1'
    $expanded = Join-Path $toolsRoot 'commandline-19-expanded'
    Expand-Archive -LiteralPath $archive -DestinationPath $expanded -Force
    New-Item -ItemType Directory -Path (Join-Path $sdkRoot 'cmdline-tools') -Force | Out-Null
    Move-Item -LiteralPath (Join-Path $expanded 'cmdline-tools') -Destination (Join-Path $sdkRoot 'cmdline-tools\19.0')
}
1..120 | ForEach-Object { 'y' } | & $sdkManager "--sdk_root=$sdkRoot" --licenses
& $sdkManager "--sdk_root=$sdkRoot" 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' 'ndk;28.2.13676358'
if ($LASTEXITCODE -ne 0) { throw 'Android SDK package installation failed.' }
if ($WithEmulator) {
    & $sdkManager "--sdk_root=$sdkRoot" 'emulator' 'system-images;android-35;google_apis;x86_64'
    if ($LASTEXITCODE -ne 0) { throw 'Android emulator installation failed.' }
}
[PSCustomObject]@{ sdkRoot = $sdkRoot; javaHome = $javaHome } | ConvertTo-Json

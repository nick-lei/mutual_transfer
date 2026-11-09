param(
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version = '0.2.5',
    [string]$PackageDirectory,
    [string]$CompilerPath,
    [switch]$PrepareCompiler
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $PackageDirectory) {
    $PackageDirectory = Join-Path $projectRoot "outputs\NearLink-$Version-windows-x64"
}
$PackageDirectory = (Resolve-Path -LiteralPath $PackageDirectory).Path
foreach ($file in @(
    'mutual_transfer.exe', 'flutter_windows.dll',
    'flutter_local_notifications_windows.dll', 'data\app.so', 'data\icudtl.dat',
    'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll',
    'data\flutter_assets\windows\runner\resources\app_icon.ico'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $PackageDirectory $file))) {
        throw "Missing installer payload: $file. Run tool/package_windows.ps1 after building Release."
    }
}
$binaryVersion = (Get-Item -LiteralPath (Join-Path $PackageDirectory 'mutual_transfer.exe')).VersionInfo.ProductVersion
if ($binaryVersion -notmatch ('^' + [Regex]::Escape($Version) + '(\+|$)')) {
    throw "Payload version $binaryVersion does not match requested installer version $Version."
}
$releaseDirectory = Join-Path $projectRoot 'build\windows\x64\runner\Release'
foreach ($file in @('mutual_transfer.exe', 'data\app.so')) {
    $releaseFile = Join-Path $releaseDirectory $file
    if ((Test-Path -LiteralPath $releaseFile) -and
        (Get-FileHash -LiteralPath $releaseFile -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $PackageDirectory $file) -Algorithm SHA256).Hash) {
        throw "Installer payload differs from the latest Release build: $file. Rerun tool/package_windows.ps1."
    }
}
if (-not $CompilerPath) {
    $candidates = @(
        (Join-Path $projectRoot 'build\installer-tools\inno-7.1.1\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe')
    )
    $CompilerPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $CompilerPath) {
        $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
        if ($command) { $CompilerPath = $command.Source }
    }
    if (-not $CompilerPath -and $PrepareCompiler) {
        $CompilerPath = & (Join-Path $PSScriptRoot 'prepare_installer.ps1')
    }
}
if (-not $CompilerPath) {
    throw 'Inno Setup 7 was not found. Rerun with -PrepareCompiler or provide -CompilerPath.'
}
$outputDirectory = Join-Path $projectRoot 'outputs'
& $CompilerPath '/Qp' "/DAppVersion=$Version" "/DPackageDirectory=$PackageDirectory" "/DOutputDirectory=$outputDirectory" (Join-Path $projectRoot 'windows\installer\nearlink.iss')
if ($LASTEXITCODE -ne 0) { throw "Installer compilation failed with exit code $LASTEXITCODE." }
$setup = Join-Path $outputDirectory "NearLink-$Version-windows-x64-Setup.exe"
if (-not (Test-Path -LiteralPath $setup)) { throw 'Installer output was not generated.' }
Write-Output $setup
Get-FileHash -LiteralPath $setup -Algorithm SHA256 | Format-List

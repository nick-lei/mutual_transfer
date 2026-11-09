param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$compilerVersion = '7.1.1'
$compilerHash = '8A5A6711C3766A6E5FB74F280BA0E3551E719CE94538D901FDBD1F8F9920B3F0'
$cache = Join-Path $projectRoot 'build\installer-tools'
$compilerDirectory = Join-Path $cache "inno-$compilerVersion"
$compilerPath = Join-Path $compilerDirectory 'ISCC.exe'
if (Test-Path -LiteralPath $compilerPath) {
    Write-Output $compilerPath
    return
}
New-Item -ItemType Directory -Path $cache -Force | Out-Null
$installer = Join-Path $cache "innosetup-$compilerVersion-x64.exe"
if (-not (Test-Path -LiteralPath $installer)) {
    Invoke-WebRequest -Uri "https://github.com/jrsoftware/issrc/releases/download/is-7_1_1/innosetup-$compilerVersion-x64.exe" -OutFile $installer
}
if ((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash -ne $compilerHash) {
    throw 'Inno Setup download checksum mismatch. Remove the cached download and retry.'
}
if ((Get-AuthenticodeSignature -LiteralPath $installer).Status -ne 'Valid') {
    throw 'Inno Setup compiler download has no valid Authenticode signature.'
}
$process = Start-Process -FilePath $installer -ArgumentList @(
    '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER', '/NOICONS', '/TASKS=',
    "/DIR=`"$compilerDirectory`"", "/LOG=`"$(Join-Path $cache 'compiler-install.log')`""
) -WindowStyle Hidden -Wait -PassThru
if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $compilerPath)) {
    throw "Inno Setup compiler preparation failed with exit code $($process.ExitCode)."
}
Write-Output $compilerPath

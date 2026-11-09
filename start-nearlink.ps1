$ErrorActionPreference = 'Stop'
$portable = Join-Path $PSScriptRoot 'outputs\NearLink-0.1.0-windows-x64\mutual_transfer.exe'
$release = Join-Path $PSScriptRoot 'build\windows\x64\runner\Release\mutual_transfer.exe'
$executable = if (Test-Path -LiteralPath $portable) { $portable } else { $release }
if (-not (Test-Path -LiteralPath $executable)) {
    throw 'Build the application with flutter build windows --release first.'
}
Start-Process -FilePath $executable -WorkingDirectory (Split-Path -Parent $executable) -WindowStyle Hidden

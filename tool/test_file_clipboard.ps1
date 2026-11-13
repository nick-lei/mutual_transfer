param([string]$Configuration = 'Release')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildDirectory = Join-Path $projectRoot 'build\windows\x64'
$cache = Join-Path $buildDirectory 'CMakeCache.txt'
if (!(Test-Path -LiteralPath $cache)) {
    throw 'Configure the Windows application with flutter build windows first.'
}
$match = Select-String -LiteralPath $cache -Pattern '^CMAKE_COMMAND:INTERNAL=(.+)$'
if (!$match) { throw 'The configured CMake executable was not found.' }
$cmake = $match.Matches.Groups[1].Value
& $cmake -S (Join-Path $projectRoot 'windows') -B $buildDirectory
if ($LASTEXITCODE -ne 0) { throw 'Windows test configuration failed.' }
& $cmake --build $buildDirectory --config $Configuration --target nearlink_file_clipboard_test
if ($LASTEXITCODE -ne 0) { throw 'Native clipboard test build failed.' }
& (Join-Path $buildDirectory "clipboard_tests\$Configuration\nearlink_file_clipboard_test.exe")
if ($LASTEXITCODE -ne 0) { throw 'Native clipboard verification failed.' }

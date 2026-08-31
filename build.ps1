# Configure + build Pootis Builder with the Qt-bundled MinGW/CMake/Ninja toolchain.
$ErrorActionPreference = "Stop"

$mingw = "C:\Qt\Tools\mingw1310_64\bin"
$cmakeDir = "C:\Qt\Tools\CMake_64\bin"
$ninjaDir = "C:\Qt\Tools\Ninja"
$env:Path = "$mingw;$cmakeDir;$ninjaDir;$env:Path"

$src = $PSScriptRoot
$build = Join-Path $src "build"

$config = if ($args.Count -ge 1) { $args[0] } else { "Release" }

& cmake -S $src -B $build -G Ninja `
    -DCMAKE_BUILD_TYPE=$config `
    -DCMAKE_C_COMPILER=gcc `
    -DCMAKE_CXX_COMPILER=g++
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }

& cmake --build $build --parallel
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }

Write-Host "`nBuilt: $build\PootisBuilder.exe" -ForegroundColor Green

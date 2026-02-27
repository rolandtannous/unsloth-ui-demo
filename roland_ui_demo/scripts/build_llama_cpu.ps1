#Requires -Version 5.1
<#
.SYNOPSIS
    CPU-only llama.cpp build -- for timing comparison against CUDA build.
.DESCRIPTION
    Forces CPU-only build (-DGGML_CUDA=OFF) and measures elapsed time
    for each phase (clone, configure, build). Use -Clean to wipe and rebuild.
.NOTES
    Usage: powershell -ExecutionPolicy Bypass -File build_llama_cpu.ps1
    Optional: -Clean to wipe build dir and rebuild from scratch
#>
param(
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "+==============================================+" -ForegroundColor Cyan
Write-Host "|   llama.cpp CPU-ONLY Build (Timed)           |" -ForegroundColor Cyan
Write-Host "+==============================================+" -ForegroundColor Cyan
Write-Host ""

# ─────────────────────────────────────────────
# Paths
# ─────────────────────────────────────────────
$LlamaCppDir = Join-Path $env:USERPROFILE ".unsloth\llama.cpp-cpu"
$BuildDir = Join-Path $LlamaCppDir "build"
$LlamaServerBin = Join-Path $BuildDir "bin\Release\llama-server.exe"

if ($Clean -and (Test-Path $BuildDir)) {
    Write-Host "[CLEAN] Removing build directory..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $BuildDir
    Write-Host "[OK] Build directory removed" -ForegroundColor Green
    Write-Host ""
}

# ─────────────────────────────────────────────
# Preflight
# ─────────────────────────────────────────────
Write-Host "--- Preflight Checks ---" -ForegroundColor Cyan

$HasGit = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
if (-not $HasGit) { Write-Host "[ERROR] git not found." -ForegroundColor Red; exit 1 }
Write-Host "[OK] git: $(git --version)" -ForegroundColor Green

$HasCmake = $null -ne (Get-Command cmake -ErrorAction SilentlyContinue)
if (-not $HasCmake) { Write-Host "[ERROR] cmake not found." -ForegroundColor Red; exit 1 }
Write-Host "[OK] cmake: $(cmake --version | Select-Object -First 1)" -ForegroundColor Green

# Visual Studio / Build Tools (cl.exe) -- needed for cmake to find a C/C++ compiler
$HasCl = $null -ne (Get-Command cl -ErrorAction SilentlyContinue)
if (-not $HasCl) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -property installationPath 2>$null
        if ($vsPath) {
            $vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
            if (Test-Path $vcvars) {
                Write-Host "   Loading Visual Studio environment..." -ForegroundColor Gray
                $envOutput = cmd /c "`"$vcvars`" >nul 2>&1 && set" 2>$null
                foreach ($line in $envOutput) {
                    if ($line -match '^([^=]+)=(.*)$') {
                        [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
                    }
                }
                $HasCl = $null -ne (Get-Command cl -ErrorAction SilentlyContinue)
            }
        }
    }
}
if ($HasCl) {
    Write-Host "[OK] C++ compiler (cl.exe) available" -ForegroundColor Green
} else {
    Write-Host "[WARN] cl.exe not found -- cmake will try its default generator" -ForegroundColor Yellow
    Write-Host "       If build fails, install Visual Studio Build Tools:" -ForegroundColor Yellow
    Write-Host "       winget install Microsoft.VisualStudio.2022.BuildTools" -ForegroundColor Yellow
}

$NumCpu = [Environment]::ProcessorCount
if ($NumCpu -lt 1) { $NumCpu = 4 }
Write-Host "[OK] CPU cores: $NumCpu" -ForegroundColor Green
Write-Host ""

# Lower for native commands
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"

# Total timer
$totalSw = [System.Diagnostics.Stopwatch]::StartNew()

# ─────────────────────────────────────────────
# Clone / update
# ─────────────────────────────────────────────
Write-Host "--- Source ---" -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$UnslothDir = Join-Path $env:USERPROFILE ".unsloth"
if (-not (Test-Path $UnslothDir)) { New-Item -ItemType Directory -Path $UnslothDir -Force | Out-Null }

if (Test-Path (Join-Path $LlamaCppDir ".git")) {
    Write-Host "   llama.cpp already cloned, pulling latest..." -ForegroundColor Gray
    git -C $LlamaCppDir pull
} else {
    if (Test-Path $LlamaCppDir) { Remove-Item -Recurse -Force $LlamaCppDir }
    Write-Host "   Cloning llama.cpp..." -ForegroundColor Gray
    git clone --depth 1 https://github.com/ggml-org/llama.cpp.git $LlamaCppDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] git clone failed" -ForegroundColor Red
        exit 1
    }
}

$sw.Stop()
Write-Host "[OK] Source ready ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -ForegroundColor Green
Write-Host ""

# ─────────────────────────────────────────────
# cmake configure (CPU-only)
# ─────────────────────────────────────────────
Write-Host "--- cmake configure (CPU-only) ---" -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$CmakeArgs = @(
    '-S', $LlamaCppDir,
    '-B', $BuildDir,
    '-DBUILD_SHARED_LIBS=OFF',
    '-DGGML_CUDA=OFF'
)

Write-Host "   cmake args:" -ForegroundColor Gray
foreach ($arg in $CmakeArgs) { Write-Host "     $arg" -ForegroundColor Gray }
Write-Host ""

cmake @CmakeArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAILED] cmake configure failed (exit $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

$sw.Stop()
Write-Host ""
Write-Host "[OK] cmake configure ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -ForegroundColor Green
Write-Host ""

# ─────────────────────────────────────────────
# cmake build -- llama-server
# ─────────────────────────────────────────────
Write-Host "--- cmake build (llama-server, CPU-only) ---" -ForegroundColor Cyan
Write-Host "   Parallel jobs: $NumCpu" -ForegroundColor Gray
Write-Host ""

$sw = [System.Diagnostics.Stopwatch]::StartNew()

cmake --build $BuildDir --config Release --target llama-server -j $NumCpu
$buildExit = $LASTEXITCODE

$sw.Stop()

if ($buildExit -ne 0) {
    Write-Host ""
    Write-Host "[FAILED] llama-server build failed (exit $buildExit) after $([math]::Round($sw.Elapsed.TotalSeconds, 1))s" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[OK] llama-server build ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -ForegroundColor Green

# ─────────────────────────────────────────────
# cmake build -- llama-quantize
# ─────────────────────────────────────────────
Write-Host ""
Write-Host "--- cmake build (llama-quantize) ---" -ForegroundColor Cyan

$sw = [System.Diagnostics.Stopwatch]::StartNew()

cmake --build $BuildDir --config Release --target llama-quantize -j $NumCpu
$qExit = $LASTEXITCODE

$sw.Stop()

if ($qExit -ne 0) {
    Write-Host "[WARN] llama-quantize build failed ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -ForegroundColor Yellow
} else {
    Write-Host "[OK] llama-quantize build ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -ForegroundColor Green
}

# Restore
$ErrorActionPreference = $prevEAP

# ─────────────────────────────────────────────
# Total time
# ─────────────────────────────────────────────
$totalSw.Stop()
$totalMin = [math]::Floor($totalSw.Elapsed.TotalMinutes)
$totalSec = [math]::Round($totalSw.Elapsed.TotalSeconds % 60, 1)

Write-Host ""
Write-Host "+==============================================+" -ForegroundColor Green
Write-Host "|             Build Complete!                   |" -ForegroundColor Green
Write-Host "+==============================================+" -ForegroundColor Green
Write-Host ""

if (Test-Path $LlamaServerBin) {
    Write-Host "[OK] llama-server: $LlamaServerBin" -ForegroundColor Green
} else {
    $altBin = Join-Path $BuildDir "bin\llama-server.exe"
    if (Test-Path $altBin) {
        Write-Host "[OK] llama-server: $altBin" -ForegroundColor Green
    } else {
        Write-Host "[WARN] llama-server.exe not found at expected path" -ForegroundColor Yellow
        $found = Get-ChildItem -Recurse -Filter "llama-server.exe" $BuildDir -ErrorAction SilentlyContinue
        if ($found) { foreach ($f in $found) { Write-Host "       Found: $($f.FullName)" -ForegroundColor Green } }
    }
}

Write-Host ""
Write-Host "   Build type: CPU-only" -ForegroundColor Yellow
Write-Host "   Total time: ${totalMin}m ${totalSec}s" -ForegroundColor Cyan
Write-Host ""

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

# Visual Studio / Build Tools -- detect for cmake -G flag
# Strategy: (1) try vswhere, (2) fall back to scanning known filesystem paths
$CmakeGenerator = $null
$VsInstallPath = $null
$vsGeneratorMap = @{ '2022' = '17'; '2019' = '16'; '2017' = '15' }

# --- Method 1: vswhere (works when VS is properly registered) ---
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsInfo = & $vswhere -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property catalog_productLineVersion 2>$null
    $vsInstPath = & $vswhere -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($vsInfo -and $vsInstPath) {
        $vsYear = $vsInfo.Trim()
        $vsNum = $vsGeneratorMap[$vsYear]
        if ($vsNum) {
            $CmakeGenerator = "Visual Studio $vsNum $vsYear"
            $VsInstallPath = $vsInstPath.Trim()
            Write-Host "[OK] Visual Studio $vsYear detected via vswhere" -ForegroundColor Green
        }
    }
}

# --- Method 2: Scan filesystem (handles broken vswhere registration) ---
if (-not $CmakeGenerator) {
    Write-Host "   vswhere did not find VS -- scanning filesystem..." -ForegroundColor Gray
    $searchRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
    $editions = @('BuildTools', 'Community', 'Professional', 'Enterprise')
    $years = @('2022', '2019', '2017')  # newest first

    foreach ($year in $years) {
        foreach ($root in $searchRoots) {
            foreach ($edition in $editions) {
                $candidatePath = Join-Path $root "Microsoft Visual Studio\$year\$edition"
                if (Test-Path $candidatePath) {
                    # Verify cl.exe actually exists (proves C++ tools are installed)
                    $clSearch = Join-Path $candidatePath "VC\Tools\MSVC"
                    if (Test-Path $clSearch) {
                        $clExe = Get-ChildItem -Path $clSearch -Filter "cl.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($clExe) {
                            $vsNum = $vsGeneratorMap[$year]
                            if ($vsNum) {
                                $CmakeGenerator = "Visual Studio $vsNum $year"
                                $VsInstallPath = $candidatePath
                                Write-Host "[OK] Visual Studio $year ($edition) found at $candidatePath" -ForegroundColor Green
                                Write-Host "   cl.exe: $($clExe.FullName)" -ForegroundColor Gray
                                break
                            }
                        }
                    }
                }
            }
            if ($CmakeGenerator) { break }
        }
        if ($CmakeGenerator) { break }
    }
}

if (-not $CmakeGenerator) {
    Write-Host "[ERROR] Visual Studio Build Tools not found." -ForegroundColor Red
    Write-Host "        Install with:" -ForegroundColor Red
    Write-Host '        winget install Microsoft.VisualStudio.2022.BuildTools --override "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive"' -ForegroundColor Yellow
    exit 1
}
Write-Host "   cmake generator: $CmakeGenerator" -ForegroundColor Gray

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
    '-G', $CmakeGenerator
)
# Tell cmake exactly where VS is (bypasses registry lookup)
if ($VsInstallPath) {
    $CmakeArgs += "-DCMAKE_GENERATOR_INSTANCE=$VsInstallPath"
}
$CmakeArgs += '-DBUILD_SHARED_LIBS=OFF'
$CmakeArgs += '-DGGML_CUDA=OFF'

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

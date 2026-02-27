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
# Strategy: (1) vswhere, (2) scan filesystem, (3) auto-install, (4) re-scan
$CmakeGenerator = $null
$VsInstallPath = $null
$vsGeneratorMap = @{ '2022' = '17'; '2019' = '16'; '2017' = '15' }

# Scans known VS installation directories for cl.exe.
# Returns @{ Generator = "Visual Studio 17 2022"; InstallPath = "C:\..." } or $null.
function Find-VsBuildTools {
    $map = @{ '2022' = '17'; '2019' = '16'; '2017' = '15' }

    # --- Try vswhere first (works when VS is properly registered) ---
    $vsw = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vsw) {
        $info = & $vsw -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property catalog_productLineVersion 2>$null
        $path = & $vsw -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
        if ($info -and $path) {
            $y = $info.Trim()
            $n = $map[$y]
            if ($n) {
                return @{ Generator = "Visual Studio $n $y"; InstallPath = $path.Trim(); Source = 'vswhere' }
            }
        }
    }

    # --- Scan filesystem (handles broken vswhere registration) ---
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
    $editions = @('BuildTools', 'Community', 'Professional', 'Enterprise')
    $years = @('2022', '2019', '2017')

    foreach ($y in $years) {
        foreach ($r in $roots) {
            foreach ($ed in $editions) {
                $candidate = Join-Path $r "Microsoft Visual Studio\$y\$ed"
                if (Test-Path $candidate) {
                    $vcDir = Join-Path $candidate "VC\Tools\MSVC"
                    if (Test-Path $vcDir) {
                        $cl = Get-ChildItem -Path $vcDir -Filter "cl.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($cl) {
                            $n = $map[$y]
                            if ($n) {
                                return @{ Generator = "Visual Studio $n $y"; InstallPath = $candidate; Source = "filesystem ($ed)"; ClExe = $cl.FullName }
                            }
                        }
                    }
                }
            }
        }
    }

    return $null
}

$vsResult = Find-VsBuildTools

# --- Auto-install if not found ---
if (-not $vsResult) {
    Write-Host "   Visual Studio Build Tools not found -- installing via winget..." -ForegroundColor Yellow
    Write-Host "   (This is a one-time install, may take several minutes)" -ForegroundColor Gray
    $HasWinget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
    if ($HasWinget) {
        $prevEAPTemp = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        winget install Microsoft.VisualStudio.2022.BuildTools --source winget --accept-package-agreements --accept-source-agreements --override "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --wait"
        $ErrorActionPreference = $prevEAPTemp
        # Re-scan filesystem after install (don't trust vswhere catalog)
        $vsResult = Find-VsBuildTools
    }
}

if ($vsResult) {
    $CmakeGenerator = $vsResult.Generator
    $VsInstallPath = $vsResult.InstallPath
    Write-Host "[OK] $CmakeGenerator detected via $($vsResult.Source)" -ForegroundColor Green
    if ($vsResult.ClExe) { Write-Host "   cl.exe: $($vsResult.ClExe)" -ForegroundColor Gray }
    Write-Host "   cmake generator: $CmakeGenerator" -ForegroundColor Gray
} else {
    Write-Host "[ERROR] Visual Studio Build Tools could not be found or installed." -ForegroundColor Red
    Write-Host "        Manual install:" -ForegroundColor Red
    Write-Host '        1. winget install Microsoft.VisualStudio.2022.BuildTools' -ForegroundColor Yellow
    Write-Host '        2. Open Visual Studio Installer -> Modify -> check "Desktop development with C++"' -ForegroundColor Yellow
    exit 1
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
    '-G', $CmakeGenerator,
    '-Wno-dev'
)
# Tell cmake exactly where VS is (bypasses registry lookup)
if ($VsInstallPath) {
    $CmakeArgs += "-DCMAKE_GENERATOR_INSTANCE=$VsInstallPath"
}
$CmakeArgs += '-DBUILD_SHARED_LIBS=OFF'
$CmakeArgs += '-DGGML_CUDA=OFF'
# Suppress warnings: no HTTPS needed for local inference, fix CRT lib conflict
$CmakeArgs += '-DLLAMA_CURL=OFF'
$CmakeArgs += '-DCMAKE_POLICY_DEFAULT_CMP0194=NEW'
$CmakeArgs += '-DCMAKE_EXE_LINKER_FLAGS=/NODEFAULTLIB:LIBCMT'

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

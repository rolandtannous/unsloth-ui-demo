#Requires -Version 5.1
<#
.SYNOPSIS
    Standalone llama.cpp CUDA build test script.
.DESCRIPTION
    Isolated script to nail down the CUDA-enabled llama.cpp build on Windows.
    Once validated, this logic gets merged into setup.ps1.
.NOTES
    Usage: powershell -ExecutionPolicy Bypass -File build_llama_cuda.ps1
    Optional: -Clean to wipe build dir and rebuild from scratch
#>
param(
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "+==============================================+" -ForegroundColor Cyan
Write-Host "|   llama.cpp CUDA Build Test (Standalone)     |" -ForegroundColor Cyan
Write-Host "+==============================================+" -ForegroundColor Cyan
Write-Host ""

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

function Refresh-Environment {
    foreach ($level in @('Machine', 'User')) {
        $vars = [System.Environment]::GetEnvironmentVariables($level)
        foreach ($key in $vars.Keys) {
            if ($key -eq 'Path') { continue }
            Set-Item -Path "Env:$key" -Value $vars[$key] -ErrorAction SilentlyContinue
        }
    }
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"
}

function Find-Nvcc {
    $cmd = Get-Command nvcc -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $cudaRoot = [Environment]::GetEnvironmentVariable('CUDA_PATH', 'Process')
    if (-not $cudaRoot) { $cudaRoot = [Environment]::GetEnvironmentVariable('CUDA_PATH', 'Machine') }
    if (-not $cudaRoot) { $cudaRoot = [Environment]::GetEnvironmentVariable('CUDA_PATH', 'User') }
    if ($cudaRoot -and (Test-Path (Join-Path $cudaRoot 'bin\nvcc.exe'))) {
        return (Join-Path $cudaRoot 'bin\nvcc.exe')
    }

    $toolkitBase = 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA'
    if (Test-Path $toolkitBase) {
        $latest = Get-ChildItem -Directory $toolkitBase | Sort-Object Name | Select-Object -Last 1
        if ($latest -and (Test-Path (Join-Path $latest.FullName 'bin\nvcc.exe'))) {
            return (Join-Path $latest.FullName 'bin\nvcc.exe')
        }
    }

    return $null
}

# Detect CUDA Compute Capability via nvidia-smi.
# Returns e.g. "80" for A100 (8.0), "89" for RTX 4090 (8.9), etc.
# Returns $null if detection fails.
function Get-CudaComputeCapability {
    $nvSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $nvSmi) { return $null }

    try {
        $raw = & nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }

        # nvidia-smi may return multiple GPUs; take the first one
        $cap = ($raw -split "`n")[0].Trim()
        if ($cap -match '^(\d+)\.(\d+)$') {
            $major = $Matches[1]
            $minor = $Matches[2]
            Write-Host "   CUDA Compute Capability = $major.$minor" -ForegroundColor Gray
            return "$major$minor"
        }
    } catch { }

    return $null
}

# ─────────────────────────────────────────────
# Paths
# ─────────────────────────────────────────────
$LlamaCppDir = Join-Path $env:USERPROFILE ".unsloth\llama.cpp"
$BuildDir = Join-Path $LlamaCppDir "build"
$LlamaServerBin = Join-Path $BuildDir "bin\Release\llama-server.exe"

if ($Clean -and (Test-Path $BuildDir)) {
    Write-Host "[CLEAN] Removing build directory..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $BuildDir
    Write-Host "[OK] Build directory removed" -ForegroundColor Green
    Write-Host ""
}

# ─────────────────────────────────────────────
# Preflight checks
# ─────────────────────────────────────────────
Write-Host "--- Preflight Checks ---" -ForegroundColor Cyan

# Git
$HasGit = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
if (-not $HasGit) {
    Write-Host "[ERROR] git not found. Install Git and re-run." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] git: $(git --version)" -ForegroundColor Green

# CMake
$HasCmake = $null -ne (Get-Command cmake -ErrorAction SilentlyContinue)
if (-not $HasCmake) {
    Write-Host "[ERROR] cmake not found. Install CMake and re-run." -ForegroundColor Red
    Write-Host "        winget install Kitware.CMake" -ForegroundColor Yellow
    exit 1
}
Write-Host "[OK] cmake: $(cmake --version | Select-Object -First 1)" -ForegroundColor Green

# Visual Studio / Build Tools -- detect via vswhere so we can pass -G to cmake
$CmakeGenerator = $null
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsInfo = & $vswhere -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property catalog_productLineVersion 2>$null
    if ($vsInfo) {
        $vsYear = $vsInfo.Trim()
        $vsGeneratorMap = @{ '2022' = '17'; '2019' = '16'; '2017' = '15' }
        $vsNum = $vsGeneratorMap[$vsYear]
        if ($vsNum) {
            $CmakeGenerator = "Visual Studio $vsNum $vsYear"
            Write-Host "[OK] Visual Studio $vsYear (Build Tools) detected" -ForegroundColor Green
        }
    }
    if (-not $CmakeGenerator) {
        $vsPath = & $vswhere -latest -property installationPath 2>$null
        if ($vsPath) {
            $vsYear = & $vswhere -latest -property catalog_productLineVersion 2>$null
            if ($vsYear) {
                $vsYear = $vsYear.Trim()
                $vsGeneratorMap = @{ '2022' = '17'; '2019' = '16'; '2017' = '15' }
                $vsNum = $vsGeneratorMap[$vsYear]
                if ($vsNum) {
                    $CmakeGenerator = "Visual Studio $vsNum $vsYear"
                    Write-Host "[OK] Visual Studio $vsYear detected (C++ tools may need install)" -ForegroundColor Yellow
                }
            }
        }
    }
}
if (-not $CmakeGenerator) {
    Write-Host "[ERROR] Visual Studio Build Tools not found." -ForegroundColor Red
    Write-Host "        Install with: winget install Microsoft.VisualStudio.2022.BuildTools" -ForegroundColor Red
    Write-Host "        Then install 'Desktop development with C++' workload." -ForegroundColor Red
    exit 1
}

Write-Host ""

# ─────────────────────────────────────────────
# CUDA Detection
# ─────────────────────────────────────────────
Write-Host "--- CUDA Detection ---" -ForegroundColor Cyan

# Lower ErrorActionPreference for native commands
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"

$NvccPath = Find-Nvcc
$UseCuda = $false
$CudaArch = $null

if ($NvccPath) {
    $CudaToolkitRoot = Split-Path (Split-Path $NvccPath -Parent) -Parent

    # Set CUDA_PATH (for cmake FindCUDAToolkit)
    [Environment]::SetEnvironmentVariable('CUDA_PATH', $CudaToolkitRoot, 'Process')

    # Set CudaToolkitDir (for MSBuild .targets -- the key fix!)
    # Trailing backslash required because .targets appends subpaths to it
    [Environment]::SetEnvironmentVariable('CudaToolkitDir', "$CudaToolkitRoot\", 'Process')

    # Ensure nvcc is on PATH
    $nvccBinDir = Split-Path $NvccPath -Parent
    if ($env:PATH -notlike "*$nvccBinDir*") {
        [Environment]::SetEnvironmentVariable('PATH', "$nvccBinDir;$env:PATH", 'Process')
    }

    Write-Host "[OK] nvcc found: $NvccPath" -ForegroundColor Green
    Write-Host "   CUDA_PATH      = $CudaToolkitRoot" -ForegroundColor Gray
    Write-Host "   CudaToolkitDir = $CudaToolkitRoot\" -ForegroundColor Gray

    # Detect compute capability
    $CudaArch = Get-CudaComputeCapability
    if ($CudaArch) {
        Write-Host "   CUDA Architecture = $CudaArch (will use -DCMAKE_CUDA_ARCHITECTURES=$CudaArch)" -ForegroundColor Gray
    } else {
        Write-Host "   [WARN] Could not detect compute capability -- cmake will use defaults" -ForegroundColor Yellow
    }

    $UseCuda = $true
} else {
    $HasGpu = $null -ne (Get-Command nvidia-smi -ErrorAction SilentlyContinue)
    if ($HasGpu) {
        Write-Host "[WARN] NVIDIA GPU detected but CUDA Toolkit (nvcc) not found." -ForegroundColor Yellow
        Write-Host "       Install: winget install --id=Nvidia.CUDA -e" -ForegroundColor Yellow
    } else {
        Write-Host "[INFO] No NVIDIA GPU detected -- building CPU-only" -ForegroundColor Gray
    }
}

Write-Host ""

# ─────────────────────────────────────────────
# Clone / update llama.cpp
# ─────────────────────────────────────────────
Write-Host "--- Source ---" -ForegroundColor Cyan

$UnslothDir = Join-Path $env:USERPROFILE ".unsloth"
if (-not (Test-Path $UnslothDir)) { New-Item -ItemType Directory -Path $UnslothDir -Force | Out-Null }

if (Test-Path (Join-Path $LlamaCppDir ".git")) {
    Write-Host "   llama.cpp already cloned, pulling latest..." -ForegroundColor Gray
    git -C $LlamaCppDir pull
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   [WARN] git pull failed (exit $LASTEXITCODE) -- using existing source" -ForegroundColor Yellow
    }
} else {
    if (Test-Path $LlamaCppDir) { Remove-Item -Recurse -Force $LlamaCppDir }
    Write-Host "   Cloning llama.cpp..." -ForegroundColor Gray
    git clone --depth 1 https://github.com/ggml-org/llama.cpp.git $LlamaCppDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] git clone failed (exit $LASTEXITCODE)" -ForegroundColor Red
        exit 1
    }
}
Write-Host "[OK] Source ready at $LlamaCppDir" -ForegroundColor Green
Write-Host ""

# ─────────────────────────────────────────────
# cmake configure
# ─────────────────────────────────────────────
Write-Host "--- cmake configure ---" -ForegroundColor Cyan

$CmakeArgs = @(
    '-S', $LlamaCppDir,
    '-B', $BuildDir,
    '-G', $CmakeGenerator,
    '-DBUILD_SHARED_LIBS=OFF'
)

if ($UseCuda) {
    $CmakeArgs += '-DGGML_CUDA=ON'
    $CmakeArgs += "-DCUDAToolkit_ROOT=$CudaToolkitRoot"
    $CmakeArgs += "-DCMAKE_CUDA_COMPILER=$NvccPath"
    $CmakeArgs += '-DGGML_CUDA_FA_ALL_QUANTS=ON'
    $CmakeArgs += '-DGGML_CUDA_F16=OFF'
    $CmakeArgs += '-DGGML_CUDA_GRAPHS=OFF'
    $CmakeArgs += '-DGGML_CUDA_FORCE_CUBLAS=OFF'
    $CmakeArgs += '-DGGML_CUDA_PEER_MAX_BATCH_SIZE=8192'

    if ($CudaArch) {
        $CmakeArgs += "-DCMAKE_CUDA_ARCHITECTURES=$CudaArch"
    }

    Write-Host "   Mode: CUDA (GPU)" -ForegroundColor Green
} else {
    $CmakeArgs += '-DGGML_CUDA=OFF'
    Write-Host "   Mode: CPU-only" -ForegroundColor Yellow
}

Write-Host "   cmake args:" -ForegroundColor Gray
foreach ($arg in $CmakeArgs) {
    Write-Host "     $arg" -ForegroundColor Gray
}
Write-Host ""

# Run cmake configure VERBOSE (no output redirection!)
cmake @CmakeArgs
$cmakeExit = $LASTEXITCODE

# CUDA fallback: if CUDA configure failed, retry CPU-only
if ($cmakeExit -ne 0 -and $UseCuda) {
    Write-Host ""
    Write-Host "   [WARN] CUDA cmake configure failed (exit $cmakeExit) -- retrying CPU-only..." -ForegroundColor Yellow
    if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }

    $CmakeArgs = @(
        '-S', $LlamaCppDir,
        '-B', $BuildDir,
        '-G', $CmakeGenerator,
        '-DBUILD_SHARED_LIBS=OFF',
        '-DGGML_CUDA=OFF'
    )
    cmake @CmakeArgs
    $cmakeExit = $LASTEXITCODE
    $UseCuda = $false
}

if ($cmakeExit -ne 0) {
    Write-Host ""
    Write-Host "[FAILED] cmake configure failed (exit $cmakeExit)" -ForegroundColor Red
    $ErrorActionPreference = $prevEAP
    exit 1
}

Write-Host ""
Write-Host "[OK] cmake configure succeeded" -ForegroundColor Green
Write-Host ""

# ─────────────────────────────────────────────
# cmake build
# ─────────────────────────────────────────────
$NumCpu = [Environment]::ProcessorCount
if ($NumCpu -lt 1) { $NumCpu = 4 }

Write-Host "--- cmake build (llama-server) ---" -ForegroundColor Cyan
Write-Host "   Parallel jobs: $NumCpu" -ForegroundColor Gray
Write-Host ""

# VERBOSE build -- output streams to console in real time
cmake --build $BuildDir --config Release --target llama-server -j $NumCpu
$buildExit = $LASTEXITCODE

if ($buildExit -ne 0) {
    Write-Host ""
    Write-Host "[FAILED] llama-server build failed (exit $buildExit)" -ForegroundColor Red
    $ErrorActionPreference = $prevEAP
    exit 1
}

Write-Host ""
Write-Host "[OK] llama-server build succeeded" -ForegroundColor Green

# ─────────────────────────────────────────────
# Build llama-quantize (best-effort)
# ─────────────────────────────────────────────
Write-Host ""
Write-Host "--- cmake build (llama-quantize) ---" -ForegroundColor Cyan

cmake --build $BuildDir --config Release --target llama-quantize -j $NumCpu
if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARN] llama-quantize build failed -- GGUF export may be unavailable" -ForegroundColor Yellow
} else {
    Write-Host "[OK] llama-quantize build succeeded" -ForegroundColor Green
}

# Restore
$ErrorActionPreference = $prevEAP

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
Write-Host ""
Write-Host "+==============================================+" -ForegroundColor Green
Write-Host "|             Build Complete!                   |" -ForegroundColor Green
Write-Host "+==============================================+" -ForegroundColor Green
Write-Host ""

if (Test-Path $LlamaServerBin) {
    Write-Host "[OK] llama-server: $LlamaServerBin" -ForegroundColor Green
} else {
    # Try alternative paths (some cmake generators don't use Release subdir)
    $altBin = Join-Path $BuildDir "bin\llama-server.exe"
    if (Test-Path $altBin) {
        Write-Host "[OK] llama-server: $altBin" -ForegroundColor Green
    } else {
        Write-Host "[WARN] llama-server.exe not found at expected path" -ForegroundColor Yellow
        Write-Host "       Expected: $LlamaServerBin" -ForegroundColor Yellow
        Write-Host "       Searching..." -ForegroundColor Gray
        $found = Get-ChildItem -Recurse -Filter "llama-server.exe" $BuildDir -ErrorAction SilentlyContinue
        if ($found) {
            foreach ($f in $found) {
                Write-Host "       Found: $($f.FullName)" -ForegroundColor Green
            }
        } else {
            Write-Host "       Not found anywhere in $BuildDir" -ForegroundColor Red
        }
    }
}

$QuantizeBin = Join-Path $BuildDir "bin\Release\llama-quantize.exe"
if (Test-Path $QuantizeBin) {
    Write-Host "[OK] llama-quantize: $QuantizeBin" -ForegroundColor Green
} else {
    $altQ = Join-Path $BuildDir "bin\llama-quantize.exe"
    if (Test-Path $altQ) {
        Write-Host "[OK] llama-quantize: $altQ" -ForegroundColor Green
    }
}

if ($UseCuda) {
    Write-Host ""
    Write-Host "   Build type: CUDA (GPU accelerated)" -ForegroundColor Green
    if ($CudaArch) {
        Write-Host "   Target architecture: sm_$CudaArch" -ForegroundColor Green
    }
} else {
    Write-Host ""
    Write-Host "   Build type: CPU-only" -ForegroundColor Yellow
}

Write-Host ""

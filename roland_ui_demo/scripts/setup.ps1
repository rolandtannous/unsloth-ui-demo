#Requires -Version 5.1
<#
.SYNOPSIS
    Full environment setup for Unsloth Studio on Windows (bundled version).
.DESCRIPTION
    Always installs Node.js if needed. When running from pip install:
    skips frontend build (already bundled). When running from git repo:
    full setup including frontend build.
.NOTES
    Usage: powershell -ExecutionPolicy Bypass -File setup.ps1
#>

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageDir = Split-Path -Parent $ScriptDir

# Detect if running from pip install (no frontend/ dir two levels up)
$FrontendDir = Join-Path $ScriptDir "..\..\frontend"
$IsPipInstall = -not (Test-Path $FrontendDir)

# Helper: refresh PATH from registry (picks up changes from winget installs)
function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"
}

Write-Host "+==============================================+" -ForegroundColor Green
Write-Host "|       Unsloth Studio Setup (Windows)         |" -ForegroundColor Green
Write-Host "+==============================================+" -ForegroundColor Green

# ============================================
# Step 0: Git (required by pip for git+https:// deps and by npm)
# ============================================
$HasGit = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
if (-not $HasGit) {
    Write-Host "Git not found -- installing via winget..." -ForegroundColor Yellow
    $HasWinget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
    if ($HasWinget) {
        try {
            winget install Git.Git --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            Refresh-Path
            $HasGit = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
        } catch { }
    }
    if (-not $HasGit) {
        Write-Host "[ERROR] Git is required but could not be installed automatically." -ForegroundColor Red
        Write-Host "        Install Git from https://git-scm.com/download/win and re-run." -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] Git installed: $(git --version)" -ForegroundColor Green
} else {
    Write-Host "[OK] Git found: $(git --version)" -ForegroundColor Green
}

# ============================================
# Step 1: Node.js / npm (always -- needed regardless of install method)
# ============================================
$NeedNode = $true
try {
    $NodeVersion = (node -v 2>$null)
    $NpmVersion = (npm -v 2>$null)
    if ($NodeVersion -and $NpmVersion) {
        $NodeMajor = [int]($NodeVersion -replace 'v','').Split('.')[0]
        $NpmMajor = [int]$NpmVersion.Split('.')[0]

        if ($NodeMajor -ge 20 -and $NpmMajor -ge 11) {
            Write-Host "[OK] Node $NodeVersion and npm $NpmVersion already meet requirements." -ForegroundColor Green
            $NeedNode = $false
        } else {
            Write-Host "[WARN] Node $NodeVersion / npm $NpmVersion too old." -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "[WARN] Node/npm not found." -ForegroundColor Yellow
}

if ($NeedNode) {
    Write-Host "Installing Node.js via winget..." -ForegroundColor Cyan
    try {
        winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
        Refresh-Path
    } catch {
        Write-Host "[ERROR] Could not install Node.js automatically." -ForegroundColor Red
        Write-Host "Please install Node.js >= 20 from https://nodejs.org/" -ForegroundColor Red
        exit 1
    }
}

Write-Host "[OK] Node $(node -v) | npm $(npm -v)" -ForegroundColor Green

# ============================================
# Step 2: Build React frontend (skip if pip-installed -- already bundled)
# ============================================
if ($IsPipInstall) {
    Write-Host "[OK] Running from pip install - frontend already bundled, skipping build" -ForegroundColor Green
} else {
    $RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path

    Write-Host ""
    Write-Host "Building frontend..." -ForegroundColor Cyan
    Push-Location (Join-Path $RepoRoot "frontend")
    npm install 2>&1 | Out-Null
    npm run build 2>&1 | Out-Null
    Pop-Location

    $PackageBuildDir = Join-Path $PackageDir "studio\frontend\build"
    if (Test-Path $PackageBuildDir) { Remove-Item -Recurse -Force $PackageBuildDir }
    Copy-Item -Recurse (Join-Path $RepoRoot "frontend\build") $PackageBuildDir

    Write-Host "[OK] Frontend built" -ForegroundColor Green
}

# ============================================
# Step 3: Python environment + dependencies
# ============================================
Write-Host ""
Write-Host "Setting up Python environment..." -ForegroundColor Cyan

# Find Python
$PythonCmd = $null
foreach ($candidate in @("python3.12", "python3.11", "python3.10", "python3.9", "python3", "python")) {
    try {
        $ver = & $candidate --version 2>&1
        if ($ver -match 'Python 3\.(\d+)') {
            $minor = [int]$Matches[1]
            if ($minor -le 12) {
                $PythonCmd = $candidate
                break
            }
        }
    } catch { }
}

if (-not $PythonCmd) {
    Write-Host "[ERROR] No Python <= 3.12 found." -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Using $PythonCmd ($(& $PythonCmd --version 2>&1))" -ForegroundColor Green

# Venv + editable install only when running from repo
if (-not $IsPipInstall) {
    $RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
    $VenvDir = Join-Path $RepoRoot ".venv"
    if (Test-Path $VenvDir) { Remove-Item -Recurse -Force $VenvDir }
    & $PythonCmd -m venv $VenvDir

    $ActivateScript = Join-Path $VenvDir "Scripts\Activate.ps1"
    . $ActivateScript

    pip install --upgrade pip 2>&1 | Out-Null

    # Copy requirements into the Python package
    $ReqsSrc = Join-Path $RepoRoot "backend\requirements"
    $ReqsDst = Join-Path $PackageDir "requirements"
    if (-not (Test-Path $ReqsDst)) { New-Item -ItemType Directory -Path $ReqsDst | Out-Null }
    Copy-Item (Join-Path $ReqsSrc "*.txt") $ReqsDst -Force

    Write-Host "   Installing CLI entry point..." -ForegroundColor Cyan
    pip install -e $RepoRoot 2>&1 | Out-Null
}

# Ordered heavy dependency installation
Write-Host "   Running ordered dependency installation..." -ForegroundColor Cyan
python -c "from roland_ui_demo.installer import run_install; exit(run_install())"

# ============================================
# Build llama.cpp binaries for GGUF inference + export
# ============================================
# Builds at ~/.unsloth/llama.cpp/ (persistent across pip upgrades).
# We build:
#   - llama-server:   for GGUF model inference
#   - llama-quantize: for GGUF export quantization
$LlamaCppDir = Join-Path $env:USERPROFILE ".unsloth\llama.cpp"
$LlamaServerBin = Join-Path $LlamaCppDir "build\bin\Release\llama-server.exe"

if (Test-Path $LlamaServerBin) {
    Write-Host ""
    Write-Host "[OK] llama-server already exists at $LlamaServerBin" -ForegroundColor Green
} else {
    $HasCmake = $null -ne (Get-Command cmake -ErrorAction SilentlyContinue)
    $HasGitNow = $null -ne (Get-Command git -ErrorAction SilentlyContinue)

    if (-not $HasCmake) {
        Write-Host ""
        Write-Host "[SKIP] cmake not found -- skipping llama-server build (GGUF inference unavailable)" -ForegroundColor Yellow
        Write-Host "       Install CMake and re-run to enable GGUF inference." -ForegroundColor Yellow
    } elseif (-not $HasGitNow) {
        Write-Host ""
        Write-Host "[SKIP] git not found -- skipping llama-server build" -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "Building llama-server for GGUF inference..." -ForegroundColor Cyan

        $UnslothDir = Join-Path $env:USERPROFILE ".unsloth"
        if (-not (Test-Path $UnslothDir)) { New-Item -ItemType Directory -Path $UnslothDir -Force | Out-Null }

        $BuildOk = $true
        $FailedStep = ""
        $BuildDir = Join-Path $LlamaCppDir "build"

        # -- Step A: Clone or pull llama.cpp --
        if (Test-Path (Join-Path $LlamaCppDir ".git")) {
            Write-Host "   llama.cpp repo already cloned, pulling latest..." -ForegroundColor Gray
            try { git -C $LlamaCppDir pull 2>&1 | Out-Null } catch { }
        } else {
            Write-Host "   Cloning llama.cpp..." -ForegroundColor Gray
            if (Test-Path $LlamaCppDir) { Remove-Item -Recurse -Force $LlamaCppDir }
            $tmpLog = [System.IO.Path]::GetTempFileName()
            try {
                $output = git clone --depth 1 https://github.com/ggml-org/llama.cpp.git $LlamaCppDir 2>&1
                $output | Out-File -FilePath $tmpLog -Encoding utf8
                if ($LASTEXITCODE -ne 0) { throw "git clone exited with code $LASTEXITCODE" }
            } catch {
                $BuildOk = $false
                $FailedStep = "git clone"
                Write-Host "   [FAILED] git clone failed:" -ForegroundColor Red
                if (Test-Path $tmpLog) { Get-Content $tmpLog | ForEach-Object { Write-Host "   $_" -ForegroundColor Red } }
                Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
            }
            if (Test-Path $tmpLog) { Remove-Item -Force $tmpLog }
        }

        # -- Step B: Detect CUDA and run cmake configure --
        if ($BuildOk) {
            $CmakeArgs = @()
            $NvccPath = $null

            # 1. Check nvcc on PATH
            $NvccCmd = Get-Command nvcc -ErrorAction SilentlyContinue
            if ($NvccCmd) {
                $NvccPath = $NvccCmd.Source
            }

            # 2. Search common CUDA Toolkit install locations on Windows
            if (-not $NvccPath) {
                $CudaRoot = $env:CUDA_PATH
                if ($CudaRoot -and (Test-Path (Join-Path $CudaRoot 'bin\nvcc.exe'))) {
                    $NvccPath = Join-Path $CudaRoot 'bin\nvcc.exe'
                    $env:PATH = (Join-Path $CudaRoot 'bin') + ';' + $env:PATH
                } else {
                    # Scan C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*
                    $ToolkitBase = 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA'
                    if (Test-Path $ToolkitBase) {
                        $Latest = Get-ChildItem -Directory $ToolkitBase | Sort-Object Name | Select-Object -Last 1
                        if ($Latest -and (Test-Path (Join-Path $Latest.FullName 'bin\nvcc.exe'))) {
                            $NvccPath = Join-Path $Latest.FullName 'bin\nvcc.exe'
                            $env:PATH = (Join-Path $Latest.FullName 'bin') + ';' + $env:PATH
                        }
                    }
                }
            }

            if ($NvccPath) {
                Write-Host "   Building with CUDA support (nvcc: $NvccPath)..." -ForegroundColor Gray
                $CmakeArgs += '-DGGML_CUDA=ON'
            } else {
                # 3. Check if GPU driver is present but toolkit is missing
                $HasNvidiaSmi = $null -ne (Get-Command nvidia-smi -ErrorAction SilentlyContinue)
                if ($HasNvidiaSmi) {
                    Write-Host "   CUDA driver detected but nvcc not found -- building CPU-only" -ForegroundColor Yellow
                    Write-Host "   To enable GPU: install CUDA Toolkit from https://developer.nvidia.com/cuda-downloads" -ForegroundColor Yellow
                    Write-Host "   Then re-run setup to rebuild with CUDA support." -ForegroundColor Yellow
                } else {
                    Write-Host "   Building CPU-only (no CUDA detected)..." -ForegroundColor Gray
                }
            }

            Write-Host "   Running cmake configure..." -ForegroundColor Gray
            $tmpLog = [System.IO.Path]::GetTempFileName()
            try {
                $cmakeConfigArgs = @('-S', $LlamaCppDir, '-B', $BuildDir) + $CmakeArgs
                $output = cmake @cmakeConfigArgs 2>&1
                $output | Out-File -FilePath $tmpLog -Encoding utf8
                if ($LASTEXITCODE -ne 0) { throw "cmake configure exited with code $LASTEXITCODE" }
            } catch {
                $BuildOk = $false
                $FailedStep = "cmake configure"
                Write-Host "   [FAILED] cmake configure failed:" -ForegroundColor Red
                if (Test-Path $tmpLog) { Get-Content $tmpLog | ForEach-Object { Write-Host "   $_" -ForegroundColor Red } }
                Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
            }
            if (Test-Path $tmpLog) { Remove-Item -Force $tmpLog }
        }

        # -- Step C: Build llama-server --
        $NumCpu = [Environment]::ProcessorCount
        if ($NumCpu -lt 1) { $NumCpu = 4 }

        if ($BuildOk) {
            Write-Host "   Building llama-server (using $NumCpu cores)..." -ForegroundColor Gray
            $tmpLog = [System.IO.Path]::GetTempFileName()
            try {
                $output = cmake --build $BuildDir --config Release --target llama-server -j $NumCpu 2>&1
                $output | Out-File -FilePath $tmpLog -Encoding utf8
                if ($LASTEXITCODE -ne 0) { throw "cmake build (llama-server) exited with code $LASTEXITCODE" }
            } catch {
                $BuildOk = $false
                $FailedStep = "cmake build (llama-server)"
                Write-Host "   [FAILED] cmake build (llama-server) failed:" -ForegroundColor Red
                if (Test-Path $tmpLog) {
                    # Show last 30 lines to avoid flooding the terminal
                    $lines = Get-Content $tmpLog
                    if ($lines.Count -gt 30) {
                        Write-Host "   ... (showing last 30 lines of $($lines.Count) total) ..." -ForegroundColor Gray
                        $lines = $lines[-30..-1]
                    }
                    $lines | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
                }
                Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
            }
            if (Test-Path $tmpLog) { Remove-Item -Force $tmpLog }
        }

        # -- Step D: Build llama-quantize (optional, best-effort) --
        if ($BuildOk) {
            Write-Host "   Building llama-quantize..." -ForegroundColor Gray
            try {
                $output = cmake --build $BuildDir --config Release --target llama-quantize -j $NumCpu 2>&1
                if ($LASTEXITCODE -ne 0) { throw "cmake build (llama-quantize) exited with code $LASTEXITCODE" }
            } catch {
                Write-Host "   [WARN] llama-quantize build failed (GGUF export may be unavailable)" -ForegroundColor Yellow
            }
        }

        # -- Summary --
        if ($BuildOk -and (Test-Path $LlamaServerBin)) {
            Write-Host "[OK] llama-server built at $LlamaServerBin" -ForegroundColor Green
            $QuantizeBin = Join-Path $BuildDir "bin\Release\llama-quantize.exe"
            if (Test-Path $QuantizeBin) {
                Write-Host "[OK] llama-quantize available for GGUF export" -ForegroundColor Green
            }
        } else {
            Write-Host ""
            Write-Host "[SKIP] llama-server build failed at step: $FailedStep" -ForegroundColor Yellow
            Write-Host "       GGUF inference unavailable, but everything else works." -ForegroundColor Yellow
            Write-Host "       To retry: delete $LlamaCppDir and re-run setup." -ForegroundColor Yellow
        }
    }
}

# ============================================
# Done
# ============================================
Write-Host ""
Write-Host "+==============================================+" -ForegroundColor Green
Write-Host "|           Setup Complete!                    |" -ForegroundColor Green
Write-Host "|                                              |" -ForegroundColor Green
Write-Host "|  Run: unsloth-roland-test studio             |" -ForegroundColor Green
Write-Host "+==============================================+" -ForegroundColor Green

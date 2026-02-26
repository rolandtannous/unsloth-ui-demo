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

# Helper: reload ALL environment variables from registry.
# Picks up changes made by installers (winget, msi, etc.) including
# Path, CUDA_PATH, CUDA_PATH_V*, and any other vars they set.
function Refresh-Environment {
    # Reload non-Path variables from Machine and User scopes
    foreach ($level in @('Machine', 'User')) {
        $vars = [System.Environment]::GetEnvironmentVariables($level)
        foreach ($key in $vars.Keys) {
            if ($key -eq 'Path') { continue }
            Set-Item -Path "Env:$key" -Value $vars[$key] -ErrorAction SilentlyContinue
        }
    }
    # Path needs special handling: concatenate Machine + User
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
            Refresh-Environment
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
        Refresh-Environment
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
    # -- Prerequisites: CMake (auto-install via winget if missing) --
    $HasCmake = $null -ne (Get-Command cmake -ErrorAction SilentlyContinue)
    if (-not $HasCmake) {
        Write-Host ""
        Write-Host "CMake not found -- installing via winget..." -ForegroundColor Yellow
        $HasWinget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
        if ($HasWinget) {
            try {
                winget install Kitware.CMake --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                Refresh-Environment
                $HasCmake = $null -ne (Get-Command cmake -ErrorAction SilentlyContinue)
            } catch { }
        }
        if ($HasCmake) {
            Write-Host "[OK] CMake installed" -ForegroundColor Green
        } else {
            Write-Host "[SKIP] CMake could not be installed -- skipping llama-server build" -ForegroundColor Yellow
            Write-Host "       Install CMake from https://cmake.org/download/ and re-run." -ForegroundColor Yellow
        }
    }

    $HasGitNow = $null -ne (Get-Command git -ErrorAction SilentlyContinue)

    if (-not $HasCmake) {
        # Already printed skip message above
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

        # Native commands (git, cmake) write to stderr even on success.
        # With $ErrorActionPreference = "Stop" (set at top of script), PS 5.1
        # converts stderr lines into terminating ErrorRecords, breaking output
        # capture. Lower to "Continue" for this section.
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"

        # -- Step A: Clone or pull llama.cpp --
        if (Test-Path (Join-Path $LlamaCppDir ".git")) {
            Write-Host "   llama.cpp repo already cloned, pulling latest..." -ForegroundColor Gray
            git -C $LlamaCppDir pull *> $null
        } else {
            Write-Host "   Cloning llama.cpp..." -ForegroundColor Gray
            if (Test-Path $LlamaCppDir) { Remove-Item -Recurse -Force $LlamaCppDir }
            $tmpLog = [System.IO.Path]::GetTempFileName()
            git clone --depth 1 https://github.com/ggml-org/llama.cpp.git $LlamaCppDir *> $tmpLog
            if ($LASTEXITCODE -ne 0) {
                $BuildOk = $false
                $FailedStep = "git clone"
                Write-Host "   [FAILED] git clone failed (exit code $LASTEXITCODE):" -ForegroundColor Red
                Get-Content $tmpLog | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
            }
            Remove-Item -Force $tmpLog -ErrorAction SilentlyContinue
        }

        # -- Step B: Detect CUDA (+ auto-install toolkit) and run cmake configure --
        if ($BuildOk) {
            $CmakeArgs = @()
            $NvccPath = $null

            # Helper: find nvcc on PATH, CUDA_PATH, or standard toolkit dirs.
            # Returns the path to nvcc.exe, or $null if not found.
            function Find-Nvcc {
                # 1. Check nvcc on PATH
                $cmd = Get-Command nvcc -ErrorAction SilentlyContinue
                if ($cmd) { return $cmd.Source }

                # 2. Check CUDA_PATH env var
                $cudaRoot = [Environment]::GetEnvironmentVariable('CUDA_PATH', 'Process')
                if (-not $cudaRoot) { $cudaRoot = [Environment]::GetEnvironmentVariable('CUDA_PATH', 'Machine') }
                if (-not $cudaRoot) { $cudaRoot = [Environment]::GetEnvironmentVariable('CUDA_PATH', 'User') }
                if ($cudaRoot -and (Test-Path (Join-Path $cudaRoot 'bin\nvcc.exe'))) {
                    return (Join-Path $cudaRoot 'bin\nvcc.exe')
                }

                # 3. Scan standard toolkit directory
                $toolkitBase = 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA'
                if (Test-Path $toolkitBase) {
                    $latest = Get-ChildItem -Directory $toolkitBase | Sort-Object Name | Select-Object -Last 1
                    if ($latest -and (Test-Path (Join-Path $latest.FullName 'bin\nvcc.exe'))) {
                        return (Join-Path $latest.FullName 'bin\nvcc.exe')
                    }
                }

                return $null
            }

            $NvccPath = Find-Nvcc

            # GPU driver present but no toolkit -- auto-install via winget
            if (-not $NvccPath) {
                $HasNvidiaSmi = $null -ne (Get-Command nvidia-smi -ErrorAction SilentlyContinue)
                if ($HasNvidiaSmi) {
                    Write-Host "   CUDA driver detected but toolkit (nvcc) not found." -ForegroundColor Yellow
                    $HasWinget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
                    if ($HasWinget) {
                        Write-Host "   Installing CUDA Toolkit via winget (this may take several minutes)..." -ForegroundColor Cyan
                        winget install --id=Nvidia.CUDA -e --accept-package-agreements --accept-source-agreements
                        Refresh-Environment
                        $NvccPath = Find-Nvcc
                        if ($NvccPath) {
                            Write-Host "   [OK] CUDA Toolkit installed (nvcc: $NvccPath)" -ForegroundColor Green
                        } else {
                            Write-Host "   [WARN] CUDA Toolkit install did not provide nvcc -- building CPU-only" -ForegroundColor Yellow
                            Write-Host "   To enable GPU: install manually from https://developer.nvidia.com/cuda-downloads" -ForegroundColor Yellow
                        }
                    } else {
                        Write-Host "   winget not available -- cannot auto-install CUDA Toolkit" -ForegroundColor Yellow
                        Write-Host "   To enable GPU: install CUDA Toolkit from https://developer.nvidia.com/cuda-downloads" -ForegroundColor Yellow
                    }
                }
            }

            # -- Set CUDA env vars so cmake AND MSBuild can find the toolkit --
            # cmake's enable_language(CUDA) generates a temp .vcxproj that imports
            # CUDA XX.X.targets but NOT CUDA XX.X.props. The .props file normally
            # sets CudaToolkitDir from $(CUDA_PATH), but without it CudaToolkitDir
            # is empty and MSBuild fails with "The CUDA Toolkit directory '' does
            # not exist." Fix: set CudaToolkitDir directly as an env var -- MSBuild
            # reads all env vars as MSBuild properties.
            if ($NvccPath) {
                $CudaToolkitRoot = Split-Path (Split-Path $NvccPath -Parent) -Parent
                # CUDA_PATH: used by cmake's find_package(CUDAToolkit)
                [Environment]::SetEnvironmentVariable('CUDA_PATH', $CudaToolkitRoot, 'Process')
                # CudaToolkitDir: the MSBuild property that CUDA .targets checks directly
                # Trailing backslash required -- the .targets file appends subpaths to it
                [Environment]::SetEnvironmentVariable('CudaToolkitDir', "$CudaToolkitRoot\", 'Process')
                Write-Host "   CUDA_PATH=$CudaToolkitRoot" -ForegroundColor Gray
                Write-Host "   CudaToolkitDir=$CudaToolkitRoot\" -ForegroundColor Gray
                # Persist CUDA_PATH to User registry if not already set
                $existingSys = [Environment]::GetEnvironmentVariable('CUDA_PATH', 'Machine')
                $existingUsr = [Environment]::GetEnvironmentVariable('CUDA_PATH', 'User')
                if (-not $existingSys -and -not $existingUsr) {
                    [Environment]::SetEnvironmentVariable('CUDA_PATH', $CudaToolkitRoot, 'User')
                    Write-Host "   Persisted CUDA_PATH to user environment" -ForegroundColor Gray
                }
                # Ensure nvcc's bin dir is on PATH for this process
                $nvccBinDir = Split-Path $NvccPath -Parent
                if ($env:PATH -notlike "*$nvccBinDir*") {
                    [Environment]::SetEnvironmentVariable('PATH', "$nvccBinDir;$env:PATH", 'Process')
                }
            }

            # -- Run cmake configure (with CUDA fallback to CPU-only) --
            $UseCuda = $false
            if ($NvccPath) {
                $CudaToolkitRoot = [Environment]::GetEnvironmentVariable('CUDA_PATH', 'Process')
                Write-Host "   Building with CUDA support (nvcc: $NvccPath)..." -ForegroundColor Gray
                Write-Host "   CUDA_PATH=$CudaToolkitRoot" -ForegroundColor Gray
                $CmakeArgs += '-DGGML_CUDA=ON'
                $CmakeArgs += "-DCUDAToolkit_ROOT=$CudaToolkitRoot"
                $CmakeArgs += "-DCMAKE_CUDA_COMPILER=$NvccPath"
                $UseCuda = $true
            } else {
                $HasGpu = $null -ne (Get-Command nvidia-smi -ErrorAction SilentlyContinue)
                if (-not $HasGpu) {
                    Write-Host "   Building CPU-only (no NVIDIA GPU detected)..." -ForegroundColor Gray
                }
                $CmakeArgs += '-DGGML_CUDA=OFF'
            }

            Write-Host "   Running cmake configure..." -ForegroundColor Gray
            $tmpLog = [System.IO.Path]::GetTempFileName()
            $cmakeConfigArgs = @('-S', $LlamaCppDir, '-B', $BuildDir) + $CmakeArgs
            cmake @cmakeConfigArgs *> $tmpLog
            $cmakeExit = $LASTEXITCODE

            # If CUDA build failed, retry CPU-only automatically
            if ($cmakeExit -ne 0 -and $UseCuda) {
                Write-Host "   [WARN] CUDA cmake configure failed -- retrying CPU-only build..." -ForegroundColor Yellow
                Write-Host "   (To fix CUDA later: ensure CUDA_PATH is set and re-run setup)" -ForegroundColor Yellow
                # Clean build dir and retry without CUDA
                if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
                $cpuArgs = @('-S', $LlamaCppDir, '-B', $BuildDir, '-DGGML_CUDA=OFF')
                cmake @cpuArgs *> $tmpLog
                $cmakeExit = $LASTEXITCODE
            }

            if ($cmakeExit -ne 0) {
                $BuildOk = $false
                $FailedStep = "cmake configure"
                Write-Host "   [FAILED] cmake configure failed (exit code $cmakeExit):" -ForegroundColor Red
                Get-Content $tmpLog | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
            }
            Remove-Item -Force $tmpLog -ErrorAction SilentlyContinue
        }

        # -- Step C: Build llama-server --
        $NumCpu = [Environment]::ProcessorCount
        if ($NumCpu -lt 1) { $NumCpu = 4 }

        if ($BuildOk) {
            Write-Host "   Building llama-server (using $NumCpu cores)..." -ForegroundColor Gray
            $tmpLog = [System.IO.Path]::GetTempFileName()
            cmake --build $BuildDir --config Release --target llama-server -j $NumCpu *> $tmpLog
            if ($LASTEXITCODE -ne 0) {
                $BuildOk = $false
                $FailedStep = "cmake build (llama-server)"
                Write-Host "   [FAILED] cmake build (llama-server) failed (exit code $LASTEXITCODE):" -ForegroundColor Red
                $lines = Get-Content $tmpLog
                if ($lines.Count -gt 30) {
                    Write-Host "   ... (showing last 30 lines of $($lines.Count) total) ..." -ForegroundColor Gray
                    $lines = $lines[-30..-1]
                }
                $lines | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
            }
            Remove-Item -Force $tmpLog -ErrorAction SilentlyContinue
        }

        # -- Step D: Build llama-quantize (optional, best-effort) --
        if ($BuildOk) {
            Write-Host "   Building llama-quantize..." -ForegroundColor Gray
            cmake --build $BuildDir --config Release --target llama-quantize -j $NumCpu *> $null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "   [WARN] llama-quantize build failed (GGUF export may be unavailable)" -ForegroundColor Yellow
            }
        }

        # Restore ErrorActionPreference
        $ErrorActionPreference = $prevEAP

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

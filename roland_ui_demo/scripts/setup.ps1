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

Write-Host "+==============================================+" -ForegroundColor Green
Write-Host "|       Unsloth Studio Setup (Windows)         |" -ForegroundColor Green
Write-Host "+==============================================+" -ForegroundColor Green

# ============================================
# Step 1: Node.js / npm (always — needed regardless of install method)
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
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    } catch {
        Write-Host "[ERROR] Could not install Node.js automatically." -ForegroundColor Red
        Write-Host "Please install Node.js >= 20 from https://nodejs.org/" -ForegroundColor Red
        exit 1
    }
}

Write-Host "[OK] Node $(node -v) | npm $(npm -v)" -ForegroundColor Green

# ============================================
# Step 2: Build React frontend (skip if pip-installed — already bundled)
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
        if ($ver -match "Python 3\.(\d+)") {
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
# Step 4: Build open_spiel from source (Windows only — no pre-built wheel)
# ============================================
Write-Host ""
Write-Host "Attempting to build open_spiel from source..." -ForegroundColor Cyan
Write-Host "  (This requires Visual Studio with C++ Desktop Development," -ForegroundColor Gray
Write-Host "   MSVC v143, and Windows 11 SDK)" -ForegroundColor Gray

$OpenSpielOk = $false
try {
    # Check prerequisites: cmake and cl.exe (MSVC compiler)
    $HasCmake = $null -ne (Get-Command cmake -ErrorAction SilentlyContinue)
    $HasMsvc = $null -ne (Get-Command cl -ErrorAction SilentlyContinue)

    # Also check via vswhere if Visual Studio C++ tools are installed
    if (-not $HasMsvc) {
        $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        if (Test-Path $vswhere) {
            $vsPath = & $vswhere -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
            if ($vsPath) {
                # Source the VS developer environment
                $vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
                if (Test-Path $vcvars) {
                    Write-Host "  Sourcing Visual Studio environment..." -ForegroundColor Gray
                    cmd /c "`"$vcvars`" >nul 2>&1 && set" | ForEach-Object {
                        if ($_ -match "^([^=]+)=(.*)$") {
                            [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], "Process")
                        }
                    }
                    $HasMsvc = $true
                }
            }
        }
    }

    if (-not $HasCmake) {
        Write-Host "[SKIP] CMake not found. Install CMake to build open_spiel." -ForegroundColor Yellow
        Write-Host "       https://cmake.org/download/" -ForegroundColor Yellow
        throw "missing cmake"
    }

    if (-not $HasMsvc) {
        Write-Host "[SKIP] MSVC compiler (cl.exe) not found." -ForegroundColor Yellow
        Write-Host "       Install Visual Studio with 'Desktop Development with C++'," -ForegroundColor Yellow
        Write-Host "       MSVC v143, and Windows 11 SDK." -ForegroundColor Yellow
        throw "missing msvc"
    }

    # Clone open_spiel into a temp directory
    $TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "open_spiel_build_$(Get-Random)"
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

    Write-Host "  Cloning open_spiel into $TempDir ..." -ForegroundColor Gray
    Push-Location $TempDir

    git clone https://github.com/deepmind/open_spiel.git 2>&1 | Out-Null
    Push-Location open_spiel

    # Clone subdependencies
    git clone --single-branch --depth 1 https://github.com/pybind/pybind11.git pybind11 2>&1 | Out-Null
    git clone --single-branch --depth 1 https://github.com/pybind/pybind11_json.git open_spiel/pybind11_json 2>&1 | Out-Null
    git clone --single-branch --depth 1 https://github.com/abseil/abseil-cpp.git open_spiel/abseil-cpp 2>&1 | Out-Null
    git clone https://github.com/pybind/pybind11_abseil.git open_spiel/pybind11_abseil 2>&1 | Out-Null
    git clone -b develop --single-branch --depth 1 https://github.com/jblespiau/dds.git open_spiel/games/bridge/double_dummy_solver 2>&1 | Out-Null

    # Install Python dependencies
    pip install absl-py attrs numpy 2>&1 | Out-Null

    # Build with CMake using MSVC flags
    $BuildDir = "open_spiel\out\build\x64-Release"
    New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
    Push-Location $BuildDir

    Write-Host "  Running CMake configure..." -ForegroundColor Gray
    cmake ..\..\.. -DCMAKE_CXX_FLAGS="/std:c++17 /utf-8 /bigobj /DWIN32 /D_WINDOWS /GR /EHsc" 2>&1 | Out-Null

    Write-Host "  Building (this may take several minutes)..." -ForegroundColor Gray
    cmake --build . --config Release 2>&1 | Out-Null

    Pop-Location  # out of build dir

    # Add to PYTHONPATH for this session
    $BuildAbsPath = (Resolve-Path $BuildDir).Path
    $env:PYTHONPATH = "$BuildAbsPath;$BuildAbsPath\python;$env:PYTHONPATH"

    # Also try pip install from the repo
    pip install -e . 2>&1 | Out-Null

    Pop-Location  # out of open_spiel
    Pop-Location  # out of temp dir

    $OpenSpielOk = $true
    Write-Host "[OK] open_spiel built and installed from source" -ForegroundColor Green
} catch {
    Write-Host ""
    Write-Host "[SKIP] open_spiel could not be built automatically." -ForegroundColor Yellow
    Write-Host "       This is optional. To install manually later, see:" -ForegroundColor Yellow
    Write-Host "       https://openspiel.readthedocs.io/en/latest/windows.html" -ForegroundColor Yellow

    # Clean up any pushed locations
    while ((Get-Location).Path -ne $ScriptDir -and (Get-Location).Path -ne $env:USERPROFILE) {
        try { Pop-Location -ErrorAction SilentlyContinue } catch { break }
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

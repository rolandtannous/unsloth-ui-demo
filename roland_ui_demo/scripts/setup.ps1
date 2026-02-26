#Requires -Version 5.1
<#
.SYNOPSIS
    Full environment setup for Unsloth Studio on Windows.
.DESCRIPTION
    Installs Node (if needed), builds the React frontend, creates a venv,
    and installs all Python dependencies in the correct order.
.NOTES
    Usage: powershell -ExecutionPolicy Bypass -File setup.ps1
#>

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReqsDir = Join-Path $ScriptDir "..\..\backend\requirements"

# If running from inside the package (pip installed), ReqsDir won't exist.
# Fall back to the bundled requirements inside the package.
if (-not (Test-Path $ReqsDir)) {
    $ReqsDir = Join-Path $ScriptDir "..\requirements"
}

Write-Host "+==============================================+" -ForegroundColor Green
Write-Host "|       Unsloth Studio Setup (Windows)         |" -ForegroundColor Green
Write-Host "+==============================================+" -ForegroundColor Green

# ============================================
# Step 1: Node.js / npm
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
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    } catch {
        Write-Host "[ERROR] Could not install Node.js automatically." -ForegroundColor Red
        Write-Host "Please install Node.js >= 20 from https://nodejs.org/" -ForegroundColor Red
        exit 1
    }
}

Write-Host "[OK] Node $(node -v) | npm $(npm -v)" -ForegroundColor Green

# ============================================
# Step 2: Build React frontend
# ============================================
Write-Host ""
Write-Host "Building frontend..." -ForegroundColor Cyan

$FrontendDir = Join-Path $ScriptDir "..\..\frontend"
if (Test-Path $FrontendDir) {
    Push-Location $FrontendDir
    npm install 2>&1 | Out-Null
    npm run build 2>&1 | Out-Null
    Pop-Location

    # Copy build into the Python package
    $PackageBuildDir = Join-Path $ScriptDir "..\studio\frontend\build"
    if (Test-Path $PackageBuildDir) { Remove-Item -Recurse -Force $PackageBuildDir }
    Copy-Item -Recurse (Join-Path $FrontendDir "build") $PackageBuildDir

    Write-Host "[OK] Frontend built" -ForegroundColor Green
} else {
    Write-Host "[SKIP] Frontend source not found (likely running from pip install)" -ForegroundColor Yellow
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

# Create venv
$VenvDir = Join-Path $ScriptDir "..\..\..\.venv"
if (Test-Path $VenvDir) { Remove-Item -Recurse -Force $VenvDir }
& $PythonCmd -m venv $VenvDir

# Activate venv
$ActivateScript = Join-Path $VenvDir "Scripts\Activate.ps1"
. $ActivateScript

# Upgrade pip
pip install --upgrade pip 2>&1 | Out-Null

# Copy requirements into the Python package
$ReqsDst = Join-Path $ScriptDir "..\requirements"
if (-not (Test-Path $ReqsDst)) { New-Item -ItemType Directory -Path $ReqsDst | Out-Null }
Copy-Item (Join-Path $ReqsDir "*.txt") $ReqsDst -Force

# Lightweight editable install (CLI entry point)
$ProjectRoot = Join-Path $ScriptDir "..\..\..\"
Write-Host "   Installing CLI entry point..." -ForegroundColor Cyan
pip install -e $ProjectRoot 2>&1 | Out-Null

# Call run_install() directly via Python import (NOT via the CLI,
# because the CLI calls setup.ps1 which would cause recursion)
Write-Host "   Running ordered dependency installation..." -ForegroundColor Cyan
python -c "from roland_ui_demo.installer import run_install; exit(run_install())"

# ============================================
# Step 4: Done
# ============================================
Write-Host ""
Write-Host "+==============================================+" -ForegroundColor Green
Write-Host "|           Setup Complete!                    |" -ForegroundColor Green
Write-Host "|                                              |" -ForegroundColor Green
Write-Host "|  Activate your venv, then:                   |" -ForegroundColor Green
Write-Host "|    .\.venv\Scripts\Activate.ps1              |" -ForegroundColor Green
Write-Host "|    unsloth-roland-test studio                |" -ForegroundColor Green
Write-Host "+==============================================+" -ForegroundColor Green

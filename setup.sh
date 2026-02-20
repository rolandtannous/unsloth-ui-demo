#!/usr/bin/env bash
#
# Full environment setup for Unsloth Studio.
# Installs Node (if needed), builds the React frontend, installs all Python
# dependencies in the correct order, and registers the CLI entry point.
#
# Usage:
#   ./setup.sh
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQS_DIR="$SCRIPT_DIR/backend/requirements"

# ── Helper: run command quietly, show output only on failure ──
run_quiet() {
    local label="$1"
    shift
    local tmplog
    tmplog=$(mktemp)
    if "$@" > "$tmplog" 2>&1; then
        rm -f "$tmplog"
    else
        local exit_code=$?
        echo "❌ $label failed (exit code $exit_code):"
        cat "$tmplog"
        rm -f "$tmplog"
        exit $exit_code
    fi
}

echo "╔══════════════════════════════════════╗"
echo "║     Unsloth Studio Setup Script      ║"
echo "╚══════════════════════════════════════╝"

# ── Detect Colab ──
IS_COLAB=false
keynames=$'\n'$(printenv | cut -d= -f1)
if [[ "$keynames" == *$'\nCOLAB_'* ]]; then
    IS_COLAB=true
fi

# ══════════════════════════════════════════════
# Step 1: Node.js / npm
# ══════════════════════════════════════════════
NEED_NODE=true

if command -v node &>/dev/null && command -v npm &>/dev/null; then
    NODE_MAJOR=$(node -v | sed 's/v//' | cut -d. -f1)
    NPM_MAJOR=$(npm -v | cut -d. -f1)

    if [ "$NODE_MAJOR" -ge 20 ] && [ "$NPM_MAJOR" -ge 11 ]; then
        echo "✅ Node $(node -v) and npm $(npm -v) already meet requirements."
        NEED_NODE=false
    elif [ "$IS_COLAB" = true ]; then
        echo "✅ Node $(node -v) and npm $(npm -v) detected in Colab."
        if [ "$NPM_MAJOR" -lt 11 ]; then
            echo "   Upgrading npm to latest..."
            npm install -g npm@latest > /dev/null 2>&1
        fi
        NEED_NODE=false
    else
        echo "⚠️  Node $(node -v) / npm $(npm -v) too old. Installing via nvm..."
    fi
else
    echo "⚠️  Node/npm not found. Installing via nvm..."
fi

if [ "$NEED_NODE" = true ]; then
    echo "Installing nvm..."
    curl -so- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash > /dev/null 2>&1

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    echo "Installing Node LTS..."
    run_quiet "nvm install" nvm install --lts
    nvm use --lts > /dev/null 2>&1

    NODE_MAJOR=$(node -v | sed 's/v//' | cut -d. -f1)
    NPM_MAJOR=$(npm -v | cut -d. -f1)

    if [ "$NODE_MAJOR" -lt 20 ]; then
        echo "❌ ERROR: Node version must be >= 20 (got $(node -v))"
        exit 1
    fi
    if [ "$NPM_MAJOR" -lt 11 ]; then
        echo "⚠️  npm version is $(npm -v), updating..."
        run_quiet "npm update" npm install -g npm@latest
    fi
fi

echo "✅ Node $(node -v) | npm $(npm -v)"

# ══════════════════════════════════════════════
# Step 2: Build React frontend
# ══════════════════════════════════════════════
echo ""
echo "Building frontend..."
cd "$SCRIPT_DIR/frontend"
run_quiet "npm install" npm install
run_quiet "npm run build" npm run build
cd "$SCRIPT_DIR"

# Copy build into the Python package
PACKAGE_BUILD_DIR="$SCRIPT_DIR/roland_ui_demo/studio/frontend/build"
rm -rf "$PACKAGE_BUILD_DIR"
cp -r "$SCRIPT_DIR/frontend/build" "$PACKAGE_BUILD_DIR"

echo "✅ Frontend built"

# ══════════════════════════════════════════════
# Step 3: Python environment + dependencies
# ══════════════════════════════════════════════
echo ""
echo "Setting up Python environment..."

# ── Find best Python <= 3.12.x ──
BEST_PY=""
BEST_MINOR=0

for candidate in $(compgen -c python3 2>/dev/null | grep -E '^python3(\.[0-9]+)?$' | sort -u); do
    if ! command -v "$candidate" &>/dev/null; then continue; fi

    ver_str=$("$candidate" --version 2>&1 | awk '{print $2}')
    py_major=$(echo "$ver_str" | cut -d. -f1)
    py_minor=$(echo "$ver_str" | cut -d. -f2)

    if [ "$py_major" -ne 3 ] 2>/dev/null; then continue; fi
    if [ "$py_minor" -gt 12 ] 2>/dev/null; then continue; fi

    if [ "$py_minor" -gt "$BEST_MINOR" ]; then
        BEST_PY="$candidate"
        BEST_MINOR="$py_minor"
    fi
done

if [ -z "$BEST_PY" ]; then
    echo "❌ ERROR: No Python version <= 3.12.x found."
    exit 1
fi

BEST_VER=$("$BEST_PY" --version 2>&1 | awk '{print $2}')
echo "✅ Using $BEST_PY ($BEST_VER)"

# ── Install Python deps (ordered!) ──
install_python_deps() {
    run_quiet "pip upgrade" pip install --upgrade pip

    # Copy requirements into the Python package (needed for editable install)
    REQS_DST="$SCRIPT_DIR/roland_ui_demo/requirements"
    mkdir -p "$REQS_DST"
    cp "$REQS_DIR"/*.txt "$REQS_DST/"

    # Lightweight editable install — gets the CLI entry point + lightweight deps
    # (does NOT install unsloth/torch/etc., those are in the requirement files)
    echo "   Installing CLI entry point..."
    run_quiet "pip install -e" pip install -e "$SCRIPT_DIR"

    # Use the CLI's install command for ordered heavy dependency installation
    echo "   Running ordered dependency installation..."
    roland-ui-demo install
}

if [ "$IS_COLAB" = true ]; then
    install_python_deps
    echo "✅ Python dependencies installed"
else
    # Local: create fresh venv
    rm -rf .venv
    "$BEST_PY" -m venv .venv
    source .venv/bin/activate

    install_python_deps
    echo "✅ Python dependencies installed"

    # WSL: pre-install GGUF build dependencies
    if grep -qi microsoft /proc/version 2>/dev/null; then
        echo ""
        echo "⚠️  WSL detected — installing build dependencies for GGUF export..."
        echo "   You may be prompted for your password."
        sudo apt-get update -y
        sudo apt-get install -y build-essential cmake curl git libcurl4-openssl-dev
        echo "✅ GGUF build dependencies installed"
    fi
fi

# ══════════════════════════════════════════════
# Step 4: Done
# ══════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════╗"
echo "║           Setup Complete!            ║"
echo "╠══════════════════════════════════════╣"
if [ "$IS_COLAB" = true ]; then
    echo "║ Ready to start in Colab!             ║"
else
    echo "║ Activate your venv, then:            ║"
    echo "║                                      ║"
    echo "║   source .venv/bin/activate           ║"
    echo "║   roland-ui-demo studio -H 0.0.0.0   ║"
fi
echo "╚══════════════════════════════════════╝"

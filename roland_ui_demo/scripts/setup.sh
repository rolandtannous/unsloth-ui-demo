#!/usr/bin/env bash
#
# Unsloth Studio setup script (bundled version).
#
# When running from a pip-installed package, the frontend is already built
# and bundled — this script only handles Python/venv setup and the ordered
# dependency installation.
#
# When running from the git repo (./setup.sh at repo root), the full version
# handles Node, frontend build, AND dependencies.
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect if we're running from inside a pip-installed package
# (site-packages/roland_ui_demo/scripts/) vs from the git repo root.
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IS_PIP_INSTALL=false
if [ ! -d "$SCRIPT_DIR/../../frontend" ]; then
    IS_PIP_INSTALL=true
fi

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
# Step 1 & 2: Node + Frontend (skip if pip-installed)
# ══════════════════════════════════════════════
if [ "$IS_PIP_INSTALL" = true ]; then
    echo "✅ Running from pip install — frontend already bundled, skipping Node/build"
else
    # ── Node.js / npm ──
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

    # ── Build React frontend ──
    REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    echo ""
    echo "Building frontend..."
    cd "$REPO_ROOT/frontend"
    run_quiet "npm install" npm install
    run_quiet "npm run build" npm run build
    cd "$REPO_ROOT"

    # Copy build into the Python package
    PACKAGE_BUILD_DIR="$REPO_ROOT/roland_ui_demo/studio/frontend/build"
    rm -rf "$PACKAGE_BUILD_DIR"
    cp -r "$REPO_ROOT/frontend/build" "$PACKAGE_BUILD_DIR"

    echo "✅ Frontend built"
fi

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

    if [ "$IS_PIP_INSTALL" = false ]; then
        # Running from repo: copy requirements and do editable install
        REQS_DIR="$(cd "$SCRIPT_DIR/../../backend/requirements" && pwd)"
        REQS_DST="$PACKAGE_DIR/requirements"
        mkdir -p "$REQS_DST"
        cp "$REQS_DIR"/*.txt "$REQS_DST/"

        REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
        echo "   Installing CLI entry point..."
        run_quiet "pip install -e" pip install -e "$REPO_ROOT"
    fi

    # Call run_install() directly via Python import (NOT via the CLI,
    # because the CLI calls setup.sh which would cause recursion)
    echo "   Running ordered dependency installation..."
    python -c "from roland_ui_demo.installer import run_install; exit(run_install())"
}

if [ "$IS_COLAB" = true ]; then
    install_python_deps
    echo "✅ Python dependencies installed"
else
    if [ "$IS_PIP_INSTALL" = false ]; then
        # From repo: create fresh venv
        REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
        rm -rf "$REPO_ROOT/.venv"
        "$BEST_PY" -m venv "$REPO_ROOT/.venv"
        source "$REPO_ROOT/.venv/bin/activate"
    fi

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
# Done
# ══════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════╗"
echo "║           Setup Complete!            ║"
echo "╠══════════════════════════════════════╣"
if [ "$IS_COLAB" = true ]; then
    echo "║ Ready to start in Colab!             ║"
else
    echo "║ Run:                                 ║"
    echo "║   unsloth-roland-test studio         ║"
fi
echo "╚══════════════════════════════════════╝"

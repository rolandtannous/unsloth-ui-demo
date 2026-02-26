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

# Like run_quiet but returns the exit code instead of exiting the script.
# Used for optional build steps (e.g. llama-server) where failure is not fatal.
run_quiet_nofail() {
    local label="$1"
    shift
    local tmplog
    tmplog=$(mktemp)
    if "$@" > "$tmplog" 2>&1; then
        rm -f "$tmplog"
        return 0
    else
        local exit_code=$?
        echo "❌ $label failed (exit code $exit_code):"
        cat "$tmplog"
        rm -f "$tmplog"
        return $exit_code
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
# Step 0: Git (required by pip for git+https:// deps)
# ══════════════════════════════════════════════
if ! command -v git &>/dev/null; then
    echo "⚠️  Git not found — installing..."
    if [ "$IS_COLAB" = true ] || command -v apt-get &>/dev/null; then
        sudo apt-get update -y > /dev/null 2>&1
        sudo apt-get install -y git > /dev/null 2>&1
    elif command -v yum &>/dev/null; then
        sudo yum install -y git > /dev/null 2>&1
    elif command -v brew &>/dev/null; then
        brew install git > /dev/null 2>&1
    else
        echo "❌ ERROR: Git is required. Install it and re-run."
        echo "  https://git-scm.com/downloads"
        exit 1
    fi
fi
echo "✅ Git: $(git --version)"

# ── CMake (needed for building triton kernels and other C++ deps from source) ──
if ! command -v cmake &>/dev/null; then
    echo "⚠️  CMake not found — installing..."
    if [ "$IS_COLAB" = true ] || command -v apt-get &>/dev/null; then
        sudo apt-get update -y > /dev/null 2>&1
        sudo apt-get install -y cmake > /dev/null 2>&1
    elif command -v yum &>/dev/null; then
        sudo yum install -y cmake > /dev/null 2>&1
    elif command -v brew &>/dev/null; then
        brew install cmake > /dev/null 2>&1
    else
        echo "❌ ERROR: CMake is required. Install it and re-run."
        echo "  https://cmake.org/download/"
        exit 1
    fi
fi
echo "✅ CMake: $(cmake --version | head -1)"

# ══════════════════════════════════════════════
# Step 1: Node.js / npm (always — needed regardless of install method)
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
# Step 2: Build React frontend (skip if pip-installed — already bundled)
# ══════════════════════════════════════════════
if [ "$IS_PIP_INSTALL" = true ]; then
    echo "✅ Running from pip install — frontend already bundled, skipping build"
else
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
# Build llama.cpp binaries for GGUF inference + export
# ══════════════════════════════════════════════
# Builds at ~/.unsloth/llama.cpp/ (persistent across pip upgrades).
# We build:
#   - llama-server:   for GGUF model inference
#   - llama-quantize: for GGUF export quantization
LLAMA_CPP_DIR="$HOME/.unsloth/llama.cpp"
LLAMA_SERVER_BIN="$LLAMA_CPP_DIR/build/bin/llama-server"

if [ -f "$LLAMA_SERVER_BIN" ]; then
    echo ""
    echo "✅ llama-server already exists at $LLAMA_SERVER_BIN"
else
    if ! command -v cmake &>/dev/null; then
        echo ""
        echo "⚠️  cmake not found — skipping llama-server build (GGUF inference won't be available)"
        echo "   Install cmake and re-run to enable GGUF inference."
    elif ! command -v git &>/dev/null; then
        echo ""
        echo "⚠️  git not found — skipping llama-server build"
    else
        echo ""
        echo "Building llama-server for GGUF inference..."
        mkdir -p "$HOME/.unsloth"

        BUILD_OK=true
        FAILED_STEP=""

        # -- Step A: Clone or pull llama.cpp --
        if [ -d "$LLAMA_CPP_DIR/.git" ]; then
            echo "   llama.cpp repo already cloned, pulling latest..."
            run_quiet_nofail "pull llama.cpp" git -C "$LLAMA_CPP_DIR" pull || true
        else
            echo "   Cloning llama.cpp..."
            rm -rf "$LLAMA_CPP_DIR"
            if ! run_quiet_nofail "clone llama.cpp" git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "$LLAMA_CPP_DIR"; then
                BUILD_OK=false
                FAILED_STEP="git clone"
            fi
        fi

        # -- Step B: Detect CUDA and run cmake configure --
        if [ "$BUILD_OK" = true ]; then
            CMAKE_ARGS=""
            # Detect CUDA: check nvcc on PATH, then common install locations
            NVCC_PATH=""
            if command -v nvcc &>/dev/null; then
                NVCC_PATH="$(command -v nvcc)"
            elif [ -x /usr/local/cuda/bin/nvcc ]; then
                NVCC_PATH="/usr/local/cuda/bin/nvcc"
                export PATH="/usr/local/cuda/bin:$PATH"
            elif ls /usr/local/cuda-*/bin/nvcc &>/dev/null 2>&1; then
                NVCC_PATH="$(ls -d /usr/local/cuda-*/bin/nvcc 2>/dev/null | sort -V | tail -1)"
                export PATH="$(dirname "$NVCC_PATH"):$PATH"
            fi

            if [ -n "$NVCC_PATH" ]; then
                echo "   Building with CUDA support (nvcc: $NVCC_PATH)..."
                CMAKE_ARGS="-DGGML_CUDA=ON"
            elif [ -d /usr/local/cuda ] || nvidia-smi &>/dev/null; then
                echo "   CUDA driver detected but nvcc not found -- building CPU-only"
                echo "   To enable GPU: install cuda-toolkit or add nvcc to PATH"
            else
                echo "   Building CPU-only (no CUDA detected)..."
            fi

            NCPU=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

            echo "   Running cmake configure..."
            if ! run_quiet_nofail "cmake configure" cmake -S "$LLAMA_CPP_DIR" -B "$LLAMA_CPP_DIR/build" $CMAKE_ARGS; then
                BUILD_OK=false
                FAILED_STEP="cmake configure"
            fi
        fi

        # -- Step C: Build llama-server --
        if [ "$BUILD_OK" = true ]; then
            echo "   Building llama-server (using $NCPU cores)..."
            if ! run_quiet_nofail "build llama-server" cmake --build "$LLAMA_CPP_DIR/build" --config Release --target llama-server -j"$NCPU"; then
                BUILD_OK=false
                FAILED_STEP="cmake build (llama-server)"
            fi
        fi

        # -- Step D: Build llama-quantize (optional, best-effort) --
        if [ "$BUILD_OK" = true ]; then
            echo "   Building llama-quantize..."
            if ! run_quiet_nofail "build llama-quantize" cmake --build "$LLAMA_CPP_DIR/build" --config Release --target llama-quantize -j"$NCPU"; then
                echo "   [WARN] llama-quantize build failed (GGUF export may be unavailable)"
            else
                QUANTIZE_BIN="$LLAMA_CPP_DIR/build/bin/llama-quantize"
                if [ -f "$QUANTIZE_BIN" ]; then
                    ln -sf build/bin/llama-quantize "$LLAMA_CPP_DIR/llama-quantize"
                fi
            fi
        fi

        # -- Summary --
        if [ "$BUILD_OK" = true ] && [ -f "$LLAMA_SERVER_BIN" ]; then
            echo "✅ llama-server built at $LLAMA_SERVER_BIN"
            if [ -f "$LLAMA_CPP_DIR/llama-quantize" ]; then
                echo "✅ llama-quantize available for GGUF export"
            fi
        else
            echo ""
            echo "⚠️  llama-server build failed at step: $FAILED_STEP"
            echo "   GGUF inference won't be available, but everything else works."
            echo "   To retry: delete $LLAMA_CPP_DIR and re-run setup."
        fi
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

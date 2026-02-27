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
# Requires an NVIDIA GPU -- CPU-only machines are not supported.
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
        echo "   [FAILED] $label failed (exit code $exit_code):"
        cat "$tmplog"
        rm -f "$tmplog"
        exit $exit_code
    fi
}

# Like run_quiet but returns the exit code instead of exiting the script.
# Used for optional build steps (e.g. llama-quantize) where failure is not fatal.
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
        echo "   [FAILED] $label failed (exit code $exit_code):"
        cat "$tmplog"
        rm -f "$tmplog"
        return $exit_code
    fi
}

# ── Detect Linux distro family ──
# Returns "debian" (Ubuntu, Debian, Mint, etc.) or "redhat" (RHEL, Fedora, CentOS, etc.)
# or "unknown". No macOS support.
detect_distro() {
    if [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ] || [ -f /etc/fedora-release ]; then
        echo "redhat"
    else
        echo "unknown"
    fi
}

# ── Install C/C++ build dependencies for llama.cpp ──
install_build_deps() {
    local distro
    distro=$(detect_distro)

    echo "   Installing build dependencies ($distro)..."

    if [ "$distro" = "debian" ]; then
        if command -v sudo &>/dev/null; then
            sudo apt-get update -y > /dev/null 2>&1
            sudo apt-get install -y build-essential cmake curl git libcurl4-openssl-dev > /dev/null 2>&1
        else
            apt-get update -y > /dev/null 2>&1
            apt-get install -y build-essential cmake curl git libcurl4-openssl-dev > /dev/null 2>&1
        fi
    elif [ "$distro" = "redhat" ]; then
        if command -v sudo &>/dev/null; then
            sudo dnf install -y gcc gcc-c++ make cmake curl git libcurl-devel > /dev/null 2>&1 || \
                sudo yum install -y gcc gcc-c++ make cmake curl git libcurl-devel > /dev/null 2>&1
        else
            dnf install -y gcc gcc-c++ make cmake curl git libcurl-devel > /dev/null 2>&1 || \
                yum install -y gcc gcc-c++ make cmake curl git libcurl-devel > /dev/null 2>&1
        fi
    else
        echo "   [WARN] Unknown distro -- please install build-essential/cmake/git manually"
    fi
}

# ── Install CUDA Toolkit on Linux (if GPU present but nvcc missing) ──
install_cuda_toolkit() {
    local distro
    distro=$(detect_distro)

    echo "   Installing CUDA Toolkit..."

    if [ "$distro" = "debian" ]; then
        # Use NVIDIA's cuda-keyring approach for apt-based distros
        local os_id os_version_id distro_tag arch
        os_id=$(. /etc/os-release && echo "$ID")
        os_version_id=$(. /etc/os-release && echo "$VERSION_ID")
        distro_tag="${os_id}${os_version_id//./}"
        arch=$(dpkg --print-architecture 2>/dev/null || echo "x86_64")

        local keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/${distro_tag}/${arch}/cuda-keyring_1.1-1_all.deb"
        local tmpdir
        tmpdir=$(mktemp -d)

        echo "   Distro: $distro_tag, Arch: $arch"
        echo "   Downloading cuda-keyring..."

        if command -v wget &>/dev/null; then
            wget -q "$keyring_url" -O "$tmpdir/cuda-keyring.deb" 2>/dev/null
        elif command -v curl &>/dev/null; then
            curl -fsSL "$keyring_url" -o "$tmpdir/cuda-keyring.deb" 2>/dev/null
        else
            echo "   [ERROR] Neither wget nor curl found"
            rm -rf "$tmpdir"
            return 1
        fi

        if [ -f "$tmpdir/cuda-keyring.deb" ]; then
            if command -v sudo &>/dev/null; then
                sudo dpkg -i "$tmpdir/cuda-keyring.deb" > /dev/null 2>&1
                sudo apt-get update -y > /dev/null 2>&1
                sudo apt-get install -y cuda-toolkit > /dev/null 2>&1
            else
                dpkg -i "$tmpdir/cuda-keyring.deb" > /dev/null 2>&1
                apt-get update -y > /dev/null 2>&1
                apt-get install -y cuda-toolkit > /dev/null 2>&1
            fi
        fi
        rm -rf "$tmpdir"

    elif [ "$distro" = "redhat" ]; then
        # Use NVIDIA's dnf/yum repo for RPM-based distros
        local os_version_id distro_tag arch
        os_version_id=$(. /etc/os-release && echo "$VERSION_ID" | cut -d. -f1)
        distro_tag="rhel${os_version_id}"
        arch=$(uname -m)

        local repo_url="https://developer.download.nvidia.com/compute/cuda/repos/${distro_tag}/${arch}/cuda-${distro_tag}.repo"

        echo "   Distro: $distro_tag, Arch: $arch"

        if command -v sudo &>/dev/null; then
            sudo dnf config-manager --add-repo "$repo_url" 2>/dev/null || true
            sudo dnf install -y cuda-toolkit > /dev/null 2>&1
        else
            dnf config-manager --add-repo "$repo_url" 2>/dev/null || true
            dnf install -y cuda-toolkit > /dev/null 2>&1
        fi
    else
        echo "   [WARN] Cannot auto-install CUDA Toolkit on unknown distro"
        return 1
    fi

    # Add CUDA to PATH
    if [ -d /usr/local/cuda/bin ]; then
        export PATH="/usr/local/cuda/bin:$PATH"
    fi
}

# ── Detect CUDA compute capability via nvidia-smi ──
# Returns e.g. "80" for A100 (8.0), "89" for RTX 4090 (8.9), etc.
# Returns empty string if detection fails.
get_cuda_compute_capability() {
    if ! command -v nvidia-smi &>/dev/null; then
        echo ""
        return
    fi

    local raw
    raw=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '[:space:]')

    if [[ "$raw" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    else
        echo ""
    fi
}

echo "+==============================================+"
echo "|      Unsloth Studio Setup (Linux)            |"
echo "+==============================================+"

# ── Detect Colab ──
IS_COLAB=false
keynames=$'\n'$(printenv | cut -d= -f1)
if [[ "$keynames" == *$'\nCOLAB_'* ]]; then
    IS_COLAB=true
fi

# ══════════════════════════════════════════════
# Step 0: GPU requirement check
# ══════════════════════════════════════════════
if ! command -v nvidia-smi &>/dev/null; then
    echo ""
    echo "[ERROR] Unsloth Studio requires an NVIDIA GPU."
    echo "        CPU-only machines are not supported."
    echo ""
    echo "        If you have an NVIDIA GPU, ensure the driver is installed:"
    echo "        https://www.nvidia.com/Download/index.aspx"
    exit 1
fi
echo "[OK] NVIDIA GPU detected"

# ══════════════════════════════════════════════
# Step 1: Build dependencies (git, cmake, build-essential)
# ══════════════════════════════════════════════
NEEDS_BUILD_DEPS=false
if ! command -v git &>/dev/null; then NEEDS_BUILD_DEPS=true; fi
if ! command -v cmake &>/dev/null; then NEEDS_BUILD_DEPS=true; fi
if ! command -v gcc &>/dev/null && ! command -v cc &>/dev/null; then NEEDS_BUILD_DEPS=true; fi

if [ "$NEEDS_BUILD_DEPS" = true ]; then
    install_build_deps
fi

if ! command -v git &>/dev/null; then
    echo "[ERROR] Git is required. Install it and re-run."
    echo "  https://git-scm.com/downloads"
    exit 1
fi
echo "[OK] Git: $(git --version)"

if ! command -v cmake &>/dev/null; then
    echo "[ERROR] CMake is required. Install it and re-run."
    echo "  https://cmake.org/download/"
    exit 1
fi
echo "[OK] CMake: $(cmake --version | head -1)"

# ══════════════════════════════════════════════
# Step 2: Node.js / npm (always -- needed regardless of install method)
# ══════════════════════════════════════════════
NEED_NODE=true

if command -v node &>/dev/null && command -v npm &>/dev/null; then
    NODE_MAJOR=$(node -v | sed 's/v//' | cut -d. -f1)
    NPM_MAJOR=$(npm -v | cut -d. -f1)

    if [ "$NODE_MAJOR" -ge 20 ] && [ "$NPM_MAJOR" -ge 11 ]; then
        echo "[OK] Node $(node -v) and npm $(npm -v) already meet requirements."
        NEED_NODE=false
    elif [ "$IS_COLAB" = true ]; then
        echo "[OK] Node $(node -v) and npm $(npm -v) detected in Colab."
        if [ "$NPM_MAJOR" -lt 11 ]; then
            echo "   Upgrading npm to latest..."
            npm install -g npm@latest > /dev/null 2>&1
        fi
        NEED_NODE=false
    else
        echo "[WARN] Node $(node -v) / npm $(npm -v) too old. Installing via nvm..."
    fi
else
    echo "[WARN] Node/npm not found. Installing via nvm..."
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
        echo "[ERROR] Node version must be >= 20 (got $(node -v))"
        exit 1
    fi
    if [ "$NPM_MAJOR" -lt 11 ]; then
        echo "[WARN] npm version is $(npm -v), updating..."
        run_quiet "npm update" npm install -g npm@latest
    fi
fi

echo "[OK] Node $(node -v) | npm $(npm -v)"

# ══════════════════════════════════════════════
# Step 3: Build React frontend (skip if pip-installed -- already bundled)
# ══════════════════════════════════════════════
if [ "$IS_PIP_INSTALL" = true ]; then
    echo "[OK] Running from pip install -- frontend already bundled, skipping build"
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

    echo "[OK] Frontend built"
fi

# ══════════════════════════════════════════════
# Step 4: Python environment + dependencies
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
    echo "[ERROR] No Python version <= 3.12.x found."
    exit 1
fi

BEST_VER=$("$BEST_PY" --version 2>&1 | awk '{print $2}')
echo "[OK] Using $BEST_PY ($BEST_VER)"

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
    echo "[OK] Python dependencies installed"
else
    if [ "$IS_PIP_INSTALL" = false ]; then
        # From repo: create fresh venv
        REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
        rm -rf "$REPO_ROOT/.venv"
        "$BEST_PY" -m venv "$REPO_ROOT/.venv"
        source "$REPO_ROOT/.venv/bin/activate"
    fi

    install_python_deps
    echo "[OK] Python dependencies installed"
fi

# ══════════════════════════════════════════════
# Step 5: Build llama.cpp with CUDA for GGUF inference + export
# ══════════════════════════════════════════════
# Builds at ~/.unsloth/llama.cpp/ (persistent across pip upgrades).
# We build:
#   - llama-server:   for GGUF model inference
#   - llama-quantize: for GGUF export quantization
LLAMA_CPP_DIR="$HOME/.unsloth/llama.cpp"
LLAMA_SERVER_BIN="$LLAMA_CPP_DIR/build/bin/llama-server"

if [ -f "$LLAMA_SERVER_BIN" ]; then
    echo ""
    echo "[OK] llama-server already exists at $LLAMA_SERVER_BIN"
else
    # -- CUDA Toolkit: detect or auto-install --
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

    if [ -z "$NVCC_PATH" ]; then
        echo ""
        echo "   CUDA driver detected but toolkit (nvcc) not found."
        echo "   Attempting to install CUDA Toolkit..."
        install_cuda_toolkit
        # Re-check
        if command -v nvcc &>/dev/null; then
            NVCC_PATH="$(command -v nvcc)"
        elif [ -x /usr/local/cuda/bin/nvcc ]; then
            NVCC_PATH="/usr/local/cuda/bin/nvcc"
            export PATH="/usr/local/cuda/bin:$PATH"
        fi
    fi

    if [ -z "$NVCC_PATH" ]; then
        echo "[ERROR] CUDA Toolkit (nvcc) is required but could not be found or installed." >&2
        echo "        Install CUDA Toolkit from https://developer.nvidia.com/cuda-downloads" >&2
        exit 1
    fi

    echo "[OK] CUDA Toolkit: $NVCC_PATH"

    # Detect compute capability
    CUDA_ARCH=$(get_cuda_compute_capability)
    if [ -n "$CUDA_ARCH" ]; then
        echo "   Compute Capability = ${CUDA_ARCH:0:${#CUDA_ARCH}-1}.${CUDA_ARCH: -1} (sm_$CUDA_ARCH)"
    else
        echo "   [WARN] Could not detect compute capability -- cmake will use defaults"
    fi

    echo ""
    echo "Building llama.cpp with CUDA support..."
    echo "   This typically takes 5-10 minutes on first build."
    echo ""

    # Start build timer
    BUILD_START_TIME=$(date +%s)

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

    # -- Step B: cmake configure (CUDA + Unsloth flags) --
    if [ "$BUILD_OK" = true ]; then
        echo ""
        echo "--- cmake configure ---"

        CMAKE_ARGS=(
            -S "$LLAMA_CPP_DIR"
            -B "$LLAMA_CPP_DIR/build"
            -DBUILD_SHARED_LIBS=OFF
            -DLLAMA_CURL=OFF
            -DGGML_CUDA=ON
            -DGGML_CUDA_FA_ALL_QUANTS=ON
            -DGGML_CUDA_F16=OFF
            -DGGML_CUDA_GRAPHS=OFF
            -DGGML_CUDA_FORCE_CUBLAS=OFF
            -DGGML_CUDA_PEER_MAX_BATCH_SIZE=8192
        )
        if [ -n "$CUDA_ARCH" ]; then
            CMAKE_ARGS+=("-DCMAKE_CUDA_ARCHITECTURES=$CUDA_ARCH")
        fi

        echo "   cmake args:"
        for arg in "${CMAKE_ARGS[@]}"; do
            echo "     $arg"
        done
        echo ""

        if ! cmake "${CMAKE_ARGS[@]}"; then
            BUILD_OK=false
            FAILED_STEP="cmake configure"
        fi
    fi

    # -- Step C: Build llama-server --
    NCPU=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    # Reduce parallelism on Colab to avoid OOM
    if [ "$IS_COLAB" = true ] && [ "$NCPU" -gt 2 ]; then
        NCPU=2
    fi

    if [ "$BUILD_OK" = true ]; then
        echo ""
        echo "--- cmake build (llama-server) ---"
        echo "   Parallel jobs: $NCPU"
        echo ""

        if ! cmake --build "$LLAMA_CPP_DIR/build" --config Release --target llama-server -j"$NCPU"; then
            BUILD_OK=false
            FAILED_STEP="cmake build (llama-server)"
        fi
    fi

    # -- Step D: Build llama-quantize (optional, best-effort) --
    if [ "$BUILD_OK" = true ]; then
        echo ""
        echo "--- cmake build (llama-quantize) ---"
        if ! cmake --build "$LLAMA_CPP_DIR/build" --config Release --target llama-quantize -j"$NCPU"; then
            echo "   [WARN] llama-quantize build failed (GGUF export may be unavailable)"
        else
            QUANTIZE_BIN="$LLAMA_CPP_DIR/build/bin/llama-quantize"
            if [ -f "$QUANTIZE_BIN" ]; then
                ln -sf build/bin/llama-quantize "$LLAMA_CPP_DIR/llama-quantize"
            fi
        fi
    fi

    # Build timing
    BUILD_END_TIME=$(date +%s)
    BUILD_ELAPSED=$((BUILD_END_TIME - BUILD_START_TIME))
    BUILD_MIN=$((BUILD_ELAPSED / 60))
    BUILD_SEC=$((BUILD_ELAPSED % 60))

    # -- Summary --
    echo ""
    if [ "$BUILD_OK" = true ] && [ -f "$LLAMA_SERVER_BIN" ]; then
        echo "[OK] llama-server built at $LLAMA_SERVER_BIN"
        if [ -f "$LLAMA_CPP_DIR/llama-quantize" ] || [ -f "$LLAMA_CPP_DIR/build/bin/llama-quantize" ]; then
            echo "[OK] llama-quantize available for GGUF export"
        fi
        echo "   Build time: ${BUILD_MIN}m ${BUILD_SEC}s"
    else
        echo "[FAILED] llama.cpp build failed at step: $FAILED_STEP (${BUILD_MIN}m ${BUILD_SEC}s)"
        echo "         To retry: delete $LLAMA_CPP_DIR and re-run setup."
        exit 1
    fi
fi

# ══════════════════════════════════════════════
# Done
# ══════════════════════════════════════════════
echo ""
echo "+==============================================+"
echo "|           Setup Complete!                    |"
echo "+----------------------------------------------+"
if [ "$IS_COLAB" = true ]; then
    echo "| Ready to start in Colab!                     |"
else
    echo "| Run:                                         |"
    echo "|   unsloth-roland-test studio                 |"
fi
echo "+==============================================+"

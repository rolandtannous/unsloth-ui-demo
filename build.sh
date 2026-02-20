#!/usr/bin/env bash
#
# Build script: compiles the React frontend, bundles it into the Python package,
# and builds a wheel ready for PyPI upload.
#
# Usage:
#   ./build.sh          # Build wheel only
#   ./build.sh publish   # Build wheel and upload to PyPI
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRONTEND_DIR="$SCRIPT_DIR/frontend"
PACKAGE_BUILD_DIR="$SCRIPT_DIR/roland_ui_demo/studio/frontend/build"

echo "=== Step 1: Build React frontend ==="
cd "$FRONTEND_DIR"

if [ ! -d "node_modules" ]; then
    echo "Installing npm dependencies..."
    npm install
fi

echo "Building frontend..."
npm run build

echo "=== Step 2: Copy frontend build into Python package ==="
rm -rf "$PACKAGE_BUILD_DIR"
cp -r "$FRONTEND_DIR/build" "$PACKAGE_BUILD_DIR"
echo "Copied to $PACKAGE_BUILD_DIR"

echo "=== Step 3: Build Python wheel ==="
cd "$SCRIPT_DIR"

# Clean previous builds
rm -rf dist/ build/ *.egg-info

python -m build

echo ""
echo "=== Build complete ==="
echo "Wheel: $(ls dist/*.whl)"
echo "Sdist: $(ls dist/*.tar.gz)"

if [ "${1:-}" = "publish" ]; then
    echo ""
    echo "=== Step 4: Upload to PyPI ==="
    python -m twine upload dist/*
    echo "Published to PyPI!"
fi

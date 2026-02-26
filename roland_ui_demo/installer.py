"""Ordered pip installer for unsloth dependencies.

Runs the 6 requirement files in the correct order with the correct pip flags,
replicating what setup.sh does but from Python so it can ship inside a wheel.

When called via the CLI (`unsloth-roland-test studio install`), detects the OS
and runs the appropriate setup script (setup.sh on Linux/macOS, setup.ps1 on
Windows). The setup script handles Node, frontend, venv, then calls back into
run_install() directly for the ordered pip steps.
"""

import platform
import subprocess
import sys
import urllib.request
from pathlib import Path
from typing import Optional

IS_WINDOWS = platform.system() == "Windows"

# Packages that are skipped on Windows (via environment markers in requirements)
# but may need manual installation. Listed here to print helpful warnings.
WINDOWS_SKIPPED_PACKAGES = {
    "open_spiel": "https://openspiel.readthedocs.io/en/latest/windows.html",
}

from roland_ui_demo.requirements import get_requirements_dir
from roland_ui_demo.scripts import get_scripts_dir

# The 6 install steps in exact order.
# Each tuple: (label, filename, extra_pip_flags)
INSTALL_STEPS = [
    (
        "Installing base packages (unsloth-zoo + unsloth)",
        "base.txt",
        [],
    ),
    (
        "Installing extras",
        "extras.txt",
        ["--no-cache-dir"],
    ),
    (
        "Installing extras (no-deps)",
        "extras-no-deps.txt",
        ["--no-deps", "--no-cache-dir"],
    ),
    (
        "Force-reinstalling overrides (torchao, transformers)",
        "overrides.txt",
        ["--force-reinstall", "--no-cache-dir"],
    ),
    (
        "Installing triton kernels (no-deps, from source)",
        "triton-kernels.txt",
        ["--no-deps"],
    ),
    (
        "Installing studio dependencies",
        "studio.txt",
        [],
    ),
]

LLAMA_CPP_URL = (
    "https://raw.githubusercontent.com/unslothai/unsloth-zoo"
    "/refs/heads/main/unsloth_zoo/llama_cpp.py"
)


def _run_pip(args: list, dry_run: bool = False) -> None:
    """Run a pip command using the current interpreter's pip."""
    cmd = [sys.executable, "-m", "pip"] + args
    if dry_run:
        print(f"  [dry-run] Would run: {' '.join(cmd)}")
        return
    result = subprocess.run(cmd, check=False)
    if result.returncode != 0:
        raise RuntimeError(
            f"pip command failed (exit code {result.returncode}): {' '.join(cmd)}"
        )


def _find_llama_cpp_destination() -> Optional[Path]:
    """Find the installed unsloth_zoo/llama_cpp.py location."""
    result = subprocess.run(
        [sys.executable, "-m", "pip", "show", "unsloth-zoo"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    for line in result.stdout.splitlines():
        if line.lower().startswith("location:"):
            location = line.split(":", 1)[1].strip()
            return Path(location) / "unsloth_zoo" / "llama_cpp.py"
    return None


def _apply_llama_cpp_patch(dry_run: bool = False) -> None:
    """Download and overwrite llama_cpp.py from unsloth-zoo main branch."""
    dst = _find_llama_cpp_destination()
    if dst is None:
        print("  ⚠️  Could not locate unsloth-zoo installation. Skipping patch.")
        return

    if dry_run:
        print(f"  [dry-run] Would download {LLAMA_CPP_URL}")
        print(f"  [dry-run] Would overwrite {dst}")
        return

    print(f"  Downloading llama_cpp.py patch...")
    print(f"  Destination: {dst}")
    try:
        urllib.request.urlretrieve(LLAMA_CPP_URL, str(dst))
        print(f"  ✅ Patch applied.")
    except Exception as e:
        print(f"  ⚠️  Patch download failed: {e}")
        print(f"  You can skip this with --skip-patch and apply it manually later.")


def run_setup(dry_run: bool = False) -> int:
    """
    Detect OS and run the appropriate platform setup script.

    Linux/macOS → setup.sh (bash)
    Windows     → setup.ps1 (PowerShell)

    The setup script handles Node, frontend build, venv creation, then
    calls run_install() directly for the ordered pip steps.

    Returns 0 on success, non-zero on failure.
    """
    scripts_dir = get_scripts_dir()
    system = platform.system()

    if system == "Windows":
        script = scripts_dir / "setup.ps1"
        cmd = ["powershell", "-ExecutionPolicy", "Bypass", "-File", str(script)]
    else:
        script = scripts_dir / "setup.sh"
        cmd = ["bash", str(script)]

    if not script.exists():
        print(f"❌ Setup script not found: {script}")
        return 1

    print(f"Detected platform: {system}")
    print(f"Running: {script.name}")
    print()

    if dry_run:
        print(f"[dry-run] Would run: {' '.join(cmd)}")
        return 0

    result = subprocess.run(cmd, check=False)
    return result.returncode


def run_install(
    skip_patch: bool = False,
    dry_run: bool = False,
) -> int:
    """
    Run the 6 ordered pip install steps.

    This is called either:
    - Directly by setup.sh/setup.ps1 (after they handle Node/frontend/venv)
    - Directly by a user who already has a venv and just needs the pip steps

    Returns 0 on success, 1 on failure.
    """
    reqs_dir = get_requirements_dir()
    total = len(INSTALL_STEPS)

    print("=" * 50)
    print("  unsloth-roland-test studio install")
    print("  Ordered dependency installation")
    print("=" * 50)
    print()

    if dry_run:
        print("[DRY RUN MODE — no changes will be made]")
        print()

    # Upgrade pip first
    print("Upgrading pip...")
    try:
        _run_pip(["install", "--upgrade", "pip"], dry_run=dry_run)
    except RuntimeError as e:
        print(f"⚠️  {e}")
        print("Continuing anyway...")
    print()

    for i, (label, filename, flags) in enumerate(INSTALL_STEPS, 1):
        req_file = reqs_dir / filename
        if not req_file.exists():
            print(f"[{i}/{total}] ❌ ERROR: {req_file} not found!")
            print(f"  Requirements files may not be bundled. Are you running from")
            print(f"  a proper install? Try: pip install unsloth-roland-test")
            return 1

        print(f"[{i}/{total}] {label}...")
        try:
            pip_args = ["install"] + flags + ["-r", str(req_file)]
            _run_pip(pip_args, dry_run=dry_run)
        except RuntimeError as e:
            print(f"❌ {e}")
            return 1

        # After extras step: notify about Windows source builds
        if i == 2 and IS_WINDOWS and WINDOWS_SKIPPED_PACKAGES:
            print("  ⚠️  The following pip packages were skipped (no pre-built wheel):")
            for pkg in WINDOWS_SKIPPED_PACKAGES:
                print(f"     - {pkg}")
            print("  Will attempt to build from source after pip steps complete.")
            print()

        # Apply patch after step 5 (triton-kernels), before step 6 (studio)
        if i == 5 and not skip_patch:
            print()
            print("Applying llama_cpp.py patch...")
            _apply_llama_cpp_patch(dry_run=dry_run)

        print()

    print("=" * 50)
    print("  ✅ Installation complete!")
    print("=" * 50)
    return 0

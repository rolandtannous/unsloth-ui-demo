"""Bundled setup scripts for platform-specific installation."""

from pathlib import Path

SCRIPTS_DIR = Path(__file__).parent


def get_scripts_dir() -> Path:
    """Return the directory containing the bundled setup scripts."""
    return SCRIPTS_DIR

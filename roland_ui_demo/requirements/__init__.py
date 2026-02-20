"""Package data: requirements files for the ordered install sequence."""

from pathlib import Path

REQUIREMENTS_DIR = Path(__file__).parent


def get_requirements_dir() -> Path:
    """Return the directory containing the bundled requirements .txt files."""
    return REQUIREMENTS_DIR

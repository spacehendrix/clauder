"""Helpers for locating the project `.claude` directory."""

from pathlib import Path
from typing import Optional


def find_claude_directory(start: Optional[Path] = None) -> Optional[Path]:
    """Return the nearest ancestor directory that contains a `.claude` folder."""
    current = (start or Path.cwd()).resolve()
    if current.is_file():
        current = current.parent

    for directory in [current, *current.parents]:
        if (directory / '.claude').is_dir():
            return directory

    return None

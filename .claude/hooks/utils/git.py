"""Git repository detection helpers."""

import subprocess
from typing import Optional


def is_git_repository(cwd: Optional[str] = None) -> bool:
    """Return True if cwd (or the current directory) is inside a git work tree."""
    result = subprocess.run(
        ['git', 'rev-parse', '--is-inside-work-tree'],
        capture_output=True,
        text=True,
        cwd=cwd,
    )
    return result.returncode == 0 and result.stdout.strip() == 'true'

# Make this directory a Python package
from .trace_decision import log_decision
from .git import is_git_repository
from .claude import find_claude_directory

__all__ = ['log_decision', 'is_git_repository', 'find_claude_directory']

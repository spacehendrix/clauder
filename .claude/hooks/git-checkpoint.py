#!/usr/bin/env python3
"""
Create a git checkpoint.
This script is called before user prompt submission to commit current changes.
"""

import subprocess
import sys
import os
import json
from utils.git import is_git_repository


def load_preferences():
    """Load preferences from preferences.json file."""
    try:
        prefs_path = '.claude/preferences.json'
        if os.path.exists(prefs_path):
            with open(prefs_path, 'r') as f:
                return json.load(f)
        return {}
    except Exception:
        return {}


def main():
    """Main function to create git checkpoint."""
    try:
        # Check if automated git commits are enabled
        preferences = load_preferences()
        automated_commits_enabled = preferences.get('automated_git_commits', {}).get('enabled', True)
        
        if not automated_commits_enabled:
            print("Automated git commits disabled. Skipping git checkpoint.", file=sys.stderr)
            sys.exit(0)
        
        # Check if we're in a git repository
        if not is_git_repository():
            print("Not in a git repository. Skipping git checkpoint.", file=sys.stderr)
            sys.exit(0)
        
        # Check if there are any changes to commit
        result = subprocess.run(['git', 'status', '--porcelain'], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"Error checking git status: {result.stderr}", file=sys.stderr)
            sys.exit(1)
        
        # If no changes, skip commit
        if not result.stdout.strip():
            print("No changes to commit. Skipping git checkpoint.", file=sys.stderr)
            sys.exit(0)
        
        # Add all changes
        add_result = subprocess.run(['git', 'add', '--all'], capture_output=True, text=True)
        if add_result.returncode != 0:
            print(f"Error adding files to git: {add_result.stderr}", file=sys.stderr)
            sys.exit(1)
        
        # Create commit message
        commit_message = f"[claude] checkpoint"
        
        # Commit changes
        commit_result = subprocess.run(['git', 'commit', '-m', commit_message], capture_output=True, text=True)
        if commit_result.returncode != 0:
            print(f"Error committing changes: {commit_result.stderr}", file=sys.stderr)
            sys.exit(1)
        
        print(f"Git checkpoint created: {commit_message}", file=sys.stderr)
        sys.exit(0)
        
    except Exception as e:
        # Log error but don't block the operation
        print(f"Error in git-checkpoint: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main() 
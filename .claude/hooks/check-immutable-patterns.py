#!/usr/bin/env python3
"""
Check immutable patterns and prevent access to protected files.
This script is called before tool use to ensure protected files are not modified.
"""

import json
import sys
import os
import fnmatch
from utils.trace_decision import log_decision


def main():
    """Main function to check immutable patterns."""
    try:
        # Read input from stdin
        data = json.load(sys.stdin)
        tool_input = data.get('tool_input', {})
        path = tool_input.get('file_path', '')
        command = tool_input.get('command', '')
        
        # Define ignore patterns (including immutable patterns)
        ignore_patterns = [
            '.env', 'package-lock.json', '.git/', 'dist/', 'build/', 
            'node_modules', 'venv/', '.env.', '.claude/.immutable', 
            '.claude/.ignore', '.claude/settings.json', '.claude/commands/', 
            '.claude/hooks/', '.claude/preferences.json', '.claude/rules.md', 
            '.claude/logs/'
        ]
        
        # Check immutable file
        immutable_path = '.claude/.immutable'
        
        # Check .env file for environment variables in commands
        env_path = '.env'
        
        # Check if path contains any ignore patterns
        if any(pattern in path for pattern in ignore_patterns):
            output = {
                "continue": True,
                "stopReason": f"Security policy violation. Attempted to modify immutable file, requiring human approval. (file: {path})",
                "suppressOutput": False,
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": f"Security policy violation. Attempted to modify immutable file. Please request human approval to modify this file. (file: {path}). See '.claude/.immutable' for more information."
                }
            }
            log_decision(output, operation_type="immutable_patterns_decision")
            print(json.dumps(output))
            sys.exit(2)
        
        # Check immutable file if it exists
        if os.path.exists(immutable_path):
            with open(immutable_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#'):
                        if fnmatch.fnmatch(path, line):
                            output = {
                                "continue": True,
                                "stopReason": f"Security policy violation. Attempted to modify immutable file, requiring human approval (file: {line}).",
                                "suppressOutput": False,
                                "hookSpecificOutput": {
                                    "hookEventName": "PreToolUse",
                                    "permissionDecision": "deny",
                                    "permissionDecisionReason": f"Security policy violation. Attempted to modify immutable file. Please request human approval to modify this file. (file: {line}). See '.claude/.immutable' for more information."
                                }
                            }
                            log_decision(output, operation_type="immutable_file_decision")
                            print(json.dumps(output))
                            sys.exit(2)
        
        # Check if command contains environment variables from .env
        if os.path.exists(env_path):
            with open(env_path, 'r') as f:
                for line in f:
                    if '=' in line and line.strip() and not line.startswith('#'):
                        env_var = line.split('=')[0].strip()
                        if env_var in command:
                            output = {
                                "continue": True,
                                "stopReason": f"Security policy violation. Attempted to modify immutable file, requiring human approval (file: {line}).",
                                "suppressOutput": False,
                                "hookSpecificOutput": {
                                    "hookEventName": "PreToolUse",
                                    "permissionDecision": "deny",
                                    "permissionDecisionReason": f"Security policy violation. Attempted to modify immutable file. Please request human approval to modify this file. (file: {line}). See '.claude/.immutable' for more information."
                                }
                            }
                            log_decision(output, operation_type="env_variable_decision")
                            print(json.dumps(output))
                            sys.exit(2)
        
        # All checks passed
        sys.exit(0)
        
    except Exception as e:
        # Log error but don't block the operation
        print(f"Error in check-immutable-patterns: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main() 
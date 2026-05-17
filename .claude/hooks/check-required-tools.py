#!/usr/bin/env python3
"""
Check for required tools and git repository.
This script is called before user prompt submission to ensure required tools are available.
"""

import subprocess
import sys
import json
from utils.trace_decision import log_decision
from utils.git import is_git_repository

def load_preferences():
    """Load preferences from .claude/preferences.json"""
    try:
        with open('.claude/preferences.json', 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        # Return default preferences if file doesn't exist or is invalid
        return {"git_requirement_checks": {"enabled": True}}

def main():
    """Main function to check required tools."""
    try:
        # Load preferences
        preferences = load_preferences()
        git_checks_enabled = preferences.get("git_requirement_checks", {}).get("enabled", True)
        
        # Define required tools
        required_tools = ['jq']  # Always require jq
        if git_checks_enabled:
            required_tools.append('git')
        
        # Check if tools are available
        missing_tools = []
        for tool in required_tools:
            result = subprocess.run(['which', tool], capture_output=True)
            if result.returncode != 0:
                missing_tools.append(tool)
        
        # Check if we're in a git repository (only if git checks are enabled)
        if git_checks_enabled and not is_git_repository():
            missing_tools.append('git repository (run `git init` to create one)')
        
        # If any tools are missing, exit with error
        if missing_tools:
            missing_tools_str = ", ".join(missing_tools)
            output = {
                "continue": False,
                "stopReason": f"Missing required tools: {missing_tools_str}",
                "suppressOutput": False,
                "decision": "block",
                "reason": f"Missing required tools: {missing_tools_str}"
            }
            log_decision(output, operation_type="required_tools_decision")
            print(json.dumps(output))
            sys.exit(2)
        
        # All tools are available
        sys.exit(0)
        
    except Exception as e:
        # Log error and exit with error code
        output = {
            "continue": False,
            "stopReason": f"Error in check-required-tools: {e}",
            "suppressOutput": False,
            "decision": "block",
            "reason": f"Error in check-required-tools: {e}"
        }
        log_decision(output, operation_type="required_tools_error_decision")
        print(json.dumps(output))
        sys.exit(2)


if __name__ == "__main__":
    main() 
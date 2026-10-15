#!/usr/bin/env python3
import json
import sys
import os
import subprocess
import platform
import time
from utils.trace_decision import log_decision

def check_command_available(command):
    """Check if a command is available in the system PATH."""
    try:
        # Use 'which' to check if command exists (works on Unix-like systems)
        result = subprocess.run(['which', command], capture_output=True, text=True)
        return result.returncode == 0
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False

def get_preferences():
    """Read preferences from .claude/preferences.json."""
    try:
        with open('.claude/preferences.json', 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}

def setup_say_command():
    """Setup the say command for different operating systems."""
    if check_command_available('say'):
        return True
    
    # Check if we're on Linux and espeak is available
    if platform.system() == 'Linux' and check_command_available('espeak'):
        # Define alias for Linux
        os.system('alias say="echo \\"$1\\" | espeak -s 120 2>/dev/null"')
        return True
    
    return False

def check_session_lock():
    """Check if audio summary has already been triggered in this session."""
    tmp_dir = '.claude/.tmp'
    lock_file = os.path.join(tmp_dir, 'audio-summary.lock')
    
    # Check if lock file exists and is recent (within last 60 seconds)
    if os.path.exists(lock_file):
        try:
            with open(lock_file, 'r') as f:
                timestamp = float(f.read().strip())
            # If lock is less than 60 seconds old, consider it active
            if time.time() - timestamp < 60:
                return True
            else:
                # Lock is old, clear it
                clear_session_lock()
        except (ValueError, IOError):
            pass
    
    return False

def clear_session_lock():
    """Clear the session lock file."""
    tmp_dir = '.claude/.tmp'
    lock_file = os.path.join(tmp_dir, 'audio-summary.lock')
    try:
        if os.path.exists(lock_file):
            os.remove(lock_file)
    except IOError:
        pass

def create_session_lock():
    """Create a session lock to prevent multiple audio summaries."""
    tmp_dir = '.claude/.tmp'
    lock_file = os.path.join(tmp_dir, 'audio-summary.lock')
    
    # Create .tmp directory if it doesn't exist
    try:
        os.makedirs(tmp_dir, exist_ok=True)
    except IOError:
        pass
    
    try:
        with open(lock_file, 'w') as f:
            f.write(str(time.time()))
    except IOError:
        pass

def main():
    # Check if jq is available
    if not check_command_available('jq'):
        print("jq is not available. Please install jq to use this script.")
        sys.exit(1)
    
    # Read preferences
    preferences = get_preferences()
    
    # Check if audio summary is enabled
    audio_summary = preferences.get('audio_summary', {})
    if not audio_summary.get('enabled', False):
        sys.exit(0)
    
    # Check if we've already triggered audio summary in this session
    if check_session_lock():
        # Already triggered, exit silently without clearing lock
        sys.exit(0)
    
    # Setup say command
    if not setup_say_command():
        print("say command is not available. Please install say or espeak to use this script.")
        sys.exit(1)
    
    # Create session lock to prevent infinite loop
    create_session_lock()
    
    # Require audio summary only once per session
    output = {
        "continue": True,
        "stopReason": "Audio summary required.",
        "suppressOutput": True,
        "decision": "block",
        "reason": (
            "Audio summary required. Speak a short version of the written response you just gave, so the user understands "
            "the same information without reading it: what was done or found, what is being asked of them if anything, and "
            "what happens or should happen next. Cover every point the user needs to act on; leave out details they would "
            "only need if they chose to read. Keep it fairly short and in plain spoken language, with no file paths, code, "
            "identifiers, markdown or lists. There is no fixed sentence limit; say what is needed and stop. Then run the "
            "say command directly with that text in single quotes, such as: say 'your summary'. Avoid apostrophes and "
            "quotes inside the text. Do not create files or scripts, and do not write anything further after speaking."
        )
    }
    log_decision(output, operation_type="audio_summary_decision")
    print(json.dumps(output))
    sys.exit(2)

if __name__ == "__main__":
    main() 
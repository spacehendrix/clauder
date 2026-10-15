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

def resolve_speech_command():
    """Return the shell command that speaks text on this machine, or None.

    macOS ships `say`. On Linux the common choices are `espeak-ng` and
    `espeak`; both take the text as a positional argument, so the same
    quoting instructions apply. The returned string is a command prefix:
    the caller appends the quoted text.
    """
    if check_command_available('say'):
        return 'say'
    if platform.system() == 'Linux':
        for candidate in ('espeak-ng', 'espeak'):
            if check_command_available(candidate):
                return f'{candidate} -s 120'
    return None

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
    
    # Resolve the speech command for this machine
    speech_command = resolve_speech_command()
    if speech_command is None:
        print("No speech command available. Install `say` (macOS) or `espeak-ng`/`espeak` (Linux) to use audio summaries.", file=sys.stderr)
        sys.exit(0)
    
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
            "identifiers, markdown or lists. There is no fixed sentence limit; say what is needed and stop. Then run this "
            f"exact command directly, with your text in single quotes: {speech_command} 'your summary'. Avoid apostrophes and "
            "quotes inside the text. Do not create files or scripts, and do not write anything further after speaking."
        )
    }
    log_decision(output, operation_type="audio_summary_decision")
    print(json.dumps(output))
    sys.exit(2)

if __name__ == "__main__":
    main() 
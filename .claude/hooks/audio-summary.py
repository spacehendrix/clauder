#!/usr/bin/env python3
import json
import sys
import os
import subprocess
import platform
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

def main():
    # Read the Stop event. Claude Code sets stop_hook_active when the model is
    # continuing because a Stop hook already blocked once in this turn. That
    # is the signal that the summary has been spoken, so exit without blocking
    # and the turn ends. This yields exactly one spoken summary per user
    # message, independent of how long speaking takes.
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        event = {}
    if event.get('stop_hook_active'):
        sys.exit(0)
    
    # Read preferences
    preferences = get_preferences()
    
    # Check if audio summary is enabled
    audio_summary = preferences.get('audio_summary', {})
    if not audio_summary.get('enabled', False):
        sys.exit(0)
    
    # Resolve the speech command for this machine
    speech_command = resolve_speech_command()
    if speech_command is None:
        print("No speech command available. Install `say` (macOS) or `espeak-ng`/`espeak` (Linux) to use audio summaries.", file=sys.stderr)
        sys.exit(0)
    
    # Require the spoken summary once for this response
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
            "quotes inside the text. Speak once only. Do not create files or scripts, and do not write anything further after speaking."
        )
    }
    log_decision(output, operation_type="audio_summary_decision")
    print(json.dumps(output))
    sys.exit(2)

if __name__ == "__main__":
    main() 
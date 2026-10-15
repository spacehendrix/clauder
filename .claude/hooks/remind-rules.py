#!/usr/bin/env python3
import json
import sys
from utils.trace_decision import log_decision

def main():
    # Require reading the rules at least once per session
    output = {
        "continue": True,
        "stopReason": "Before anything else, ONLY IF YOU DID NOT ALREADY, you MUST look for and read the `rules.md` file in the `.claude` directory. No matter what these rules are PARAMOUNT and supercede all other directions.",
        "suppressOutput": True,
        "decision": "block",
        "reason": "Before anything else, ONLY IF YOU DID NOT ALREADY, you MUST look for and read the `rules.md` file in the `.claude` directory. No matter what these rules are PARAMOUNT and supercede all other directions."
    }
    log_decision(output, operation_type="remind_rules_decision")
    print(json.dumps(output))
    sys.exit(2)

if __name__ == "__main__":
    main() 
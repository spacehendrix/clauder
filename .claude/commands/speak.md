# Toggle spoken summaries

Turn the spoken summary of each response on or off. The setting is `audio_summary.enabled` in `.claude/preferences.json`. With no argument, toggle it. With `on` or `off`, set it to that state.

## Steps

1. Read `.claude/preferences.json`. Treat a missing `audio_summary` key as disabled.
2. Decide the new state from the argument (`on`, `off`, or none for toggle).
3. Write the new state with this single command, replacing `STATE` with `true` or `false`. Do not use the Edit or Write tools on this file; it is protected by the immutable-patterns hook and this command is the supported way to change it:

```bash
python3 - STATE <<'PY'
import json, sys
path = ".claude/preferences.json"
try:
    data = json.load(open(path))
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
data.setdefault("audio_summary", {})["enabled"] = sys.argv[1] == "true"
json.dump(data, open(path, "w"), indent=2)
open(path, "a").write("\n")
print("audio_summary.enabled =", data["audio_summary"]["enabled"])
PY
```

4. Reply in one line with the new state, for example "Spoken summaries are now on." If turning on, add that `say` on macOS or `espeak-ng`/`espeak` on Linux must be installed, and that the first spoken summary follows this response. Do not speak this confirmation yourself; the Stop hook handles speaking.

Only the `audio_summary` key changes. Leave every other preference as it is.

# Project Guardrails

Review this project and propose permission guardrails: shell commands that should be allowed without prompting because they are routine and safe here, and commands that should be denied because an accidental run would damage this project, its data, or its infrastructure. If a user direction is provided, focus on it.

## Steps

1. Understand the project and its purpose. Read the top-level layout, manifests, build and test configuration, CI files, deployment and infrastructure files, scripts, and `CLAUDE.md` if present. Delegate deeper exploration to the `investigator` agent so your own context stays small. Note the stack, the package manager, the test runner, the linters, the databases, the cloud or hosting providers, and any production-facing tooling.
2. Read the current rules: `permissions.allow` and `permissions.deny` in `.claude/settings.json` and in `.claude/settings.local.json` if it exists. Read `.claude/hooks/prevent-unsafe-commands.py` so you know which commands already require human approval through the hook and do not need a deny rule.
3. Propose **allow** rules for commands this project runs constantly and that only read or build: the test runner, linters, type checkers, formatters in check mode, builds, dependency listing, and read-only invocations of the project's own CLI. Never propose broad patterns such as `Bash(*)`, a whole package manager, or anything that installs, publishes, deploys, or deletes.
4. Propose **deny** rules for commands whose accidental use would be hard to reverse in this project specifically: deploy and release commands, infrastructure apply or destroy, production database CLIs and migration tools, container and cluster deletion, cloud CLIs with write access, publishing to registries, bulk deletion of data or generated directories the project depends on, and anything that rotates or prints credentials. Prefer the narrowest pattern that catches the dangerous form and leaves the safe form usable.
5. Present the proposal as two short tables, one for allow and one for deny. Each row: the exact rule, a one-line description of what it covers, and why it belongs here. Mark rules that duplicate an existing hook or rule as redundant and leave them out. Keep the lists short; a guardrail nobody understands gets removed.
6. Ask the user for approval or feedback on each list. Use `AskUserQuestion` when available, otherwise ask in plain text and wait. Do not change anything before the user answers. Apply their edits and re-present only the rows that changed.
7. Apply the approved rules to `.claude/settings.local.json`, creating the file with `{"permissions": {"allow": [], "deny": []}}` if it is missing and preserving everything else in it. Never remove an existing clauder rule from `.claude/settings.json`, and never add an allow rule for a command that a deny rule or the unsafe-command hook covers.
8. Report what was written, what was declined, and remind the user that a new session is needed for permission changes to take effect.

## Why `settings.local.json`

`.claude/settings.json` is replaced on every clauder activation and auto-update so hooks and baseline permissions stay consistent, and it is protected from edits by the immutable-patterns hook. Project-specific guardrails belong in `.claude/settings.local.json`, which clauder never touches. Claude Code merges the permission lists from both files, and a deny in either file wins.

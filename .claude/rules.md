# RULES

These rules steer the AI in this project. Only the user may edit this file. If a `CLAUDE.md` exists at project root, it is maintained separately and overrides these rules on conflict. If a rule is unclear, or two rules conflict, stop and ask the user.

## 1. Boundaries

1. Never read any file or folder matching an entry in `.claude/.ignore`, and never read secrets (keys, tokens, credentials, `.env` files), even when asked. If you need their contents, say so and ask the user for a redacted copy or a reference to a vault.
2. Never write any file or folder matching an entry in `.claude/.immutable`, even when asked.
3. Never keep secrets in the project. Recommend `~/.env/<project-name>` or a vault, referenced by path or variable name only.
4. Never bypass a blocking hook, a denied permission, or a failed check by trying another method. Report it and wait.
5. Never execute a script or command you do not understand or trust. Read it first.

## 2. Working method

6. Do what was asked. Reasonable abstraction, refactoring, and future-proofing that serve the request are fine. Anything significant, such as re-architecting, introducing new layers or patterns, or changing code well outside the request, is discussed with the user first. If you see a problem outside the request, mention it in one or two sentences and continue.
7. When a request or change reasonably justifies it, interview the user before changing code: ask for missing details, surface the decisions and trade-offs involved, and confirm the context you are relying on. Do this when the request is ambiguous, when several readings would lead to materially different work, when the change touches behaviour users depend on, or when a design decision would be costly to reverse. Do not interview for small or clear changes.
8. Scale your process to the change:
   - Trivial or purely visual: do it, then summarise in one line.
   - Anything else: state goals, the files involved, risks and edge cases, how you will verify it, and backward compatibility, before changing code. Use plan mode when the work spans several files or changes behaviour.
9. Before you change code, check for duplicate, conflicting, or dead code, broken existing behaviour, departures from established patterns, missed edge cases, side effects, and user-facing breakage.
10. Verify before you declare done: run the existing tests, linters, and type checks relevant to the change. Report results truthfully, including failures and anything you skipped.
11. Commit when a task is complete, with a short summary line and a body describing what changed and why. You do not need approval to commit. Never revert, rebase, or force-push without explicit approval and a commit id from the user.

## 3. Risk

12. Before an action that carries risk, highlight the risks and edge cases to the user. If they are significant, pause and make sure the user understands them before proceeding. Risky actions include, at minimum:
    - Irreversible or hard-to-reverse operations (deletions, history rewrites, data migrations).
    - Actions on live systems (databases, servers, repositories, access control, deployments).
    - Anything that may affect a production environment.
    - Unusual, elevated, or destructive shell commands.
    Permissions configured in `.claude/settings.json` or `.claude/settings.local.json` cover routine commands. They do not replace this rule for the items above.

## 4. Sub-agents

13. Delegate to the sub-agent made for the job, instead of doing it yourself in the main context. Give each one a clear scope and all the context it needs. Sub-agents start with no memory of this conversation, so brief them fully: what was requested, what was done, what was rejected, and where to look.
    - `investigator`: explores the codebase to answer a question or build understanding. Use it for any exploration that would otherwise fill your own context. It may run at any time without asking.
    - `code-reviewer`: reviews recent commits for bugs, regressions, and improvements.
    - `test-engineer`: judges whether existing tests are sufficient, then writes and maintains tests. It tests behaviour, inputs, outputs, and outcomes, never implementation details, and focuses on the most important layers and integration surfaces. It writes a short report with high-level metrics to `.test-reports/`, naming the commit it covers.
    - `security-reviewer`: reviews the security of the application and flags or suggests improvements.
    - `documentation-specialist`: documents the codebase and important technical or product decisions, including investigation results when useful. It reads the existing documentation first, keeps it up to date, and matches its style.
14. Every sub-agent other than `investigator` runs only with the user's approval. Ask whether to run them after a significant change, or after a sufficiently long run of minor changes, when it is sensible to pause and check the latest code. Do not ask eagerly or often, and do not get in the way of development. Ask once, naming the agents you propose to run; one approval covers the whole sequence.
15. Run approved sub-agents one at a time, never in parallel, in this order: `code-reviewer`, `security-reviewer`, `test-engineer`, `documentation-specialist`, skipping any the user did not approve. Wait for each to finish, relay its report, address or commit what it left in the working tree with the user, and only then start the next. Each agent therefore sees a clean tree and the previous agents' results.
16. When one of those sub-agents runs, it first reads every commit message and diff since its own last run, recorded in `.claude/.agent-runs.json`, then reviews the code as it now stands before advising or acting. It updates its entry in that file when it finishes. The shared procedure lives in `.claude/skills/agent-run-protocol/SKILL.md`.
17. When asked to create a new sub-agent, in any wording, use the `agent-builder` agent. Afterwards tell the user: "☑️ New specialized agent created in `.claude/agents/`. 🔄 Restart Claude Code to start using it."
18. When another agent gives you feedback or a review, remember it has less context than you. Take important points on board, keep features coherent, and do not let the project outgrow its scope.

## 5. Skills

19. When an operation is intricate, needs precise and stable context, or is done frequently, draft a skill for it in `.claude/skills/` and present the draft to the user for review before relying on it. Keep existing skills accurate when the operations they describe change.

## 6. Conventions

20. CSS: express `px` values in `rem`, except values below 4px and media query breakpoints.

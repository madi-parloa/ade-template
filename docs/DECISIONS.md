# ADE Template — Decision Log

Decisions made during design and implementation, with context for why.

## D-001: No custom CLI

**Decision:** Use copier as the scaffolding tool instead of building a custom `ade` CLI.

**Context:** Multiple iterations designed an `ade new/launch/list/rm` CLI in bash+Python. Each iteration revealed that the core operation (clone repos + run install) was too thin to justify a new tool. Copier covers scaffolding, parameterization, and updates.

**Alternatives considered:**
- Custom bash CLI (~200 lines) — rejected: maintenance burden for marginal UX gain
- degit (no `.git/` in output) — rejected: no parameterization, no update lifecycle
- cookiecutter — rejected: copier has `_tasks` and `copier update`; cookiecutter doesn't

**Trade-off:** Depends on copier's idiosyncrasies (e.g., `--trust` required for `_tasks`, git required for `copier update`). Accepted because the alternative (custom tooling) has worse idiosyncrasies.

## D-002: Workspace-local installation

**Decision:** Install scripts write to `<ade>/.cursor/`, not `~/.cursor/`.

**Context:** The user's requirement was explicit: "whatever we are installing during ADE initialization is being installed to work in the workspace only, not global." GSD supports `--local --cursor` for this.

**Alternatives considered:**
- Shadow HOME (override `$HOME` per Cursor process) — rejected for v1: complex plumbing, not needed because Cursor reads workspace-level `.cursor/` natively
- Fan-out symlinks (per-item symlinks from shadow to real `~/.cursor/`) — designed in detail but rejected as over-engineered for the use case

## D-003: _subdirectory: template

**Decision:** Template content lives under `template/`, copier config at repo root.

**Context:** Without `_subdirectory`, copier.yml and `.jinja` files appear in the output directory. The user pointed out that copier config files should not be mixed with template content.

## D-004: Git init for copier update

**Decision:** `_tasks` includes `git init && git add -A && git commit` guarded by `_copier_operation == 'copy'`.

**Context:** `copier update` hard-requires a git repo at the destination. Verified via hostile subagent research: the source code raises `UserMessageError("Updating is only supported in git-tracked subprojects.")` with no bypass flag.

Copier does NOT auto-init git (confirmed: no `_init_git` setting exists, [Discussion #2167](https://github.com/orgs/copier-org/discussions/2167) requests it).

The git repo is local only — no remote.

**Guard is critical:** Without `when: "{{ _copier_operation == 'copy' }}"`, the git tasks would run in copier's internal temp directories during update, causing `fatal: not a git repository`. Discovered during end-to-end testing.

## D-005: Portfolio as file input

**Decision:** Default portfolio in `ade-repos.txt`, overridable via `--data portfolio_file=<path>`.

**Context:** User asked: "what if we make the list of repos via copier inputs, but I don't have to write a long list — feed a file to it."

**Implementation:** `_tasks` copies the file over `ade-repos.txt` before running install. Absolute paths required because tasks run in the output directory.

## D-006: Pre-seeded codebase intel

**Decision:** Seed `.planning/codebase/*.md` from the existing workspace analysis.

**Context:** GSD planning commands read these files to ground reasoning. Without them, every new ADE requires `/gsd-map-codebase` (minutes of wall time, multiple mapper subagents) before planning can begin.

Seven files: ARCHITECTURE, CONCERNS, CONVENTIONS, INTEGRATIONS, STACK, STRUCTURE, TESTING. All produced by `/gsd-map-codebase` on 2026-04-07.

## D-007: ade-repos.txt and ade-install.sh stay in output

**Decision:** Keep these files in the ADE (not hidden or deleted after use).

**Context:** Early iteration tried render → run → delete. User said: "might as well keep them, just rename to something understandable." The `ade-` prefix was chosen to make clear they belong to the ADE template system, not to any repo in the portfolio.

## D-008: Answers file for copier update

**Decision:** Include `{{_copier_conf.answers_file}}.jinja` in the template.

**Context:** Copier does NOT auto-generate `.copier-answers.yml` unless the template explicitly includes a Jinja file with that name. Discovered when the answers file was missing from scaffolded ADEs. Without it, `copier update` can't determine which template version was used or what answers were given.

## D-009: Tasks guarded by _copier_operation

**Decision:** `ade-install.sh`, `git init`, and Cursor launch only run during `copier copy`, not during `copier update`.

**Context:** `_tasks` run during both copy and update. Without the guard, every `copier update` would re-clone 14 repos, re-install GSD, and re-open Cursor — taking minutes for what should be a fast template-file update.

Discovered during end-to-end testing: unguarded `git add -A` failed in copier's internal temp directory during update with `fatal: not a git repository`.

## D-010: Include ade-template in its own portfolio

**Decision:** `ade-repos.txt` includes `git@github.com:madi-parloa/ade-template.git`.

**Context:** User requested it so the template source is available inside every ADE for reference and potential modification.

## D-011: Version tags for copier

**Decision:** Tag releases with PEP 440-compatible versions (`v0.1.0`, `v0.2.0`, etc.).

**Context:** Copier uses git tags to track template versions. Without tags, copier prints "No git tags found" and can't do proper version comparison for `copier update`.

## D-012: Broken tags are unrecoverable in updates

**Decision:** Never tag a release without first running `bash test.sh` successfully. If a broken tag ships, delete it from the remote immediately.

**Context:** `copier update` computes its diff by re-rendering the template at BOTH the current baseline version (stored in `.copier-answers.yml`) and the target version. If the baseline tag has a jinja error (missing include, bad syntax, etc.), the baseline render crashes and the entire update fails — with no flag to skip baseline regeneration. The only user-side workarounds are:

1. Hand-edit `.copier-answers.yml` to point `_commit` at the last known-good tag (destructive to copier's merge semantics on the affected file).
2. Delete the broken tag upstream so copier falls back to the previous tag.

Neither is acceptable in a shared template. Therefore: pre-tag tests are mandatory, and `v0.6.0` was force-deleted after it shipped a broken `{% include %}` path that only manifested at `copier update` time (the broken-baseline double-render path).

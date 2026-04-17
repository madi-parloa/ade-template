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

## D-007: ade-repos.txt stays in output; ade-install.sh removed in favor of _tasks

**Decision:** Keep `ade-repos.txt` in the ADE (not hidden or deleted after use). The separate `ade-install.sh` script was removed; its clone loop and GSD install now live directly in copier `_tasks`.

**Context:** Early iteration tried render → run → delete. User said: "might as well keep them, just rename to something understandable." The `ade-` prefix was chosen to make clear `ade-repos.txt` belongs to the ADE template system, not to any repo in the portfolio.

Initially `ade-install.sh` shipped alongside as a re-runnable sync tool: users could edit `ade-repos.txt` and re-run the script to clone new repos / pull existing ones without touching copier. That split was later consolidated — the clone loop and `npx get-shit-done-cc` call moved into copier `_tasks` (unguarded by `_copier_operation`), making `uvx copier update --trust` the sole sync entry point. Trade-off: `copier update` redundantly runs the sync in its internal temp render directories, but it removes a file from the output and eliminates the "which of these two commands do I need?" friction. See D-009 for the guard semantics.

## D-008: Answers file for copier update

**Decision:** Include `{{_copier_conf.answers_file}}.jinja` in the template.

**Context:** Copier does NOT auto-generate `.copier-answers.yml` unless the template explicitly includes a Jinja file with that name. Discovered when the answers file was missing from scaffolded ADEs. Without it, `copier update` can't determine which template version was used or what answers were given.

## D-009: Selective _copier_operation guards

**Decision:** `git init` and Cursor launch are guarded by `when: "{{ _copier_operation == 'copy' }}"`. The portfolio sync and GSD install tasks are deliberately unguarded so they run on both `copier copy` and `copier update`.

**Context:** `_tasks` run during both copy and update. Earlier versions guarded every task with `_copier_operation == 'copy'` and shipped a separate `ade-install.sh` for re-sync. That was consolidated (see D-007): sync + GSD now run on update too, making `copier update` a one-command refresh.

Still guarded (must only run on first scaffold):
- `git init && git add -A && git commit` — unguarded, this fails in copier's internal temp directory during update with `fatal: not a git repository` (discovered during end-to-end testing). On copy, it establishes the `.git/` that copier update requires (D-004).
- Cursor launch — unguarded, Cursor would re-open on every template update.

Deliberately unguarded (safe + desired to run on update):
- Portfolio sync (clone/pull loop) — idempotent. Runs redundantly inside copier's internal temp render directories during update; this is wasted work but harmless (clones land in a temp dir that copier discards).
- GSD install (`npx -y get-shit-done-cc@latest --local --cursor`) — idempotent. Same caveat about temp-dir redundancy.

Trade-off: `copier update` does more work than strictly necessary (sync runs in temp renders plus at the real target), but removes the need for a separate re-sync script. Accepted.

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

## D-013: Kitchen installers are not auto-run

**Decision:** The copier `_tasks` sync loop clones `claudes-kitchen/` and `open-kitchen/` but does NOT execute their setup scripts. Users who want kitchen functionality run the installers manually.

**Context:** D-002 mandates workspace-local installation — nothing scaffolded by the ADE should mutate `~/` or system paths. Auditing the kitchen setup scripts showed they violate this contract heavily:

`claudes-kitchen/setup-cooking-environment.sh` writes to:
- `$HOME/CLAUDE.md` (overwritten, prior version moved to `.backup`)
- `$HOME/.claude/settings.json` (merges a company-wide permissions allowlist)
- `$HOME/.claude/.company-permissions.json` (canonical baseline for future merges)
- `$HOME/.cargo/credentials.toml` (JFrog bearer token; prompts interactively)
- `$HOME/.git-templates/hooks/` + `git config --global init.templateDir` (every future `git init` inherits these hooks)
- `$HOME/.gnupg/gpg-agent.conf` (macOS pinentry config)
- `$HOME/.zshrc` / `$HOME/.bashrc` (appends `source claudes-kitchen/.env`)
- `git config --global commit.gpgsign true`
- Installs the Claude Code CLI and adds a plugin marketplace to the user's Claude install

On Linux it additionally runs `sudo apt-get install` for gnupg, jq, 1password-cli, writes APT keyrings under `/usr/share/keyrings/`, `/etc/apt/sources.list.d/`, and `/etc/debsig/policies/`, and drops a gitleaks binary into `/usr/local/bin/`.

`open-kitchen/setup-cargo-jfrog.sh` writes `$HOME/.cargo/credentials.toml`.

None of this is workspace-local. Running these installers as part of `copier copy` would:
1. Silently change the user's global environment every time an ADE is scaffolded.
2. Overwrite `$HOME/CLAUDE.md` on a machine that may host multiple ADEs, defeating per-ADE isolation.
3. Fail in confusing ways when non-interactive (an earlier iteration piped `</dev/null` into the kitchen installers, which caused the JFrog token prompt to be skipped but left the user unsure whether setup succeeded).

**Alternatives considered:**
- Run kitchens as before, document the global side-effects in the README — rejected: scaffolding should be side-effect-free outside the ADE directory.
- Fork the kitchens and strip the global writes — rejected for v1: large maintenance surface; kitchens are an evolving external codebase.
- Remove the kitchen repos from `ade-repos.txt` entirely — rejected: their source is valuable as reference material for composing skills, and cloning a git repo is itself side-effect-free.

**Trade-off:** Users who expected kitchens to be live after scaffolding must now run the installers themselves. The `README.md` and `docs/DESIGN.md` flag this clearly.

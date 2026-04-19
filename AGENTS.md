# ADE Template

This is a Copier template repo, not a runtime project. It scaffolds Agent Dev Environments (ADEs) for Parloa infrastructure work.

## Repo structure

- `copier.yml` — Copier configuration: questions, `_tasks`, `_subdirectory` setting
- `README.md` — GitHub landing page
- `docs/DESIGN.md` — Full design document with motivation and architecture
- `docs/DECISIONS.md` — Decision log (D-001 through D-018) with context for every choice
- `template/` — Everything copier renders into an ADE:
  - `.jinja` files are rendered with variable substitution (suffix stripped in output)
  - Non-`.jinja` files are copied verbatim
  - Portfolio sync and GSD workspace-local install are driven by copier `_tasks` in `copier.yml` (not a separate shell script). Both run on `copier copy` AND `copier update` — sync is clone-if-missing (never pulls existing repos), and GSD install tracks `@latest`. On `copier update` they run **once per invocation** (in the real destination) — each task guards itself with a `$PWD` check that skips copier's internal temp render dirs; see D-015. `git init` and Cursor launch are guarded to first-scaffold-only via `when: "{{ _copier_operation == 'copy' }}"`. An auto-commit task at the end of every update writes a `chore: copier update to <new_commit>` commit so the working tree is always clean after a successful update — see D-018. Kitchen setup scripts (`claudes-kitchen`, `open-kitchen`) are deliberately NOT run — see `docs/DECISIONS.md` D-013. See D-007, D-009, D-015, and D-018 for the full `_tasks` policy and its evolution.
  - `ade-repos.txt` lists the default repo portfolio
  - `.gitignore` uses an allowlist pattern (ignore every top-level dir except `.planning/`) — see D-014
  - `.planning/codebase/*.md` are pre-seeded GSD intel files

## Working on this repo

- Read `docs/DESIGN.md` before making changes — it explains why things are the way they are.
- Read `docs/DECISIONS.md` for specific decision context (e.g., why tasks are guarded by `_copier_operation`).
- **When to tag:** Create a new git tag (e.g., `v0.5.1`) when you change anything inside `template/` or `copier.yml` — these affect what copier scaffolds. Copier resolves the latest tag to determine the template version; without a new tag, `copier update` won't see the change.
- **When NOT to tag:** Changes to `README.md`, `AGENTS.md`, or `docs/` at the repo root do NOT need a tag — they are not part of the copier template output.
- **Before tagging, run `bash test.sh`.** It exercises both `copier copy` and `copier update` against the working tree with stubbed `open` / `npx` (so Cursor doesn't launch and GSD doesn't install). If it fails, do NOT tag — a broken tag makes `copier update` unrecoverable on any ADE that lands on it as a baseline (see `docs/DECISIONS.md` D-012).
- Why this matters: Jinja include paths, `_tasks` semantics, and ordering between render and tasks are all easy to get wrong in ways that pass local mental dry-runs but fail at real `copier copy` / `update` time. The test catches this class of bug.

## Keeping an ADE up to date

`uvx copier update --trust --skip-answered` is the **single entry point** for keeping an ADE current with the template. From v0.8.4 onward it is a true one-command operation:

- Refreshes template-managed files (AGENTS.md, `.planning/codebase/*`, rendered Cursor workspace, etc.) via smart 3-way merge.
- Re-runs portfolio sync + GSD install, **once per invocation** thanks to the pwd gate (D-015). New repos in `ade-repos.txt` are cloned; existing repos are never `git pull`'d (clone-if-missing only — safe even when user has WIP on feature branches, see D-007).
- **Auto-commits its own output** as `chore: copier update to <new_commit>` at the end of every successful update (D-018). This means the working tree is always clean after `copier update`, and the next `copier update` is never blocked by a forgotten manual commit. If the 3-way merge produces unresolved conflict markers, auto-commit is aborted loudly and the tree is left dirty for manual resolution — same failure mode as before, no regression.
- Suppresses re-prompting via `--skip-answered` (D-017). New questions added in future template versions still prompt.

Users who want to re-answer a specific question (e.g., to enable an optional agentic-stack MCP) follow the separate instructions in `agentic-stack.md`, which deliberately uses plain `--trust` without `--skip-answered`.

Users wanting to pull existing clones run the one-liner in the scaffolded `README.md` themselves. Kitchen setup scripts are never run, per D-013.

## Editing template files

- Files under `template/` with `.jinja` suffix are Jinja2 templates. Variables like `{{ ade_name }}` and `{{ description }}` come from `copier.yml` questions. The suffix is stripped in output.
- Files without `.jinja` are copied verbatim.
- `{{_copier_conf.answers_file}}.jinja` is a special copier file that generates `.copier-answers.yml` — do not rename or remove it. See D-008.

## Editing copier.yml

- `_tasks` run in the output directory, not in this repo.
- `_tasks` fire during BOTH `copier copy` AND `copier update`. On update, copier's three-way-merge algorithm invokes `_tasks` **three times** (old-baseline temp render, new-target temp render, real destination). Three orthogonal gating mechanisms are available and compose per task:
  - **`when: "{{ _copier_operation == 'copy' }}"`** restricts a task to first-scaffold only. Used for `git init` (no `.git/` exists in copier's temp dirs — `git add -A` would fail) and Cursor launch (don't re-launch on every update). See D-004, D-009.
  - **`when: "{{ _copier_operation == 'update' }}"`** restricts a task to update only. Used for the auto-commit task (D-018) — during `copier copy`, the dedicated `ADE scaffold` commit already handles committing, so the auto-commit message would be wrong in that context.
  - **`case "$PWD" in */copier._main.*) exit 0 ;; esac`** at the top of the task body skips copier's two temp render dirs and lets the task run only in the real destination. Used for portfolio sync, GSD install, the `cp portfolio_file` task, and the auto-commit task — all of which must run on update (to propagate new repos / refresh GSD / commit the result) but should run **once**, not three times. See D-015. The pwd substring `copier._main.` is the naming convention copier uses for its internal temp render dirs; treat it as a contract that may need revisiting if a future copier release changes it.
- Quote all Jinja variables interpolated into shell commands: `cp "{{ portfolio_file }}"` not `cp {{ portfolio_file }}`.
- `copier update` requires the destination to be a git repo. The template's `_tasks` handle `git init` on first scaffold. See D-004.

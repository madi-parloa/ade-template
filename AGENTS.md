# ADE Template

This is a Copier template repo, not a runtime project. It scaffolds Agent Dev Environments (ADEs) for Parloa infrastructure work.

## Repo structure

- `copier.yml` — Copier configuration: questions, `_tasks`, `_subdirectory` setting
- `README.md` — GitHub landing page
- `docs/DESIGN.md` — Full design document with motivation and architecture
- `docs/DECISIONS.md` — Decision log (D-001 through D-013) with context for every choice
- `template/` — Everything copier renders into an ADE:
  - `.jinja` files are rendered with variable substitution (suffix stripped in output)
  - Non-`.jinja` files are copied verbatim
  - Portfolio clone/pull and GSD workspace-local install are driven by copier `_tasks` in `copier.yml` (not a separate shell script). Kitchen setup scripts (`claudes-kitchen`, `open-kitchen`) are deliberately NOT run — see `docs/DECISIONS.md` D-013.
  - `ade-repos.txt` lists the default repo portfolio
  - `.planning/codebase/*.md` are pre-seeded GSD intel files

## Working on this repo

- Read `docs/DESIGN.md` before making changes — it explains why things are the way they are.
- Read `docs/DECISIONS.md` for specific decision context (e.g., why tasks are guarded by `_copier_operation`).
- **When to tag:** Create a new git tag (e.g., `v0.5.1`) when you change anything inside `template/` or `copier.yml` — these affect what copier scaffolds. Copier resolves the latest tag to determine the template version; without a new tag, `copier update` won't see the change.
- **When NOT to tag:** Changes to `README.md`, `AGENTS.md`, or `docs/` at the repo root do NOT need a tag — they are not part of the copier template output.
- **Before tagging, run `bash test.sh`.** It exercises both `copier copy` and `copier update` against the working tree with stubbed `open` / `npx` (so Cursor doesn't launch and GSD doesn't install). If it fails, do NOT tag — a broken tag makes `copier update` unrecoverable on any ADE that lands on it as a baseline (see `docs/DECISIONS.md` D-012).
- Why this matters: Jinja include paths, `_tasks` semantics, and ordering between render and tasks are all easy to get wrong in ways that pass local mental dry-runs but fail at real `copier copy` / `update` time. The test catches this class of bug.

## Keeping an ADE up to date

One step: `uvx copier update --trust` — pulls latest template changes (new repos in portfolio, updated context files, etc.) via smart 3-way merge AND re-runs the portfolio sync + GSD install `_tasks` (idempotent). Kitchen setup scripts are not run, per D-013.

## Editing template files

- Files under `template/` with `.jinja` suffix are Jinja2 templates. Variables like `{{ ade_name }}` and `{{ description }}` come from `copier.yml` questions. The suffix is stripped in output.
- Files without `.jinja` are copied verbatim.
- `{{_copier_conf.answers_file}}.jinja` is a special copier file that generates `.copier-answers.yml` — do not rename or remove it. See D-008.

## Editing copier.yml

- `_tasks` run in the output directory, not in this repo.
- `_tasks` run during BOTH `copier copy` AND `copier update`. Use `when: "{{ _copier_operation == 'copy' }}"` to restrict tasks to first scaffold only. See D-009.
- During `copier update`, copier also runs tasks in internal temp directories for diff computation. Tasks that assume a git repo (like `git add`) must be guarded.
- Quote all Jinja variables interpolated into shell commands: `cp "{{ portfolio_file }}"` not `cp {{ portfolio_file }}`.
- `copier update` requires the destination to be a git repo. The template's `_tasks` handle `git init` on first scaffold. See D-004.

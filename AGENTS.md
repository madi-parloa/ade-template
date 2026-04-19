# ADE Template

This is a Copier template repo, not a runtime project. It scaffolds Agent Dev Environments (ADEs) for Parloa infrastructure work.

## Repo structure

- `copier.yml` — Copier configuration: questions, `_tasks`, `_subdirectory`, `_skip_if_exists`, `_exclude`
- `_portfolio.jinja` — Jinja macros (`platform_repos`, `group_repos`, `resolve_url`, `repo_dir`) that turn copier answers into the final repo set. Lives at the template root so Jinja imports can find it; excluded from rendering by `_exclude: ["_*.jinja"]`. See D-022 and D-023.
- `README.md` — GitHub landing page
- `docs/DESIGN.md` — Full design document with motivation and architecture
- `docs/DECISIONS.md` — Decision log with context for every non-obvious choice
- `template/` — Everything copier renders into an ADE:
  - `.jinja` files are rendered with variable substitution (suffix stripped in output)
  - Non-`.jinja` files are copied verbatim
  - `ade-repos.txt.jinja` and `{{ ade_name }}.code-workspace.jinja` are generated from the macros in `_portfolio.jinja` — they are not user-editable artifacts. See D-023.
  - `.gitignore.jinja` renders a conditional gitignore: when `include_gsd_docs` is true, ignores the `.planning` symlink; when false, allowlists `.planning/` as a real directory — see D-014 and D-021
  - `.planning/codebase/*.md` are pre-seeded GSD intel files (migrated into gsd-docs on scaffold when enabled)

## Update model

The prescribed update command is:

```bash
uvx copier recopy --trust --skip-answered --overwrite
```

`copier recopy` re-applies the current template fresh (no 3-way merge), so whatever is in the latest template is what lands on disk. Combined with a near-empty `_skip_if_exists`, every template-owned file is overwritten on every recopy — no drift. See D-022. The single exception is `.planning/PROJECT.md` when `include_gsd_docs=true`: ownership transfers to gsd-docs after the initial scaffold, see D-026.

`copier update` (3-way merge) is not the prescribed path. It works if invoked, but recopy is what the scaffolded README and docs point users at, because the portfolio (ade-repos.txt, code-workspace) is fully derived from answers — there's nothing to merge.

## `_tasks` semantics

`_tasks` fire during BOTH `copier copy` and `copier recopy` (copier sets `_copier_operation` to `'copy'` for both — `recopy` is implemented as `run_copy` under the hood; see D-022). Three orthogonal gating mechanisms compose per task:

- **On-disk state detection** (`.git/` presence check) distinguishes "first scaffold" from "re-apply". The consolidated finalize task uses this: no `.git/` → `git init` + `ADE scaffold` commit + open Cursor; `.git/` exists → conflict-marker check, then auto-commit as `chore: copier recopy to <hash>`. See D-022.
- **`case "$PWD" in */copier._main.*) exit 0 ;; esac`** at the top of every task body skips copier's internal temp render dirs (`copier._main.*`) and lets the task run only in the real destination. Every `_task` is pwd-gated.
- **`when: "{{ include_gsd_docs }}"`** and similar Jinja conditions gate tasks on copier answers (e.g. the gsd-docs onboard task only fires when the user opted in).

## Portfolio model

`ade-repos.txt` and `<ade>.code-workspace` are **generated** from copier answers:

- `include_gsd_docs`, `include_agent_guardrails`, `include_cursor_self_hosted_agent` (booleans) gate platform-level repos.
- `portfolio_groups` (multiselect) pulls in fixed sets: `core-infra`, `stamps`, `catalog`, `kitchens`, `template-source`.
- `extra_repos` (multiline free-text) adds user-specified repos.
- `default_org` (hidden, default `parloa`) lets bare `some-repo` names resolve to `parloa/some-repo` automatically. Override with `--data default_org=other-org` for non-Parloa scaffolds.

Short-name DSL (D-024): `some-repo` → `git@github.com:parloa/some-repo.git`; `org/some-repo` → `git@github.com:org/some-repo.git`; full URLs pass through.

Changing the portfolio post-scaffold: `uvx copier recopy --trust --overwrite` (without `--skip-answered`) re-prompts for `portfolio_groups` and `extra_repos`, using current answers as defaults.

## gsd-docs sentinel region

When `include_gsd_docs=true`, `template/CLAUDE.md.jinja` and `template/AGENTS.md.jinja` render a `<!-- GSD-DOCS:multi-repo-paths:BEGIN -->` … `<!-- GSD-DOCS:multi-repo-paths:END -->` block at the end of each file, with `{{ gsd_docs_handle }}` substituted into the ownership contract lines. This region is **template-owned**: `gsd-docs/bin/onboard.sh`'s `inject_sentinel` still runs as task 3, but since the block already matches what it would render, the rewrite is byte-identical and produces no diff. No more `conflict / overwrite` noise for these files on recopy. See D-025. The `gsd_docs_handle` answer must match the handle `onboard.sh` detects (via `gh api user` or `gsd-docs/.gsd-docs-user`); a mismatch makes the next recopy show one real conflict until the answer is corrected via `copier recopy` without `--skip-answered`.

## Working on this repo

- Read `docs/DESIGN.md` before making changes — it explains why things are the way they are.
- Read `docs/DECISIONS.md` for specific decision context.
- **When to tag:** Create a new git tag (e.g., `v0.9.1`) when you change anything inside `template/`, `_portfolio.jinja`, or `copier.yml` — these affect what copier scaffolds. Copier resolves the latest tag to determine the template version; without a new tag, `copier recopy` won't see the change.
- **When NOT to tag:** Changes to `README.md`, `AGENTS.md`, `CLAUDE.md`, or `docs/` at the repo root do NOT need a tag — they are not part of the copier template output.
- **Before tagging, run `bash test.sh`.** It exercises `copier copy` and `copier recopy` scenarios (initial scaffold, recopy picks up new repo, no-op recopy, template-wins, partial selection, short-name DSL) against the working tree with stubbed `open` / `npx` / `git clone` (network URLs only — local paths pass through so copier can clone the local template source). If it fails, do NOT tag — a broken tag makes `copier recopy` unrecoverable on any ADE that lands on it as a baseline (see D-012).

## Editing template files

- Files under `template/` with `.jinja` suffix are Jinja2 templates. Variables like `{{ ade_name }}` and `{{ description }}` come from `copier.yml` questions. The suffix is stripped in output.
- Files without `.jinja` are copied verbatim.
- `{{_copier_conf.answers_file}}.jinja` is a special copier file that generates `.copier-answers.yml` — do not rename or remove it. See D-008.
- To import `_portfolio.jinja` macros from a template file, use `{% from '_portfolio.jinja' import ... with context %}` — the `with context` is required for the macros to see top-level answers like `default_org`.

## Editing copier.yml

- `_tasks` run in the output directory, not in this repo.
- Every `_task` body must start with the `*/copier._main.*) exit 0` pwd gate — without it, the task runs in copier's temp render dirs as well.
- Quote all Jinja variables interpolated into shell commands.
- `_skip_if_exists` is near-empty by design — it's the mechanism that enforces "template wins" on recopy. The one Jinja-gated entry for `.planning/PROJECT.md` (when `include_gsd_docs=true`) is a deliberate ownership boundary, not a leak; see D-026 before adding more.
- `_exclude` keeps `_*.jinja` files (including `_portfolio.jinja`) from being rendered into the output; they're for internal Jinja imports only.

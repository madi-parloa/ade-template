# ADE Template — Claude Instructions

Read `AGENTS.md` for repo structure and conventions. Read `docs/DESIGN.md` for the full design context.

## This is a Copier template, not a runtime project

Do not treat this repo as an application or service. It has no source code, no tests, no CI. It is a set of template files that Copier renders into ADE directories.

## When editing template files

- Files under `template/` with `.jinja` suffix are Jinja2 templates. Variables like `{{ ade_name }}` and `{{ description }}` come from `copier.yml` questions.
- Files without `.jinja` are copied verbatim (e.g., `ade-repos.txt`, `ade-install.sh`, `.planning/codebase/*.md`).
- `{{_copier_conf.answers_file}}.jinja` is a special copier file — do not rename or remove it.

## When editing copier.yml

- `_tasks` run in the output directory, not in this repo.
- `_tasks` run during BOTH `copier copy` AND `copier update`. Use `when: "{{ _copier_operation == 'copy' }}"` to restrict tasks to first scaffold only.
- During `copier update`, copier also runs tasks in internal temp directories for diff computation. Tasks that assume a git repo (like `git add`) must be guarded.
- Quote all Jinja variables interpolated into shell commands: `cp "{{ portfolio_file }}"` not `cp {{ portfolio_file }}`.

## When editing docs/

- `docs/DESIGN.md` and `docs/DECISIONS.md` are repo-level documentation, not part of the template output.
- Update `DECISIONS.md` when making a design choice that future contributors should understand.
- No tag needed for doc-only changes.

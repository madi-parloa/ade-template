# ADE Template — Design Document

## What this is

A [Copier](https://copier.readthedocs.io/) template that scaffolds an **ADE (Agent Dev Environment)** — a Cursor workspace containing a portfolio of cloned repos, workspace-local GSD, and pre-seeded codebase intelligence.

One command creates a fully functional agentic workspace:

```bash
uvx copier copy --trust git+https://github.com/madi-parloa/ade-template.git ~/path/to/my-ade
```

## Motivation

The ADE template exists to solve **agent maximalism** — the problem of accumulating too many skills, rules, hooks, and plugins in a single Cursor workspace until neither the agent nor the human can reason about them.

The original workspace (`~/Documents/cursor-self-hosted-agent/`) grew to 151 SKILL.md files, 68 GSD commands, 15 rule files, 5 MCP servers, and 4 hook events with dual judge/policy systems. Agent skill-selection became unreliable, the policy-gate MCP had conflicts, and the user felt overwhelmed.

Rather than trying to fix the one overloaded setup, the ADE approach makes experiments cheap: spin up multiple isolated workspaces with different agentic configurations and compare them side-by-side.

## Key design decisions

### 1. Off-the-shelf tooling, not a custom CLI

Early iterations designed a custom `ade` CLI with `ade new`, `ade launch`, `ade list`, `ade rm`, etc. This was scrapped because:

- The v1 scope (clone repos + run install script) is too thin to justify a new binary.
- Copier already handles template scaffolding, parameterization, and lifecycle updates.
- `uvx copier` runs without installation (`uv` was already present on the host).
- Template updates propagate via `copier update`, which copier handles natively.

### 2. Workspace-local installation, not user-level

Install scripts must write to `<ade>/.cursor/`, not `~/.cursor/`. This gives per-ADE isolation using Cursor's native workspace-level config layer — different ADEs present different skill/rule/hook/MCP sets without needing shadow-HOME machinery.

GSD supports this via `npx -y get-shit-done-cc@latest --local --cursor`.

Kitchen setup scripts (`claudes-kitchen/setup-cooking-environment.sh`, `open-kitchen/setup-cargo-jfrog.sh`) do NOT respect the working directory — they write to `$HOME/.cargo`, `$HOME/.claude`, `$HOME/CLAUDE.md`, `$HOME/.git-templates`, global git config, and (on Linux) apt-installed system packages. Running them during ADE scaffolding would violate workspace-local isolation. The kitchen repos are therefore cloned for reference but their installers are not auto-run (see D-013).

Earlier iterations explored:
- **Shadow HOME per ADE** (overriding `$HOME` for each Cursor process). Rejected for v1 as overkill — workspace-level `.cursor/` gives isolation for free.
- **Symlink-based profiles** (swapping `~/.cursor/` components via symlinks). Rejected because parallel Cursor windows sharing `~/.cursor/` means they can't have different configs.
- **Devcontainers** for full OS-level isolation. Deferred to future work.

### 3. Copier _subdirectory separates config from template

The repo root holds `copier.yml` and `README.md` (copier config + landing page). All template content lives under `template/`. This prevents copier machinery (`.yml`, `.jinja` suffixes) from cluttering the template output.

### 4. Git init in _tasks for copier update support

`copier update` requires the destination to be a git repo (hard requirement — the source code raises `UserMessageError("Updating is only supported in git-tracked subprojects.")`). This is a local `.git/` only — no remote, no push.

`_tasks` split into two groups:

**Run on both copy and update** (idempotent, form the sync pipeline):
- Portfolio clone/pull loop — reads `ade-repos.txt`, clones missing, `git pull --ff-only` existing. Kitchen installers (`claudes-kitchen`, `open-kitchen`) are deliberately skipped; see D-013.
- GSD workspace-local install — `npx -y get-shit-done-cc@latest --local --cursor`.

**Guarded by `when: "{{ _copier_operation == 'copy' }}"`** (first scaffold only):
- `git init && git add -A && git commit` — creates the local git repo.
- Cursor launch — opens the ADE.

This means `copier update` is the single entry point for both "pull latest template changes" and "re-sync portfolio / GSD" — no separate re-sync script.

### 5. Portfolio as a copier input with file override

The default repo list lives in `template/ade-repos.txt`. Users can override it via:

```bash
uvx copier copy --trust --data portfolio_file=/path/to/my-repos.txt ...
```

The `_tasks` copies the user's file over `ade-repos.txt` before running install. Absolute paths are required (tasks run in the output directory, not the user's CWD).

### 6. Pre-seeded .planning/codebase/ intel

The seven GSD codebase intel files (`ARCHITECTURE.md`, `STACK.md`, `STRUCTURE.md`, `CONVENTIONS.md`, `CONCERNS.md`, `TESTING.md`, `INTEGRATIONS.md`) are seeded from the existing workspace analysis. This means:

- GSD planning commands are Parloa-aware from the first invocation.
- No need to run `/gsd-map-codebase` (which takes minutes and spawns multiple subagents) before starting work.
- Static copies — regenerate with `/gsd-map-codebase` if the portfolio changes.

### 7. ade-repos.txt stays in the output

Early iterations tried to hide this file (render → run → delete). Kept because:
- Users edit `ade-repos.txt` to add/remove repos and then re-run `copier update --trust` to sync.
- The `ade-` prefix makes its purpose clear in the directory listing.
- Copier manages it across template updates.

An earlier design kept a companion `ade-install.sh` script for the same reason (manual re-sync), but the clone loop and GSD install were later inlined into copier `_tasks` so `copier update` is the sole sync entry point. See D-007 for the full history.

## Architecture

```
madi-parloa/ade-template (GitHub repo)
├── copier.yml                          # questions + _tasks
├── README.md                           # repo landing page
└── template/                           # _subdirectory: template
    ├── {{_copier_conf.answers_file}}.jinja  # enables copier update
    ├── AGENTS.md.jinja                 # workspace context (rendered with variables)
    ├── CLAUDE.md.jinja                 # Claude-specific guidance
    ├── README.md.jinja                 # human README
    ├── ade-repos.txt                   # default portfolio (13 Parloa repos + template itself)
    ├── .gitignore                      # excludes .cursor/, cloned repos, volatile .planning/
    └── .planning/
        ├── PROJECT.md.jinja            # GSD project seed
        └── codebase/                   # 7 pre-seeded intel files
            ├── ARCHITECTURE.md
            ├── CONCERNS.md
            ├── CONVENTIONS.md
            ├── INTEGRATIONS.md
            ├── STACK.md
            ├── STRUCTURE.md
            └── TESTING.md
```

## copier.yml explained

```yaml
_min_copier_version: "9.0.0"
_subdirectory: template           # template content lives under template/

_tasks:
  # 1. Override ade-repos.txt if user provided a custom file (runs on copy AND update)
  - >-
    {% if portfolio_file %}cp "{{ portfolio_file }}" ade-repos.txt{% endif %}
  # 2. Portfolio sync: clone missing, pull existing (runs on copy AND update; kitchen installers skipped)
  - command:
      - bash
      - -c
      - |
        # ...clone/pull loop reading ade-repos.txt...
  # 3. GSD workspace-local install (runs on copy AND update; idempotent)
  - command:
      - bash
      - -c
      - |
        npx -y get-shit-done-cc@latest --local --cursor
  # 4. Init git for copier update support (first scaffold only)
  - command: "git init && git add -A && git commit --no-gpg-sign -m 'ADE scaffold'"
    when: "{{ _copier_operation == 'copy' }}"
  # 5. Open Cursor (first scaffold only)
  - command: "open -a Cursor '{{ ade_name }}.code-workspace'"
    when: "{{ _copier_operation == 'copy' }}"
```

The `when: "{{ _copier_operation == 'copy' }}"` guard on `git init` and the Cursor launch is critical — without it, `git add -A` would fail inside copier's internal temp directories during update (no `.git/` there), and Cursor would re-open on every template update. The sync + GSD tasks deliberately run on both operations so `copier update` is the single re-sync entry point; per D-009, this trades a small amount of redundant work in update's internal temp renders for removing the need for a separate install script.

## Known limitations (v1)

- **Kitchens are cloned but not installed.** By design (see D-013). Users who want global kitchen installation must run `bash claudes-kitchen/setup-cooking-environment.sh` and `bash open-kitchen/setup-cargo-jfrog.sh` manually.
- **macOS only.** Cursor path hardcoded to `/Applications/Cursor.app/Contents/MacOS/Cursor`.
- **No per-ADE guardrail state.** Policy-gate and judge still use global `/tmp` paths. Two parallel ADEs with guardrails share state.
- **copier update overwrites template-managed files.** If you edit `AGENTS.md` or `README.md` locally, `copier update` will merge changes (via git 3-way diff) but may produce conflicts.

## Future work

- **Shadow HOME isolation** for fully parallel experimentation.
- **Per-ADE guardrail state** (`ADE_STATE_DIR` env var).
- **Devcontainer variant** for OS-level isolation.
- **Multiple templates** (`ade-template-infra`, `ade-template-frontend`).
- **Template questions for flavor selection** (copier conditional rendering).

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
- Template updates propagate via `copier recopy`, which copier handles natively.

### 2. Workspace-local installation, not user-level

Install scripts must write to `<ade>/.cursor/`, not `~/.cursor/`. This gives per-ADE isolation using Cursor's native workspace-level config layer — different ADEs present different skill/rule/hook/MCP sets without needing shadow-HOME machinery.

The scaffolded ADE's `.gitignore` allowlists `.planning/` and ignores every other top-level directory (`/*/`), so workspace-local tooling dirs like `.cursor/` never get accidentally committed to the ADE's own git history. Portfolio repos are also caught by the same pattern, which prevents them from being tracked as gitlinks (a failure mode that bit earlier versions — see D-014).

GSD supports this via `npx -y get-shit-done-cc@latest --local --cursor`.

Kitchen setup scripts (`claudes-kitchen/setup-cooking-environment.sh`, `open-kitchen/setup-cargo-jfrog.sh`) do NOT respect the working directory — they write to `$HOME/.cargo`, `$HOME/.claude`, `$HOME/CLAUDE.md`, `$HOME/.git-templates`, global git config, and (on Linux) apt-installed system packages. Running them during ADE scaffolding would violate workspace-local isolation. The kitchen repos are therefore cloned for reference but their installers are not auto-run (see D-013).

Earlier iterations explored:
- **Shadow HOME per ADE** (overriding `$HOME` for each Cursor process). Rejected for v1 as overkill — workspace-level `.cursor/` gives isolation for free.
- **Symlink-based profiles** (swapping `~/.cursor/` components via symlinks). Rejected because parallel Cursor windows sharing `~/.cursor/` means they can't have different configs.
- **Devcontainers** for full OS-level isolation. Deferred to future work.

### 3. Copier _subdirectory separates config from template

The repo root holds `copier.yml` and `README.md` (copier config + landing page). All template content lives under `template/`. This prevents copier machinery (`.yml`, `.jinja` suffixes) from cluttering the template output.

### 4. The update command is `copier recopy`, not `copier update`

The prescribed update flow for any ADE is:

```bash
uvx copier recopy --trust --skip-answered --overwrite
```

`recopy` re-renders every template-owned file from the current template and writes the result to the destination. It does not perform copier's structural 3-way merge (`copier update` does). Combined with `_skip_if_exists: []` in `copier.yml`, every template-owned file is overwritten on every recopy. The contract is: **whatever the latest template version renders is what's on disk after the command returns.**

This is the right model because every template-owned file in the ADE is a derived artifact (AGENTS.md, CLAUDE.md, `.planning/codebase/*.md`, `.gitignore`, the workspace file, `ade-repos.txt`). There is no legitimate "user diverged from template" state for these files — if a user wants a different portfolio, they change the answer and recopy. Three-way merge on derived artifacts only hides template evolution.

See D-022 for the full rationale, flag anatomy, and the finalize task that handles git init on first scaffold + auto-commit on recopy.

### 5. `_tasks` run on both copy and recopy, pwd-gated to fire exactly once

Every `_task` in `copier.yml` begins with:

```bash
case "$PWD" in
  */copier._main.*) exit 0 ;;
esac
```

Copier's render algorithm may create internal temp directories (`copier._main.old_copy.*`, `copier._main.new_copy.*`) during update or recopy, and `_tasks` fire in every render. The pwd gate ensures tasks execute **only in the real destination** — exactly once per invocation.

Current task list (order matches `copier.yml`):

| Task | Gate | Runs on |
|---|---|---|
| Portfolio sync (clone-if-missing loop over `ade-repos.txt`) | pwd | copy + recopy |
| GSD install (`npx -y get-shit-done-cc@latest --local --cursor`) | pwd | copy + recopy |
| gsd-docs onboard (`gsd-docs/bin/onboard.sh`) | pwd + `when: include_gsd_docs` | copy + recopy (when enabled) |
| Finalize: `.git/` check → scaffold path (git init + ADE scaffold commit + open Cursor) OR recopy path (conflict-marker check + auto-commit) | pwd + on-disk state | copy + recopy |

The sync loop never `git pull`s existing repos. A recopy that brings in a new entry results in one `git clone`; already-cloned repos are left alone so that user WIP branches are never stomped. Users who want to refresh everything run the explicit pull one-liner documented in the scaffolded `README.md`.

Kitchen installers (`claudes-kitchen/setup-cooking-environment.sh`, `open-kitchen/setup-cargo-jfrog.sh`) are deliberately skipped; see D-013.

### 6. Portfolio is answer-derived, not file-edited

`ade-repos.txt` and `<ade>.code-workspace` are generated from copier answers — they are not user-editable source files. The answers that drive them:

- `include_gsd_docs`, `include_agent_guardrails`, `include_cursor_self_hosted_agent` (booleans) — platform-layer toggles.
- `portfolio_groups` (multiselect) — `core-infra`, `stamps`, `catalog`, `kitchens`, `template-source`.
- `extra_repos` (multiline) — freeform list using the short-name DSL (D-024).
- `default_org` (hidden, defaults to `parloa`) — org used when expanding bare repo names.

All rendering is driven by macros in `_portfolio.jinja` at the template root: `platform_repos()`, `group_repos(group)`, `resolve_url(name)`, `repo_dir(name)`. Both `ade-repos.txt.jinja` and `{{ ade_name }}.code-workspace.jinja` import those macros `with context`, so the two files can never disagree about what URL or folder a short name refers to.

Adding a new repo to a group: edit `_portfolio.jinja`, tag a new template version, recopy — every ADE picks it up on the next recopy.

Adding a one-off repo to a single ADE: `uvx copier recopy --trust --overwrite` (without `--skip-answered`) re-prompts for `portfolio_groups` and `extra_repos` with the current answers as defaults. Or pass `--data extra_repos="$(cat my-repos.txt)"` to seed the answer directly.

See D-023 for the full decision and D-024 for the short-name DSL.

### 6. Pre-seeded .planning/codebase/ intel

The seven GSD codebase intel files (`ARCHITECTURE.md`, `STACK.md`, `STRUCTURE.md`, `CONVENTIONS.md`, `CONCERNS.md`, `TESTING.md`, `INTEGRATIONS.md`) are seeded from the existing workspace analysis. This means:

- GSD planning commands are Parloa-aware from the first invocation.
- No need to run `/gsd-map-codebase` (which takes minutes and spawns multiple subagents) before starting work.
- Static copies — regenerate with `/gsd-map-codebase` if the portfolio changes.

### 7. ade-repos.txt stays visible in the output

Although `ade-repos.txt` is generated, it's kept as a visible file in the ADE root rather than hidden. Reasons:

- Users benefit from seeing the resolved portfolio at a glance. Each recopy regenerates it, so it always matches the answers.
- The `ade-` prefix makes its purpose obvious in a directory listing.
- The file header says clearly that edits are reverted on the next recopy and that portfolio changes are made by re-answering, not by editing.

## Architecture

```
madi-parloa/ade-template (GitHub repo)
├── copier.yml                          # questions + _tasks
├── _portfolio.jinja                    # portfolio macros (imported by template files)
├── README.md                           # repo landing page
├── AGENTS.md                           # repo-level agent context
├── docs/
│   ├── DESIGN.md
│   └── DECISIONS.md
├── test.sh                             # end-to-end copier copy + recopy scenarios
└── template/                           # _subdirectory: rendered into the ADE
    ├── {{_copier_conf.answers_file}}.jinja  # generates .copier-answers.yml
    ├── AGENTS.md.jinja
    ├── CLAUDE.md.jinja
    ├── README.md.jinja
    ├── agentic-stack.md.jinja
    ├── ade-repos.txt.jinja             # generated from _portfolio.jinja macros
    ├── {{ ade_name }}.code-workspace.jinja  # generated from same macros
    ├── .gitignore.jinja                # conditional on include_gsd_docs (D-014 / D-021)
    └── .planning/
        ├── PROJECT.md.jinja            # GSD project seed
        └── codebase/                   # 7 pre-seeded intel files (D-006)
            ├── ARCHITECTURE.md
            ├── CONCERNS.md
            ├── CONVENTIONS.md
            ├── INTEGRATIONS.md
            ├── STACK.md
            ├── STRUCTURE.md
            └── TESTING.md
```

## copier.yml shape

See `copier.yml` for the authoritative current state. Summary:

- `_subdirectory: template` — only files under `template/` are rendered into the output.
- `_exclude: ["_*.jinja", ...]` — keeps the `_portfolio.jinja` macro file (which lives at the template root) out of the render.
- `_skip_if_exists: []` — nothing is protected on recopy; template always wins.
- Questions: `ade_name`, `description`, `include_gsd_docs`, `include_agent_guardrails`, `include_cursor_self_hosted_agent`, `portfolio_groups`, `extra_repos`, the four `include_*_mcp` / `include_eval_pipeline` agentic-stack toggles, `default_org` (hidden), `portfolio_file` (hidden, inert — see D-005).
- `_tasks`: portfolio sync → GSD install → gsd-docs onboard (conditional) → finalize (git init + ADE scaffold on first copy; auto-commit on recopy).

## Known limitations (v1)

- **Kitchens are cloned but not installed.** By design (see D-013). Users who want global kitchen installation must run `bash claudes-kitchen/setup-cooking-environment.sh` and `bash open-kitchen/setup-cargo-jfrog.sh` manually.
- **Portfolio sync does not auto-pull existing repos.** Recopy clones any repos newly listed in the rendered `ade-repos.txt`, but never `git pull`s already-cloned repos (doing so on top of a user's WIP would be unsafe). Users who want to refresh everything run the one-liner documented in the scaffolded `README.md`. See D-007.
- **macOS only.** Cursor path hardcoded to `/Applications/Cursor.app/Contents/MacOS/Cursor`.
- **No per-ADE guardrail state.** Policy-gate and judge still use global `/tmp` paths. Two parallel ADEs with guardrails share state.

## Future work

- **Shadow HOME isolation** for fully parallel experimentation.
- **Per-ADE guardrail state** (`ADE_STATE_DIR` env var).
- **Devcontainer variant** for OS-level isolation.
- **Multiple templates** (`ade-template-infra`, `ade-template-frontend`).
- **Template questions for flavor selection** (copier conditional rendering).

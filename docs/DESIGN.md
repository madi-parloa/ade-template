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

The scaffolded ADE's `.gitignore` allowlists `.planning/` and ignores every other top-level directory (`/*/`), so workspace-local tooling dirs like `.cursor/` never get accidentally committed to the ADE's own git history. Portfolio repos are also caught by the same pattern, which prevents them from being tracked as gitlinks (a failure mode that bit earlier versions — see D-014).

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

Guard rule for `_tasks`: guard destructive or one-shot tasks; leave idempotent tasks unguarded so template evolution propagates on `copier update`:

| Task | Guarded to `copy` only? | Runs on `copier update`? |
|---|---|---|
| Copy `portfolio_file` → `ade-repos.txt` (if provided) | no | yes (trivial, no-op when unset) |
| Portfolio sync — **clone-if-missing** loop | no | yes (new repos land; existing repos untouched) |
| GSD install — `npx -y get-shit-done-cc@latest --local --cursor` | no | yes (tracks `@latest`) |
| `git init && git add -A && git commit` | **yes** | no (no `.git/` in copier's temp dirs) |
| Cursor launch | **yes** | no (otherwise Cursor relaunches on every update) |

The sync loop never `git pull`s existing repos. `copier update` bringing in a new `ade-repos.txt` entry results in one `git clone`; already-cloned repos are left alone so that user WIP branches are never stomped. Users who want to pull everything run the one-liner documented in the scaffolded `README.md`.

Kitchen installers (`claudes-kitchen`, `open-kitchen`) are deliberately skipped; see D-013.

The three versions of this policy (v0.7.0 unguarded-with-pull, v0.7.1 guarded-to-copy-only, v0.7.2 unguarded-clone-if-missing) and the copier double-render behavior that constrains them are documented in D-007 and D-009.

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
- Users edit `ade-repos.txt` to tweak the portfolio (and re-running `copier update --trust` re-renders the Cursor workspace file and triggers `clone-if-missing` for any new entries).
- The `ade-` prefix makes its purpose clear in the directory listing.
- Copier manages it across template updates.

The install flow that reads this file has gone through four iterations: a re-runnable companion `ade-install.sh` (v0.1.x–v0.6.x), inlined unguarded `_tasks` with clone-or-pull making `copier update` the sync entry point (v0.7.0), inlined `_tasks` guarded to copy-only (v0.7.1), and finally unguarded inlined `_tasks` with a clone-if-missing sync loop (v0.7.2+). See D-007 for the full rationale and D-009 for the copier double-render behavior that shapes the guard decisions.

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
    ├── .gitignore                      # allowlist: ignore /*/ except .planning/; see D-014
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
  # 1. Override ade-repos.txt if user provided a custom file (no-op when unset)
  - >-
    {% if portfolio_file %}cp "{{ portfolio_file }}" ade-repos.txt{% endif %}
  # 2. Portfolio sync: clone missing repos; existing repos are never touched.
  #    Unguarded so new entries in ade-repos.txt propagate on copier update.
  #    Kitchen installers are deliberately skipped; see D-013.
  - command:
      - bash
      - -c
      - |
        # ...clone-if-missing loop reading ade-repos.txt...
  # 3. GSD workspace-local install; unguarded so @latest tracks template evolution.
  - command:
      - bash
      - -c
      - |
        npx -y get-shit-done-cc@latest --local --cursor
  # 4. Init git for copier update support (first scaffold only; no .git/ in copier temp dirs)
  - command: "git init && git add -A && git commit -m 'ADE scaffold'"
    when: "{{ _copier_operation == 'copy' }}"
  # 5. Open Cursor (first scaffold only; otherwise Cursor relaunches on every update)
  - command: "open -a Cursor '{{ ade_name }}.code-workspace'"
    when: "{{ _copier_operation == 'copy' }}"
```

Copier's update algorithm re-executes `_tasks` three times per update (old-baseline temp render, new-target temp render, and real project — the double-render path; see D-009). This is the central constraint. The sync loop is written as **clone-if-missing** so 3× execution is idempotent — one clone on the first iteration, two `[ -d "$dir" ]` skips on the other two. GSD install runs 3× and accepts the cost (3× npm registry check) as the price of tracking `@latest`. `git init` and Cursor launch are guarded to copy-only because running them on update would fail (no `.git/` in copier temp dirs) or be user-hostile (re-launching Cursor on every template bump).

## Known limitations (v1)

- **Kitchens are cloned but not installed.** By design (see D-013). Users who want global kitchen installation must run `bash claudes-kitchen/setup-cooking-environment.sh` and `bash open-kitchen/setup-cargo-jfrog.sh` manually.
- **Portfolio sync does not auto-pull existing repos.** `copier update` clones any repos newly added to `ade-repos.txt`, but never `git pull`s already-cloned repos (doing so on top of a user's WIP would be unsafe). Users who want to refresh everything run the one-liner documented in the scaffolded `README.md`. See D-007.
- **ADEs scaffolded before v0.7.2 have stale gitlinks.** Prior `.gitignore` versions didn't catch nested portfolio repos, so `git add -A` on first scaffold tracked them as `160000`-mode gitlinks. After `copier update` to v0.7.2+ brings in the new `.gitignore`, run `git rm --cached -r <repo-name>` for each affected repo to drop the stale pointer. See D-014.
- **macOS only.** Cursor path hardcoded to `/Applications/Cursor.app/Contents/MacOS/Cursor`.
- **No per-ADE guardrail state.** Policy-gate and judge still use global `/tmp` paths. Two parallel ADEs with guardrails share state.
- **copier update overwrites template-managed files.** If you edit `AGENTS.md` or `README.md` locally, `copier update` will merge changes (via git 3-way diff) but may produce conflicts.

## Future work

- **Shadow HOME isolation** for fully parallel experimentation.
- **Per-ADE guardrail state** (`ADE_STATE_DIR` env var).
- **Devcontainer variant** for OS-level isolation.
- **Multiple templates** (`ade-template-infra`, `ade-template-frontend`).
- **Template questions for flavor selection** (copier conditional rendering).

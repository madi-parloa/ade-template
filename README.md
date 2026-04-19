# ADE Template

A [Copier](https://copier.readthedocs.io/) template that scaffolds an **ADE (Agent Dev Environment)** — a Cursor workspace with a portfolio of Parloa infrastructure repos, workspace-local GSD, and pre-seeded codebase intelligence.

## Scaffolding a new ADE

```bash
uvx copier copy --trust git+https://github.com/madi-parloa/ade-template.git ~/path/to/my-ade
```

Copier prompts for the ADE name, which repo groups to include, which optional integrations to declare, etc. The template then clones every repo in the answer-derived portfolio, installs GSD workspace-locally, commits, and opens Cursor.

### Portfolio questions

| Answer | Type | Default | What it controls |
|--------|------|---------|------------------|
| `include_gsd_docs` | bool | `true` | Clone `parloa/gsd-docs` and wire `.planning/` to the shared workspace |
| `include_agent_guardrails` | bool | `true` | Clone `madi-parloa/agent-guardrails` (clone-only; activate manually) |
| `include_cursor_self_hosted_agent` | bool | `true` | Clone `madi-parloa/cursor-self-hosted-agent` |
| `gsd_docs_handle` | str (gated on `include_gsd_docs`) | empty | Your GitHub handle for `gsd-docs` — substituted into the template-owned gsd-docs sentinel region in `CLAUDE.md` / `AGENTS.md`. Must match what `gsd-docs/bin/onboard.sh` detects (D-025) |
| `portfolio_groups` | multiselect | all 5 groups | Include `core-infra` / `stamps` / `catalog` / `kitchens` / `template-source` (see D-023 for group contents) |
| `extra_repos` | multiline | empty | Extra repos to clone, one per line. Short-name DSL (see below) |
| `default_org` | str, hidden | `parloa` | Default GitHub org for bare repo names; override with `--data default_org=other-org` |

Plus four optional agentic-stack questions (`include_code_graph_mcp`, `include_code_mode_mcp`, `include_letta_memory_mcp`, `include_eval_pipeline`) — docs-only; nothing is auto-installed.

### Short-name DSL

Every repo reference — platform toggles, group contents, `extra_repos` — is a **short name**, resolved to a full git URL at render time:

| Input | Resolved URL | On-disk folder |
|-------|--------------|----------------|
| `some-repo` | `git@github.com:parloa/some-repo.git` | `some-repo` |
| `parloa/some-repo` | `git@github.com:parloa/some-repo.git` | `some-repo` |
| `madi-parloa/some-repo` | `git@github.com:madi-parloa/some-repo.git` | `some-repo` |
| `git@...` / `https://...` / `*.git` | pass-through | basename (stripping `.git`) |

Lines starting with `#` or whitespace-only are ignored. See `docs/DECISIONS.md` D-024.

## What you get

| File | Purpose |
|------|---------|
| `AGENTS.md` | Agent-level workspace context (includes an "Agentic stack" summary rendered from your Copier answers) |
| `README.md` | Human orientation |
| `agentic-stack.md` | Declared defaults + opt-in MCP integrations, with the exact `agent-guardrails/install.sh --with=...` activation command |
| `ade-repos.txt` | Git URLs of repos to clone. **Generated from copier answers** — do not edit; re-run recopy without `--skip-answered` to change the portfolio |
| `<ade_name>.code-workspace` | Multi-root Cursor workspace. Root first, portfolio repos alphabetical (D-016). Generated from the same portfolio macros as `ade-repos.txt` |
| `.planning/PROJECT.md` | GSD project definition. When `include_gsd_docs=true` (default) the template does not render this file at all — `gsd-docs/bin/new-project.sh` authors it in shared storage on initial scaffold and `recopy` never touches it again. When `include_gsd_docs=false` the template owns it (rendered from `ade_name`/`description` each recopy). See D-026 |
| `.planning/codebase/*.md` | Pre-seeded codebase intelligence (7 files) |
| `.cursor/` | Workspace-local Cursor config (populated by install) |

## Keeping an ADE up to date

```bash
cd ~/path/to/my-ade
uvx copier recopy --trust --skip-answered --overwrite
```

That's the single entry point. `recopy` re-renders every template-owned file from the current template, so the latest template is what lands on disk. Details:

- **`--trust`** — required because the template uses `_tasks` (clone loop, GSD install, auto-commit).
- **`--overwrite`** — required on `recopy`; suppresses the per-file "overwrite?" prompt (recopy is, by definition, "template wins").
- **`--skip-answered`** — reuses answers from `.copier-answers.yml` for existing questions, but still prompts if a newer template version introduces a new question. Template evolution cannot be silently defaulted away.

After recopy returns, `ade-repos.txt` and `<ade_name>.code-workspace` match the latest template, missing repos have been cloned, GSD has been refreshed, and the output is auto-committed as `chore: copier recopy to <hash>` (where `<hash>` is the template commit SHA) so the working tree is clean. If a pre-existing local edit produced a conflict marker (unlikely under `--overwrite`), auto-commit is skipped and the tree is left dirty for manual resolution.

### Changing the portfolio

To add/remove a repo group or freeform extras:

```bash
uvx copier recopy --trust --overwrite
```

Omit `--skip-answered` and re-answer `portfolio_groups` / `extra_repos`. Copier presents your stored answers as the prompt defaults, so you only need to edit the ones you want to change.

One-off seeded input (e.g. a large list piped from another tool):

```bash
uvx copier recopy --trust --overwrite --data extra_repos="$(cat my-repos.txt)"
```

### Pulling existing clones

`recopy` never `git pull`s existing clones — doing so over WIP is unsafe. To refresh everything:

```bash
for d in */; do [ -d "$d/.git" ] && git -C "$d" pull --ff-only; done
```

## Post-install notes

- **GSD** is installed workspace-locally into `.cursor/` (not `~/.cursor/`). Each ADE has its own independent GSD install.
- **Kitchens** (`claudes-kitchen/`, `open-kitchen/`) are cloned for reference but their setup scripts are **not** auto-run. They mutate user/system-level state (`$HOME/.cargo`, `$HOME/.claude`, `$HOME/CLAUDE.md`, `$HOME/.git-templates`, global git config, apt/brew packages) which conflicts with the workspace-local isolation goal (see `docs/DECISIONS.md` D-002, D-013). Run them manually if you want global installation:
  ```bash
  bash claudes-kitchen/setup-cooking-environment.sh
  bash open-kitchen/setup-cargo-jfrog.sh  # requires `jf login` first
  ```
- **agent-guardrails** is cloned when `include_agent_guardrails=true` but `install.sh` is **not** auto-run (same kitchen policy). Activate manually:
  ```bash
  ./agent-guardrails/install.sh --with=<csv from agentic-stack.md>
  ```

## Forking

```bash
gh repo fork madi-parloa/ade-template --remote
uvx copier copy --trust git+https://github.com/<you>/ade-template.git ~/path/to/my-ade
```

See `docs/DECISIONS.md` for the design rationale behind every non-obvious choice.

# ADE Template

A [Copier](https://copier.readthedocs.io/) template that scaffolds an **ADE (Agent Dev Environment)** — a Cursor workspace with a portfolio of Parloa infrastructure repos, workspace-local GSD, and pre-seeded codebase intelligence.

## Usage

```bash
# Default Parloa portfolio:
uvx copier copy --trust git+https://github.com/madi-parloa/ade-template.git ~/path/to/my-ade

# Custom repo list:
uvx copier copy --trust --data portfolio_file=/path/to/my-repos.txt git+https://github.com/madi-parloa/ade-template.git ~/path/to/my-ade
```

Copier prompts for a name and description, renders the template, clones all repos, installs GSD workspace-locally, and opens Cursor.

## What you get

| File | Purpose |
|------|---------|
| `AGENTS.md` | Agent-level workspace context (includes an "Agentic stack" summary rendered from your Copier answers) |
| `README.md` | Human orientation |
| `agentic-stack.md` | Declared defaults + opt-in MCP integrations for this ADE, with the exact `agent-guardrails/install.sh --with=...` command to activate them |
| `ade-repos.txt` | Git URLs of repos to clone |
| `<ade_name>.code-workspace` | Multi-root Cursor workspace listing every portfolio repo, with the ADE root at the top and portfolio repos sorted alphabetically (see D-016). Rendered by Copier from `ade-repos.txt` on `copier copy` / `copier update`; opened automatically on first scaffold only. Re-render after editing `ade-repos.txt` with `uvx copier update --trust --skip-answered` |
| `.planning/PROJECT.md` | GSD project definition |
| `.planning/codebase/*.md` | Pre-seeded codebase intelligence (7 files) |
| `.cursor/` | Workspace-local Cursor config (populated by install) |

## Keeping an ADE up to date

```bash
cd ~/path/to/my-ade
uvx copier update --trust --skip-answered
```

`copier update` is the single entry point. It:

1. Merges template/docs changes (AGENTS.md, `.planning/codebase/*`, rendered Cursor workspace, and `ade-repos.txt` itself — via 3-way diff, so any repos newly added to the template's default list land automatically while your local edits are preserved; see D-019).
2. Clones any repos newly added to `ade-repos.txt` (from the merge above, or from your own edits). Already-cloned repos are **not** `git pull`'d — safe even if you have WIP on feature branches.
3. Refreshes GSD (`npx -y get-shit-done-cc@latest --local --cursor`).
4. Auto-commits its own output as `chore: copier update to <new_commit>` so the working tree is clean when the command returns (see D-018, D-020).

**One-command-forever promise (v0.8.4+):** `uvx copier update --trust --skip-answered` requires no pre-work and no post-work. It won't prompt, it won't leave the tree dirty, and the next update is never blocked by a forgotten commit from this one. If copier's 3-way merge produces unresolved conflict markers in any file, the auto-commit is aborted with a loud message and the tree is left dirty for you to resolve — same as pre-v0.8.4 behavior, no regression in the conflict case.

`--skip-answered` suppresses re-prompting for answers already stored in `.copier-answers.yml` (see D-017). Drop it if you want to re-answer questions — typically only needed when adding an optional agentic-stack integration (`include_code_graph_mcp`, etc.), for which `agentic-stack.md` has its own documented command.

**`portfolio_file` is a scaffold-only input.** If you passed `--data portfolio_file=...` on `copier copy`, that was a one-time seed of `ade-repos.txt`. After scaffold, `ade-repos.txt` belongs to your ADE's git repo — edit it directly, commit, and the next `copier update` will clone new entries. Re-passing `portfolio_file` on update is a no-op (and before v0.8.5 it would silently break updates when the source file moved). See D-019.

As of **v0.8.3**, portfolio sync and GSD install run **once per update** in the real destination (prior versions re-ran them three times — see D-015). As of **v0.8.4**, the update auto-commits when done; as of **v0.8.5**, the auto-commit runs as an `_migrations` step *after* copier's final merge, so consecutive `copier update` invocations are never blocked by a dirty tree (see D-020).

**Pulling existing clones** — if you want to update all already-cloned repos (not just add new ones), run this one-liner yourself. It's deliberately not automatic because `git pull` over a user's WIP is unsafe:

```bash
for d in */; do [ -d "$d/.git" ] && git -C "$d" pull --ff-only; done
```

## Customizing

1. **Different repos** — at scaffold time, pass `--data portfolio_file=/path/to/my-repos.txt` to seed `ade-repos.txt` from your own file. After scaffold, `ade-repos.txt` is owned by your ADE — edit it directly and run `uvx copier update --trust --skip-answered` to clone any newly listed repos. The template's own additions to the default list land on the same update via copier's 3-way merge. See D-019.
2. **Optional agentic integrations** — Copier asks four questions that declare which `agent-guardrails` MCP extensions should be considered active for this ADE:

   | Question | Values | Default | Effect |
   |----------|--------|---------|--------|
   | `include_code_graph_mcp` | `none` / `cody` / `augment` | `none` | Cross-repo code-graph retrieval via Sourcegraph Cody (OSS) or Augment (commercial). Highest-ROI optional integration. |
   | `include_code_mode_mcp` | `true` / `false` | `false` | Python-as-tool-calls (`mcp-code-executor`). Low ROI for Terraform/YAML. |
   | `include_letta_memory_mcp` | `true` / `false` | `false` | Letta/MemGPT self-editing memory. Requires a running Letta instance. |
   | `include_eval_pipeline` | `none` / `latitude` / `braintrust` | `none` | Documents a production→eval platform. Docs-only; nothing is installed. |

   Your answers render into `agentic-stack.md` along with the exact `./agent-guardrails/install.sh --with=<csv>` activation command. Nothing is installed automatically — this matches the existing kitchen policy (user/system-level installs are never auto-run). See `docs/DECISIONS.md`.
3. **Fork this template** — `gh repo fork madi-parloa/ade-template` and scaffold from your fork.

## Post-install notes

- **GSD** is installed workspace-locally into `.cursor/` (not `~/.cursor/`). Each ADE has its own independent GSD install.
- **Kitchens** (`claudes-kitchen/`, `open-kitchen/`) are cloned for reference but their setup scripts are **not** auto-run. They mutate user/system-level state (`$HOME/.cargo`, `$HOME/.claude`, `$HOME/CLAUDE.md`, `$HOME/.git-templates`, global git config, apt/brew packages) which conflicts with the workspace-local isolation goal (see `docs/DECISIONS.md` D-002, D-013). Run them manually if you want global installation:
  ```bash
  bash claudes-kitchen/setup-cooking-environment.sh
  bash open-kitchen/setup-cargo-jfrog.sh  # requires `jf login` first
  ```

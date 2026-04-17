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
| `AGENTS.md` | Agent-level workspace context |
| `README.md` | Human orientation |
| `ade-repos.txt` | Git URLs of repos to clone |
| `<ade_name>.code-workspace` | Multi-root Cursor workspace listing every portfolio repo. Rendered by Copier from `ade-repos.txt` on `copier copy` / `copier update`; opened automatically on first scaffold only. Re-render after editing `ade-repos.txt` with `uvx copier update --trust --force` |
| `.planning/PROJECT.md` | GSD project definition |
| `.planning/codebase/*.md` | Pre-seeded codebase intelligence (7 files) |
| `.cursor/` | Workspace-local Cursor config (populated by install) |

## Keeping an ADE up to date

**Template/docs refresh** — to pull new AGENTS.md guidance, updated `.planning/codebase/*` intel, or changes to the rendered Cursor workspace file:

```bash
cd ~/path/to/my-ade
uvx copier update --trust
```

`copier update` is a pure template/docs refresh. It does NOT re-sync the portfolio or reinstall GSD (those `_tasks` are guarded to first-scaffold only — see `docs/DECISIONS.md` D-009 for why).

**Portfolio changes** — if you edited `ade-repos.txt` (or the template added new repos via a `copier update`), clone/remove the corresponding directories manually:

```bash
# Example: pick up newly added repos from ade-repos.txt
while read -r url; do
  dir="$(basename "$url" .git)"
  [ -d "$dir" ] || git clone "$url" "$dir"
done < <(grep -Ev '^\s*(#|$)' ade-repos.txt)

# Update existing clones
for d in */; do [ -d "$d/.git" ] && git -C "$d" pull --ff-only; done
```

**GSD refresh** — to update GSD itself:

```bash
npx -y get-shit-done-cc@latest --local --cursor
```

## Customizing

1. **Different repos** — re-run copier with `--data portfolio_file=/path/to/my-repos.txt`, or edit `ade-repos.txt` (see the manual sync snippet above).
2. **Fork this template** — `gh repo fork madi-parloa/ade-template` and scaffold from your fork.

## Post-install notes

- **GSD** is installed workspace-locally into `.cursor/` (not `~/.cursor/`). Each ADE has its own independent GSD install.
- **Kitchens** (`claudes-kitchen/`, `open-kitchen/`) are cloned for reference but their setup scripts are **not** auto-run. They mutate user/system-level state (`$HOME/.cargo`, `$HOME/.claude`, `$HOME/CLAUDE.md`, `$HOME/.git-templates`, global git config, apt/brew packages) which conflicts with the workspace-local isolation goal (see `docs/DECISIONS.md` D-002, D-013). Run them manually if you want global installation:
  ```bash
  bash claudes-kitchen/setup-cooking-environment.sh
  bash open-kitchen/setup-cargo-jfrog.sh  # requires `jf login` first
  ```

# ADE Template

A [Copier](https://copier.readthedocs.io/) template that scaffolds an **ADE (Agent Dev Environment)** — a Cursor workspace with a portfolio of Parloa infrastructure repos, workspace-local GSD, kitchen skills, and pre-seeded codebase intelligence.

## Usage

```bash
# Default Parloa portfolio:
uvx copier copy --trust git+https://github.com/madi-parloa/ade-template.git ~/path/to/my-ade

# Custom repo list:
uvx copier copy --trust --data portfolio_file=/path/to/my-repos.txt git+https://github.com/madi-parloa/ade-template.git ~/path/to/my-ade
```

Copier prompts for a name and description, renders the template, clones all repos, installs GSD workspace-locally, runs kitchen setup scripts, and opens Cursor.

## What you get

| File | Purpose |
|------|---------|
| `AGENTS.md` | Agent-level workspace context |
| `README.md` | Human orientation |
| `ade-repos.txt` | Git URLs of repos to clone |
| `ade-install.sh` | Clones/pulls repos, installs GSD + kitchens |
| `.planning/PROJECT.md` | GSD project definition |
| `.planning/codebase/*.md` | Pre-seeded codebase intelligence (7 files) |
| `.cursor/` | Workspace-local Cursor config (populated by install) |

## Keeping an ADE up to date

Two steps:

**1. Pull latest template changes** (new repos in portfolio, updated AGENTS.md, etc.):

```bash
cd ~/path/to/my-ade
uvx copier update --trust
```

This merges template changes into your ADE while preserving your local edits.

**2. Sync all repos** (clone any new repos, pull latest on existing ones):

```bash
bash ade-install.sh
```

This also re-installs GSD and re-runs kitchen setups (idempotent).

## Customizing

1. **Different repos** — re-run copier with `--data portfolio_file=/path/to/my-repos.txt`, or edit `ade-repos.txt` and run `bash ade-install.sh`.
2. **Fork this template** — `gh repo fork madi-parloa/ade-template` and scaffold from your fork.

## Post-install notes

- **claudes-kitchen** setup prompts for a JFrog token interactively. If it was skipped during scaffolding, run `bash claudes-kitchen/setup-cooking-environment.sh` manually.
- **GSD** is installed workspace-locally into `.cursor/` (not `~/.cursor/`). Each ADE has its own independent GSD install.

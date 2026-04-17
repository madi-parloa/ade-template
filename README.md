# ADE Template

A [Copier](https://copier.readthedocs.io/) template that scaffolds an **ADE (Agent Dev Environment)** — a Cursor workspace with a portfolio of Parloa infrastructure repos, workspace-local GSD, kitchen skills, and pre-seeded codebase intelligence.

## Usage

```bash
uvx copier copy --trust git+https://github.com/madi-parloa/ade-template.git ~/path/to/my-ade
```

Copier prompts for a name and description, renders the template, clones all portfolio repos, installs GSD workspace-locally, and runs kitchen setup scripts. Then:

```bash
cursor ~/path/to/my-ade
```

## What you get

| File | Purpose |
|------|---------|
| `AGENTS.md` | Agent-level workspace context |
| `CLAUDE.md` | Claude-specific instructions |
| `README.md` | Human orientation |
| `portfolio.txt` | Git URLs of repos to clone |
| `install.sh` | Clones repos, installs GSD + kitchens |
| `.planning/PROJECT.md` | GSD project definition |
| `.planning/codebase/*.md` | Pre-seeded codebase intelligence (7 files) |
| `.cursor/` | Workspace-local Cursor config (populated by install) |

## Updating an existing ADE

```bash
cd ~/path/to/my-ade
uvx copier update --trust
```

Re-renders template files (preserving your answers) and re-runs `install.sh`.

## Customizing

1. **Edit in place** — change `portfolio.txt` and `install.sh` in your ADE, then re-run `./install.sh`.
2. **Fork this template** — `gh repo fork madi-parloa/ade-template` and scaffold from your fork.

## Post-install notes

- **claudes-kitchen** setup prompts for a JFrog token interactively. If you ran the template non-interactively, run `bash claudes-kitchen/setup-cooking-environment.sh` manually afterwards.
- **GSD** is installed workspace-locally into `.cursor/` (not `~/.cursor/`). Each ADE has its own independent GSD install.

# ADE Template — Decision Log

Decisions made during design and implementation, with context for why.

## D-001: No custom CLI

**Decision:** Use copier as the scaffolding tool instead of building a custom `ade` CLI.

**Context:** Multiple iterations designed an `ade new/launch/list/rm` CLI in bash+Python. Each iteration revealed that the core operation (clone repos + run install) was too thin to justify a new tool. Copier covers scaffolding, parameterization, and updates.

**Alternatives considered:**
- Custom bash CLI (~200 lines) — rejected: maintenance burden for marginal UX gain
- degit (no `.git/` in output) — rejected: no parameterization, no update lifecycle
- cookiecutter — rejected: copier has `_tasks` and a native update/recopy lifecycle; cookiecutter doesn't

**Trade-off:** Depends on copier's idiosyncrasies (e.g., `--trust` required for `_tasks`, git required at the destination for `copier recopy`). Accepted because the alternative (custom tooling) has worse idiosyncrasies.

## D-002: Workspace-local installation

**Decision:** Install scripts write to `<ade>/.cursor/`, not `~/.cursor/`.

**Context:** The user's requirement was explicit: "whatever we are installing during ADE initialization is being installed to work in the workspace only, not global." GSD supports `--local --cursor` for this.

**Alternatives considered:**
- Shadow HOME (override `$HOME` per Cursor process) — rejected for v1: complex plumbing, not needed because Cursor reads workspace-level `.cursor/` natively
- Fan-out symlinks (per-item symlinks from shadow to real `~/.cursor/`) — designed in detail but rejected as over-engineered for the use case

## D-003: _subdirectory: template

**Decision:** Template content lives under `template/`, copier config at repo root.

**Context:** Without `_subdirectory`, copier.yml and `.jinja` files appear in the output directory. The user pointed out that copier config files should not be mixed with template content.

## D-004: Git init on first scaffold

**Decision:** The consolidated finalize `_task` (see D-022) runs `git init && git add -A && git commit` whenever the destination has no `.git/` directory, creating the initial `ADE scaffold` commit.

**Context:** `copier recopy` (and `copier update`, which we don't prescribe) hard-requires a git repo at the destination. The source code raises `UserMessageError("Updating is only supported in git-tracked subprojects.")` with no bypass flag. Copier does NOT auto-init git (no `_init_git` setting exists; [Discussion #2167](https://github.com/orgs/copier-org/discussions/2167) requests it). Without the finalize task, every ADE user would have to run `git init` by hand before the first recopy, which defeats the "one command" contract.

The git repo is local only — no remote.

**Why an on-disk state check, not `_copier_operation`:** `_copier_operation` is `'copy'` for both `copier copy` and `copier recopy` (see D-022), so it cannot distinguish "first scaffold" from "user is re-applying the template on an existing repo." The presence of `.git/` is the authoritative signal.

## D-005: `portfolio_file` is an inert backward-compatibility answer

**Decision:** The `portfolio_file` question is still declared in `copier.yml` with `when: false` and an empty default. It is not prompted and does not drive any task. The portfolio comes from `portfolio_groups` + `extra_repos` (D-023) instead.

**Why keep it declared at all:** Older `.copier-answers.yml` files may contain a `portfolio_file: <path>` entry. Removing the question from `copier.yml` would cause copier to emit an "unknown answer" warning on every `recopy`. Keeping the question as `when: false` lets the stored answer be ingested silently and ignored.

## D-006: Pre-seeded codebase intel

**Decision:** Seed `.planning/codebase/*.md` from the existing workspace analysis.

**Context:** GSD planning commands read these files to ground reasoning. Without them, every new ADE requires `/gsd-map-codebase` (minutes of wall time, multiple mapper subagents) before planning can begin.

Seven files: ARCHITECTURE, CONCERNS, CONVENTIONS, INTEGRATIONS, STACK, STRUCTURE, TESTING. All produced by `/gsd-map-codebase` on 2026-04-07.

## D-007: Portfolio sync is an inlined `_task`, not a separate shell script

**Decision:** The clone-if-missing loop and the GSD install live directly in copier `_tasks` in `copier.yml`. There is no companion `ade-install.sh` script in the template. Both tasks run on `copier copy` and `copier recopy`, pwd-gated so they fire exactly once per invocation (in the real destination, not in copier's internal temp renders — see D-015).

**Why inlined:** A separate script would need its own versioning story (does the ADE's local copy of `ade-install.sh` win, or does the template's?), its own invocation docs ("after copier, run bash ade-install.sh"), and would drift from the copier `_tasks` over time. Keeping the logic inline makes the template the single source of truth.

**Why clone-if-missing, never `git pull`:** Silently `git pull`-ing over a user's WIP branch is a class of side-effect a scaffolder should never produce. The clone loop only acts on missing repos; already-cloned repos are left alone regardless of branch state. Users who want to refresh all clones run `for d in */; do [ -d "$d/.git" ] && git -C "$d" pull --ff-only; done` — documented in the scaffolded README.

**Why `ade-repos.txt` stays visible in the output:** It's a generated artifact (D-023) but users benefit from seeing the resolved portfolio at a glance. The `ade-` prefix makes it clear the file belongs to the ADE template system, not to any repo in the portfolio. Edits to it are reverted on the next recopy; the file header says so explicitly.

## D-008: Ship the answers file via Jinja

**Decision:** Include `{{_copier_conf.answers_file}}.jinja` in the template so every scaffold writes `.copier-answers.yml` to the destination.

**Context:** Copier does NOT auto-generate `.copier-answers.yml` unless the template explicitly includes a Jinja file with that name. Without it, `copier recopy` cannot determine which template version was used or read back stored answers — every recopy becomes a fresh `copier copy` with no `--skip-answered` behavior, and the finalize task loses access to `vcs_ref_hash` for its commit message trailer.

## D-009: How `_tasks` are gated

**Decision:** Every task in `copier.yml` is pwd-gated at the top of its body:

```bash
case "$PWD" in
  */copier._main.*) exit 0 ;;
esac
```

Scaffold-vs-recopy behavior is handled inside tasks by state checks (e.g. `.git/` presence for the finalize task), not by a `when: "{{ _copier_operation == 'copy' }}"` clause. Content-sensitive gating (e.g. "only onboard gsd-docs if `include_gsd_docs`") uses Jinja `when:` clauses evaluated against copier answers.

**Why pwd-gate everything:** copier's update flow re-renders the template multiple times into internal temp directories. Without the pwd gate, unguarded tasks run in every temp render as well as the real destination. The pwd substring `copier._main.` is copier's standard naming convention for these dirs (`copier._main.old_copy.*`, `copier._main.new_copy.*`, etc.) — matching it is the reliable way to distinguish "real destination" from "copier's scratch space." See D-015 for the full lifecycle rationale.

**Why not key gating off `_copier_operation`:** `_copier_operation` equals `'copy'` for both `copier copy` and `copier recopy` (see D-022), so it cannot distinguish "first scaffold" from "user is re-applying the template." For tasks that need that distinction (the finalize task in D-022, which must `git init` on first scaffold but auto-commit on recopy), the on-disk `.git/` state is the correct signal. Using `_copier_operation` was an attractive API but it doesn't carry the information we need.

**Why `npx get-shit-done-cc@latest` re-runs every time:** `@latest` tracking is the point — template bumps should land GSD refreshes on existing ADEs. The install is idempotent; re-running it re-applies skills/rules/hooks from the current published version. No additional gate needed.

## D-010: Include ade-template in its own portfolio

**Decision:** `ade-repos.txt` includes `git@github.com:madi-parloa/ade-template.git`.

**Context:** User requested it so the template source is available inside every ADE for reference and potential modification.

## D-011: Version tags for copier

**Decision:** Tag releases with PEP 440-compatible versions (`v0.1.0`, `v0.2.0`, etc.).

**Context:** Copier uses git tags to select "latest version" when no explicit `--vcs-ref` is passed to `recopy` or `update`. Without tags, copier prints "No git tags found" and falls back to `HEAD`. Tagging also lets the auto-commit message (`chore: copier recopy to <hash>`, D-022) be cross-referenced to a human-readable release.

## D-012: Pre-tag tests are mandatory; broken tags must be force-deleted

**Decision:** Never tag a release without first running `bash test.sh` successfully. If a broken tag ships, delete it from the remote immediately.

**Context:** `test.sh` exercises `copier copy` + `copier recopy --trust --skip-answered --overwrite` end-to-end against the local template checkout and verifies the finalize task's scaffold and recopy paths. Shipping a tag that fails this test means every user who runs recopy against it hits the same failure.

If a bad tag slips through, `git push --delete origin <tag>` on the remote is the right fix — copier will fall back to the previous tag. Hand-editing `.copier-answers.yml` to pin `_commit` at an older SHA is strictly worse; it hides the breakage from the user and the template author.

## D-013: Kitchen installers are not auto-run

**Decision:** The copier `_tasks` sync loop clones `claudes-kitchen/` and `open-kitchen/` but does NOT execute their setup scripts. Users who want kitchen functionality run the installers manually.

**Context:** D-002 mandates workspace-local installation — nothing scaffolded by the ADE should mutate `~/` or system paths. Auditing the kitchen setup scripts showed they violate this contract heavily:

`claudes-kitchen/setup-cooking-environment.sh` writes to:
- `$HOME/CLAUDE.md` (overwritten, prior version moved to `.backup`)
- `$HOME/.claude/settings.json` (merges a company-wide permissions allowlist)
- `$HOME/.claude/.company-permissions.json` (canonical baseline for future merges)
- `$HOME/.cargo/credentials.toml` (JFrog bearer token; prompts interactively)
- `$HOME/.git-templates/hooks/` + `git config --global init.templateDir` (every future `git init` inherits these hooks)
- `$HOME/.gnupg/gpg-agent.conf` (macOS pinentry config)
- `$HOME/.zshrc` / `$HOME/.bashrc` (appends `source claudes-kitchen/.env`)
- `git config --global commit.gpgsign true`
- Installs the Claude Code CLI and adds a plugin marketplace to the user's Claude install

On Linux it additionally runs `sudo apt-get install` for gnupg, jq, 1password-cli, writes APT keyrings under `/usr/share/keyrings/`, `/etc/apt/sources.list.d/`, and `/etc/debsig/policies/`, and drops a gitleaks binary into `/usr/local/bin/`.

`open-kitchen/setup-cargo-jfrog.sh` writes `$HOME/.cargo/credentials.toml`.

None of this is workspace-local. Running these installers as part of `copier copy` would:
1. Silently change the user's global environment every time an ADE is scaffolded.
2. Overwrite `$HOME/CLAUDE.md` on a machine that may host multiple ADEs, defeating per-ADE isolation.
3. Fail in confusing ways when non-interactive (an earlier iteration piped `</dev/null` into the kitchen installers, which caused the JFrog token prompt to be skipped but left the user unsure whether setup succeeded).

**Alternatives considered:**
- Run kitchens as before, document the global side-effects in the README — rejected: scaffolding should be side-effect-free outside the ADE directory.
- Fork the kitchens and strip the global writes — rejected for v1: large maintenance surface; kitchens are an evolving external codebase.
- Remove the kitchen repos from `ade-repos.txt` entirely — rejected: their source is valuable as reference material for composing skills, and cloning a git repo is itself side-effect-free.

**Trade-off:** Users who expected kitchens to be live after scaffolding must now run the installers themselves. The `README.md` and `docs/DESIGN.md` flag this clearly.

## D-014: `.gitignore` allowlists `.planning/`, ignores every other top-level directory

**Decision:** `template/.gitignore` ignores every top-level directory by default via `/*/`, then allowlists `.planning/` with `!/.planning/` (and allowlists a few files like `ROADMAP.md` inside `.planning/`). Individual portfolio repo names are not enumerated.

**Why an allowlist, not an enumeration:** Enumerating every cloned repo has two failure modes:

1. **Missed entries cause gitlink pollution.** If a repo is missing from the list, `git add -A` on first scaffold tracks the freshly cloned repo as a **gitlink** (`160000` mode) — git's way of recording a nested repo's HEAD pointer. On subsequent recopy, as that repo's HEAD advances, the working tree reports it as modified, which trips copier's "Destination repository is dirty; cannot continue" check.
2. **Maintenance burden.** Adding a new repo to the template would require remembering to add it to `.gitignore` as well. Silent coupling; easy to forget.

The allowlist inverts the default: ignore every top-level directory unconditionally (`/*/`), then surface only the template-managed ones. Every current and future portfolio repo is ignored with no `.gitignore` edit. Template-managed **files** at root (`AGENTS.md`, `README.md`, `.copier-answers.yml`, `<ade>.code-workspace`, `ade-repos.txt`, etc.) are unaffected — `/*/` matches only directories.

**Trade-off:** If someone genuinely wanted to track a cloned repo's working copy (e.g., ship it as part of the scaffolded project), they'd need to add an explicit `!/name/` allowlist. No current use case needs this, and doing so would be conceptually wrong — portfolio repos are external dependencies, not scaffolded content.

## D-015: Skip `_tasks` in copier's temp render dirs

**Decision:** Every `_task` in `copier.yml` starts with a pwd gate:

```bash
case "$PWD" in
  */copier._main.*) exit 0 ;;
esac
```

On `copier recopy`, this causes tasks to **no-op** in copier's internal render temp directories (`/private/var/folders/.../copier._main.old_copy.*` and `.../copier._main.new_copy.*`) and run **only once**, in the real destination.

**Why this is needed:** Copier's recopy flow re-renders the template into temp directories as part of its diff computation, and `_tasks` fire in every render. Without a gate, tasks that clone repos or run `npx` would execute 3× per invocation — wasteful enough to matter for the GSD install (which refetches the npm manifest and rewrites `.cursor/`) and confusing in the log (three back-to-back banners).

**Why a pwd check, not some other gate:**

- **`_copier_operation`** — copier sets this identically in all three renders, so it cannot distinguish "temp render" from "real destination."
- **`.git/` presence** — on the real destination during a fresh `copier copy`, `.git/` doesn't exist yet (it's created by the finalize task, D-022). A `.git/`-based gate would false-skip on first scaffold. (The finalize task does use `.git/` state, but only to decide between scaffold and auto-commit paths — not to gate execution against temp renders.)
- **Sentinel file / lockfile** — works, but requires a cleanup step and opens "what if cleanup is missed" failure modes. More moving parts than the pwd match.

**Why the pwd substring is safe:** Copier names its temp dirs with `copier._main.<phase>_copy.<random>` where `<phase>` is `old` or `new`. That substring doesn't occur in natural destination paths. If copier renames its temp dirs in a future version, tasks silently regress to multi-execution — correct but wasteful. `test.sh` exercises `copier recopy` end-to-end, so any regression would show up as extra sync output in test logs.

## D-016: Workspace file: root first, repos alphabetical

**Decision:** In the generated `<ade_name>.code-workspace`, the ADE root folder is the first entry, and portfolio repos are sorted case-insensitive alphabetically. Previously, portfolio repos appeared first in the order they were declared in `ade-repos.txt` (grouped by section: "Parloa infra core", "Stamps and Deployment Units", etc.) and the root appeared last.

**Context:** The user reported that finding a specific repo in the Cursor sidebar required scanning a non-obvious order that matched `ade-repos.txt`'s editorial grouping rather than the alphabet. With 15+ repos in the Parloa portfolio this was friction. Moving root to the top also makes workspace-level files (`AGENTS.md`, `README.md`, `.planning/`, `.copier-answers.yml`) the first thing the user sees when they open the workspace — which aligns with the "root contains orientation, subdirs contain the work" mental model baked into `AGENTS.md`.

**Implementation:** The Jinja template pipes `repo_names` through `| sort(case_sensitive=false)` and emits the root folder outside the loop, before the sorted entries. A `{% if sorted_names %},{% endif %}` guard handles the edge case of an empty `ade-repos.txt`.

**Trade-offs:**

- The section grouping in `ade-repos.txt` (`# Parloa infra core`, `# Stamps and Deployment Units`, ...) no longer propagates to the workspace view. That grouping is still meaningful for humans reading the portfolio file, just not rendered in the sidebar.
- Alphabetical ordering means `ade-template` (the template's own clone) is the first folder after root. Acceptable — consistent with the alphabetical rule and easy to find.

## D-017: `--skip-answered` semantics in the prescribed recopy command

**Decision:** The scaffolded `README.md` documents the routine update as `uvx copier recopy --trust --skip-answered --overwrite`. The `agentic-stack.md` "Changing your choices" section intentionally omits `--skip-answered` — that section is about re-answering existing questions, so skipping them would defeat the purpose. See D-022 for the full flag anatomy of the prescribed recopy command.

**Rationale:** Without `--skip-answered`, every recopy re-prompts for every stored answer in `.copier-answers.yml` (`ade_name`, `description`, the platform toggles, `portfolio_groups`, `extra_repos`, and the agentic-stack toggles — 10+ prompts). For a command that's supposed to be routine — "just refresh my ADE" — that volume of prompts is pure friction. `--skip-answered` suppresses prompts for questions that already have stored answers; newly added questions still prompt, so template evolution is surfaced exactly once when the user first updates past the version that added the question. That's the correct trade-off for the routine case and orthogonal to the intentional re-answer case (which is why "Changing your choices" opts out).

## D-021: gsd-docs shared planning integration

**Decision**: New ADEs are wired into `parloa/gsd-docs` by default via a copier
question `include_gsd_docs` (boolean, default `true`). The `gsd-docs` repo is
always cloned (it's in `ade-repos.txt`); the toggle controls whether `onboard.sh`
runs to create the `.planning/` symlink, install agent adapters, and set up the
`pre-push` hook.

**What happens on scaffold (`copier copy`) with `include_gsd_docs=true`:**

1. Task 2 clones `gsd-docs` with `-b docs` (all other repos use default branch).
2. Task 4 runs `gsd-docs/bin/new-project.sh` — migrates the template-seeded
   `.planning/` content (PROJECT.md, codebase intel) into
   `gsd-docs/projects/<ade_name>/` and replaces the local directory with a symlink.
3. Task 4 then runs `gsd-docs/bin/onboard.sh --workspace "$PWD"` — installs
   agent adapters (Cursor rule, CLAUDE.md/AGENTS.md sentinel blocks) and the
   `pre-push` hook inside `gsd-docs/.git/hooks/`.

**What happens with `include_gsd_docs=false`:**

1. `gsd-docs` is still cloned (available for manual onboarding later).
2. Task 4 is skipped (`when: "{{ include_gsd_docs }}"`).
3. `.planning/` remains a real directory tracked in the ADE repo.
4. Template docs (AGENTS.md, CLAUDE.md, README.md) omit gsd-docs sections via
   Jinja conditionals.

**Template file changes:**

- `ade-repos.txt`: added `git@github.com:parloa/gsd-docs.git`.
- `.gitignore` → `.gitignore.jinja`: conditional — when enabled, ignores the
  `.planning` symlink; when disabled, allowlists `.planning/` as a real directory.
- `AGENTS.md.jinja`: "GSD planning (gsd-docs)" section and agentic-stack bullet
  wrapped in `{% if include_gsd_docs %}`.
- `CLAUDE.md.jinja`: symlink/commit note wrapped in `{% if include_gsd_docs %}`.
- `README.md.jinja`: "What is this?" bullet and Files table conditional on toggle.
- `copier.yml`: new question + Task 4 with `when:` guard.
- `.planning/` seed content kept in template — `new-project.sh` migrates it on
  first scaffold; it's the fallback when gsd-docs is disabled.

**Why always clone, optionally onboard:** Engineers who initially skip gsd-docs
can manually run `gsd-docs/bin/onboard.sh --workspace .` later without
re-scaffolding. Keeping the clone present makes this a zero-friction upgrade path.

**Why default `true`:** Shared planning is the recommended workflow for Parloa
ADEs. Defaulting to enabled ensures new engineers land in the happy path without
needing to know about the toggle. Advanced users can set `include_gsd_docs=false`
for isolated experiments.

## D-022: Update command is `copier recopy --trust --skip-answered --overwrite`

**Decision:** The documented, supported update flow for any ADE is a single command:

```bash
uvx copier recopy --trust --skip-answered --overwrite
```

`recopy` re-renders every template-owned file from the current template and writes
the result into the destination. It does not perform copier's structural 3-way
merge. `_skip_if_exists` is empty, so no file is protected from re-render. The
resulting contract is: **whatever the latest template version renders is what's
on disk after the command returns.** No file drifts, nothing is quietly preserved
from an earlier template version.

**Flag anatomy:**

- `--trust` — required because the template uses `_tasks` (clone loop, GSD install,
  auto-commit). Without it, copier refuses to execute arbitrary commands.
- `--overwrite` — required on `recopy`; otherwise copier prompts per-file
  ("overwrite? [Y/n]") for every changed file. Recopy is definitionally "template
  wins", so the prompt is pure friction.
- `--skip-answered` — reuses answers already stored in `.copier-answers.yml` for
  existing questions, so routine updates do not re-prompt. Newly introduced
  questions (e.g. a future `include_new_thing`) are still prompted — template
  evolution surfaces to the user exactly once, at the first recopy after the
  template adds the question.

**Why `--skip-answered`, not `--force` or `--defaults`:** `--force`
(`--defaults --overwrite`) silently default-answers any new question. That would
make template evolution invisible: a new `include_*` toggle added in a later
version would be quietly answered `false` (or whatever the default is) on every
user's next update without them ever knowing the question exists. `--skip-answered`
gives the correct default-on-re-answer behavior *only for already-answered
questions*, which is the combination we want.

**Why `recopy` and not `copier update`:** `copier update` is copier's three-way
merge (old template, new template, destination). It preserves local modifications
where the user has diverged from the old template — which is the right default for
*most* copier templates but the wrong default here. The ADE's template-owned files
(AGENTS.md, CLAUDE.md, `.planning/codebase/*.md`, the workspace file, `ade-repos.txt`,
`.gitignore`) have no legitimate "diverged" state: they're derived artifacts, not
hand-authored content. Three-way merge on those files only hides template evolution.
`recopy` + `--overwrite` makes the intent explicit.

**What the auto-commit adds:** a single consolidated `_tasks` entry that,
after all other tasks run, decides between two paths based on whether `.git/`
already exists at the destination:

- No `.git/` (first `copier copy`): `git init && git add -A && git commit -m
  'ADE scaffold'`, then open the workspace in Cursor.
- `.git/` exists (recopy or update): detect conflict markers; if clean, exit;
  otherwise `git add -A && git commit -m "chore: copier recopy to <hash>"` where
  `<hash>` is `_copier_conf.vcs_ref_hash`.

The recopy commit is atomic and revertable (`git revert HEAD`) if the user
decides they don't want this particular template bump.

**Why key off `.git/`, not `_copier_operation`:** copier's `run_recopy` is
implemented as `run_copy` under the hood and is decorated with
`@as_operation("copy")`, so `_copier_operation` equals `'copy'` for BOTH
`copier copy` and `copier recopy`. It only becomes `'update'` for `copier
update` (the 3-way-merge command we do not prescribe). That means
`_copier_operation` cannot distinguish "first-time scaffold" from "user is
re-applying the template" — the on-disk `.git/` is the reliable signal.

**Why `_copier_conf.vcs_ref_hash` in the commit message and not a semver
tag:** `version_from` / `version_to` are only populated inside `_migrations`
runs, which fire exclusively under `copier update`. Regular `_tasks` do not
have a PEP440 "target version" variable available. `_copier_conf.vcs_ref_hash`
is the commit SHA of the template ref being applied and is always populated,
so it's the correct answer for the auto-commit trailer. The hash is stable
across runs and `git log --oneline` still shows it next to the commit.

**Trade-offs:**

- Users who hand-edit template-owned files (`ade-repos.txt`, the workspace file)
  lose those edits on the next recopy. This is the point — those files are
  generated from answers (see D-023). If a user wants the edit, they change the
  answer and recopy.
- Commit-hook-heavy projects will run their pre-commit hooks on the auto-commit.
  We respect user git policy (no `--no-verify` / `--no-gpg-sign`). If a hook fails,
  the commit fails and the user sees the error — same as any other commit.

## D-023: Portfolio is answer-derived, not file-edited

**Decision:** Every input to the repo portfolio is a copier answer stored in
`.copier-answers.yml`:

- `include_gsd_docs`, `include_agent_guardrails`, `include_cursor_self_hosted_agent`
  — platform-layer toggles.
- `portfolio_groups` (multiselect) — which predefined groups of Parloa repos to
  include.
- `extra_repos` (multiline) — freeform list for anything outside the groups.
- `default_org` (hidden, defaults to `parloa`) — org used when expanding bare
  repo names; overridable via `--data default_org=other-org`.

`template/ade-repos.txt.jinja` and `template/{{ ade_name }}.code-workspace.jinja`
are rendered from the same set of macros in `_portfolio.jinja` at the
template root: `platform_repos()`, `group_repos(group)`, `resolve_url()`,
`repo_dir()`. The macro file lives at the template root (not under
`template/`) because Copier's Jinja search path is the template root, not
`_subdirectory` — files under `template/` can import `_portfolio.jinja` by
name, and the file itself is never rendered as output because it's outside
`_subdirectory`. The two generated files are derived artifacts, not
hand-authored content. On every recopy they match the current answers.

**Group contents:**

| Group | Repos |
|-------|-------|
| `core-infra` | `parloa-infra`, `parloa-infra-global`, `parloa-infra-it`, `parloa-infra-pre-stamp`, `parloa-k8s`, `parloa-terraform-modules` |
| `stamps` | `stamps-catalog`, `stamps-release-channels`, `crossplane-xrd` |
| `catalog` | `engineering-catalog` |
| `kitchens` | `claudes-kitchen`, `open-kitchen` |
| `template-source` | `madi-parloa/ade-template` |

Add a new repo to a group by editing `_portfolio.jinja` at the template root;
every ADE that includes that group picks it up on the next recopy.

**Why answers and not files:** A text-file-as-source-of-truth (where users edit
`ade-repos.txt` directly) makes two bugs structurally possible:

1. **Drift.** User edits the file; copier doesn't know about the edit; the file
   and `.copier-answers.yml` diverge. Future recopies either revert the edit
   (template wins) or preserve it (merge), and there's no single answer for what
   "latest template" means on that file.
2. **Hidden template evolution.** Template adds a default repo. On update, either
   the user has edited the file (edit wins, template addition never lands) or
   not (template wins, but the file no longer reflects user intent).

When the portfolio is derived from answers, neither is representable. Answers
evolve on re-answering; files are always freshly generated; "latest template
output" is a single, well-defined thing.

**Escape hatches:**

- **Ad-hoc repo without re-answering:** `--data extra_repos="$(cat file)"` on the
  recopy command passes the list directly, bypassing the prompt.
- **Ad-hoc org override:** `--data default_org=my-org` changes the org applied to
  bare repo names for that single recopy.

**Trade-offs:**

- Adding a single repo to this ADE requires re-running recopy without
  `--skip-answered` and editing the `extra_repos` answer. One command vs. one
  text-file edit. Acceptable because the recopy also re-validates every other
  template-owned file and reclones anything the answer change introduced.
- `portfolio_file` (from earlier versions of the template) is kept as `when: false`
  in `copier.yml` so older `.copier-answers.yml` files still load without
  `UnknownQuestionsError`. Its value is ignored by the template. On the first
  recopy from an older version, the user is prompted for the new questions and
  the answer file is rewritten with the current shape.

## D-024: Repo-name shorthand DSL

**Decision:** Every repo reference in the portfolio (platform toggles, group
contents in `_portfolio.jinja` at the template root, `extra_repos` input) is
a **short name**, resolved to a full git URL at render time by the
`resolve_url(name)` macro:

| Input | Resolved URL |
|-------|--------------|
| `some-repo` | `git@github.com:{{ default_org }}/some-repo.git` (i.e. `parloa/some-repo`) |
| `parloa/some-repo` | `git@github.com:parloa/some-repo.git` |
| `madi-parloa/some-repo` | `git@github.com:madi-parloa/some-repo.git` |
| starts with `git@` / `git+` / contains `://` / ends `.git` | pass-through |

Lines that are empty or start with `#` are ignored. Paths with more than two
segments (e.g. `org/suborg/repo`) are not supported — they're not a real GitHub
shape.

The on-disk folder name is derived by `repo_dir(name)`: split on `/`, take the
last segment, strip trailing `.git`. So `madi-parloa/agent-guardrails` clones
into `agent-guardrails/`, and `git@github.com:foo/bar.git` clones into `bar/`.

**Why short names:** with 16 repos in the Parloa portfolio and a future where
users add their own, the full URL is boilerplate. `git@github.com:parloa/`
appears on every line. Short names keep the `_portfolio.jinja` group
definitions readable and let `extra_repos` feel like a one-repo-per-line list
instead of a URL list:

```
cool-tool
madi-parloa/scratch
git@github.com:vendor/vendored-thing.git
```

...expands to three full URLs at render time, with the default org applied to
the first line.

**Why a macro, not a shell resolver:** the resolver runs at *render* time, not
task time. That means `ade-repos.txt` and `<ade>.code-workspace` are both
derived from the same resolver output in the same render pass, so they cannot
disagree about what URL or folder name a short entry refers to. A shell-side
resolver running inside a `_task` would compute the URL later than the workspace
file rendering, creating a window where the two disagree.

**Why `default_org` is hidden (`when: false`):** for the overwhelming majority
of ADEs (Parloa-internal), the default `parloa` is correct. Prompting for it
every scaffold is noise. Users scaffolding outside Parloa override once via
`--data default_org=other-org`; the answer is stored and every future recopy
uses it.

**Trade-offs:**

- Users reading `ade-repos.txt` see fully resolved git URLs (they're the target
  of `git clone`), but users *writing* `extra_repos` or editing
  `_portfolio.jinja` at the template root see short names. The asymmetry is
  intentional: `ade-repos.txt` is a machine artifact for the clone loop; the
  human-facing inputs stay terse.
- No support for three-segment paths (`org/suborg/repo`). Not a real GitHub shape,
  rejected to keep the grammar unambiguous.

## D-025: Template owns the gsd-docs sentinel region

**Decision:** The gsd-docs multi-repo-paths sentinel region — the block between
`<!-- GSD-DOCS:multi-repo-paths:BEGIN -->` and `<!-- GSD-DOCS:multi-repo-paths:END -->`
markers in `CLAUDE.md` and `AGENTS.md` — is rendered by the template
(`template/CLAUDE.md.jinja`, `template/AGENTS.md.jinja`), gated on
`include_gsd_docs`, with the handle substituted from the new `gsd_docs_handle`
question. `gsd-docs/bin/onboard.sh`'s `inject_sentinel` function still runs
afterwards; it finds the sentinel already present with identical content, so
its rewrite is byte-identical and produces no diff.

**Context:** Before this decision, only `onboard.sh` knew about the sentinel
region. It appended the block to `CLAUDE.md` and `AGENTS.md` after every
copier run. On the next `copier recopy`:

1. Copier renders `CLAUDE.md` without the sentinel (template didn't declare it).
2. Disk has "template body + sentinel" from the previous `onboard` run.
3. Copier sees the divergence, declares `conflict`, applies `--overwrite`,
   writes a body with no sentinel.
4. `onboard.sh` runs as task 3 and re-injects the sentinel.
5. Task 4 (finalize) finds no diff (net-zero change) and commits nothing.

The end state is correct, but the per-recopy log carries two noisy
`conflict / overwrite` lines for `CLAUDE.md` and `AGENTS.md` every time, and
the flow relies on two non-trivial pieces of state (template render + post-task
injection) disagreeing and being reconciled. That's the wrong invariant — the
template should own everything under its name.

**How byte-identity is preserved:** `inject_sentinel` is byte-idempotent when
the existing block matches what it would render: it reads the target file line
by line, substitutes the whole region between `BEGIN` and `END` markers with
the freshly-rendered snippet, and writes back. If the rendered snippet is
identical to what was already there (same handle, same layout), the new bytes
equal the old bytes. Copier then reports `identical` on recopy, not `conflict`.

This requires the template render to match onboard's `printf '\n%s\n'` layout
exactly: one blank line before `<!-- BEGIN -->`, single trailing newline after
`<!-- END -->`. The Jinja tails use `{% if include_gsd_docs %}` (no left-strip)
before the block and `{%- endif %}` (left-strip the trailing newline after
`<!-- END -->`) after it to produce those exact bytes.

**Why a `gsd_docs_handle` question instead of autodetection:** Copier answers
are resolved at render time, before any `_task` has run. `gsd-docs/bin/onboard.sh`
detects the GitHub handle at task-3 time via `gh api user` or
`gsd-docs/.gsd-docs-user`, but that's too late — the render has already
happened and the handle placeholder would still be literal in the template
output. The cleanest fix is a dedicated question, gated on `include_gsd_docs`
so it's only asked when relevant, with an empty default so the user must
provide it once.

**Consequence of handle mismatch:** If `gsd_docs_handle` differs from what
`onboard.sh` detects, `inject_sentinel` rewrites the block with the detected
handle and the rendered-vs-disk diff reappears on the next recopy. Fix by
re-running `copier recopy` without `--skip-answered` and correcting the
answer. This is the single concrete reason the question exists and is not
hidden behind `when: false`.

**Trade-off:** A new answer key (`gsd_docs_handle`) to reconcile a problem
that lived entirely in onboard/copier timing. Accepted because the
alternative (parsing `gsd-docs/.gsd-docs-user` inside a `_task` and having
it rewrite the template output) would put the render under two owners
again — exactly what this decision removes.

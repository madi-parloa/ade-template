# ADE Template — Decision Log

Decisions made during design and implementation, with context for why.

## D-001: No custom CLI

**Decision:** Use copier as the scaffolding tool instead of building a custom `ade` CLI.

**Context:** Multiple iterations designed an `ade new/launch/list/rm` CLI in bash+Python. Each iteration revealed that the core operation (clone repos + run install) was too thin to justify a new tool. Copier covers scaffolding, parameterization, and updates.

**Alternatives considered:**
- Custom bash CLI (~200 lines) — rejected: maintenance burden for marginal UX gain
- degit (no `.git/` in output) — rejected: no parameterization, no update lifecycle
- cookiecutter — rejected: copier has `_tasks` and `copier update`; cookiecutter doesn't

**Trade-off:** Depends on copier's idiosyncrasies (e.g., `--trust` required for `_tasks`, git required for `copier update`). Accepted because the alternative (custom tooling) has worse idiosyncrasies.

## D-002: Workspace-local installation

**Decision:** Install scripts write to `<ade>/.cursor/`, not `~/.cursor/`.

**Context:** The user's requirement was explicit: "whatever we are installing during ADE initialization is being installed to work in the workspace only, not global." GSD supports `--local --cursor` for this.

**Alternatives considered:**
- Shadow HOME (override `$HOME` per Cursor process) — rejected for v1: complex plumbing, not needed because Cursor reads workspace-level `.cursor/` natively
- Fan-out symlinks (per-item symlinks from shadow to real `~/.cursor/`) — designed in detail but rejected as over-engineered for the use case

## D-003: _subdirectory: template

**Decision:** Template content lives under `template/`, copier config at repo root.

**Context:** Without `_subdirectory`, copier.yml and `.jinja` files appear in the output directory. The user pointed out that copier config files should not be mixed with template content.

## D-004: Git init for copier update

**Decision:** `_tasks` includes `git init && git add -A && git commit` guarded by `_copier_operation == 'copy'`.

**Context:** `copier update` hard-requires a git repo at the destination. Verified via hostile subagent research: the source code raises `UserMessageError("Updating is only supported in git-tracked subprojects.")` with no bypass flag.

Copier does NOT auto-init git (confirmed: no `_init_git` setting exists, [Discussion #2167](https://github.com/orgs/copier-org/discussions/2167) requests it).

The git repo is local only — no remote.

**Guard is critical:** Without `when: "{{ _copier_operation == 'copy' }}"`, the git tasks would run in copier's internal temp directories during update, causing `fatal: not a git repository`. Discovered during end-to-end testing.

## D-005: Portfolio as file input

**Decision:** Default portfolio in `ade-repos.txt`, overridable via `--data portfolio_file=<path>`.

**Context:** User asked: "what if we make the list of repos via copier inputs, but I don't have to write a long list — feed a file to it."

**Implementation:** `_tasks` copies the file over `ade-repos.txt` before running install. Absolute paths required because tasks run in the output directory.

## D-006: Pre-seeded codebase intel

**Decision:** Seed `.planning/codebase/*.md` from the existing workspace analysis.

**Context:** GSD planning commands read these files to ground reasoning. Without them, every new ADE requires `/gsd-map-codebase` (minutes of wall time, multiple mapper subagents) before planning can begin.

Seven files: ARCHITECTURE, CONCERNS, CONVENTIONS, INTEGRATIONS, STACK, STRUCTURE, TESTING. All produced by `/gsd-map-codebase` on 2026-04-07.

## D-007: ade-repos.txt stays in output; ade-install.sh removed from template

**Decision:** Keep `ade-repos.txt` in the ADE (not hidden or deleted after use). The separate `ade-install.sh` script was removed from the template; its clone loop and GSD install now live directly in copier `_tasks`. Both run on `copier copy` **and** `copier update`, but the sync loop is carefully constrained to be idempotent and cheap on repeated execution (see D-009).

**Context:** Early iteration tried render → run → delete. User said: "might as well keep them, just rename to something understandable." The `ade-` prefix was chosen to make clear `ade-repos.txt` belongs to the ADE template system, not to any repo in the portfolio.

Version history of the install flow:
1. **v0.1.x – v0.6.x:** `ade-install.sh` shipped as a re-runnable sync tool. Users could edit `ade-repos.txt` and re-run `bash ade-install.sh` to clone new repos / pull existing ones without touching copier. `copier copy` invoked the script via a `_tasks` entry guarded by `_copier_operation == 'copy'`.
2. **v0.7.0:** The script was inlined into unguarded `_tasks` so that `copier update` would also re-sync the portfolio and GSD. This made `uvx copier update --trust` the single entry point for both template updates and re-sync. The loop did clone-**or-pull**: missing repos were cloned, existing repos were `git pull --ff-only`'d. It turned out to run the sync + GSD install **three times** per update because copier's double-render algorithm executes `_tasks` in (a) the "old baseline" temp render, (b) the "new target" temp render, and (c) the real target project. With a realistic portfolio this was ~30–90s of redundant network traffic: 3× `npx get-shit-done-cc` downloads plus 3× `git pull` on every repo, for zero user benefit (the temp renders are discarded). See D-009 for the copier behavior.
3. **v0.7.1:** Sync and GSD install were re-guarded with `_copier_operation == 'copy'`. They ran only on first scaffold. This killed the 3× cost but regressed a real use case: adding a new repo to `ade-repos.txt` in the template no longer propagated to existing ADEs on `copier update`. Users had to run a manual clone snippet from the README. The v0.7.0 design had the right semantics (update = sync) but the wrong implementation (pull everything).
4. **v0.7.2+ (current):** Sync and GSD install are **unguarded again**, but the sync loop is rewritten as **clone-if-missing, never pull**. Existing repos are never touched. Template additions to `ade-repos.txt` propagate on `copier update` via one clone per new repo. Under the 3× double-render execution, the first iteration clones the missing repo and the other two see `[ -d "$dir" ]` and skip — net cost is one clone, not three. Users who want to update already-cloned repos run the explicit pull one-liner documented in the scaffolded `README.md` — this is deliberately not automatic because `git pull` on a user's WIP branch is the class of thing a scaffolder should never do silently.

**Trade-off:** `copier update` no longer auto-pulls existing repos. Users wanting to refresh everything run `for d in */; do [ -d "$d/.git" ] && git -C "$d" pull --ff-only; done`. Accepted because: (a) auto-pulling over a user's uncommitted work is strictly worse than requiring an explicit action, and (b) the original user-visible pain point — "new repo in template doesn't land on update" — is fixed.

## D-008: Answers file for copier update

**Decision:** Include `{{_copier_conf.answers_file}}.jinja` in the template.

**Context:** Copier does NOT auto-generate `.copier-answers.yml` unless the template explicitly includes a Jinja file with that name. Discovered when the answers file was missing from scaffolded ADEs. Without it, `copier update` can't determine which template version was used or what answers were given.

## D-009: Which `_tasks` are guarded, and why

**Decision:** The guard rule is **"guard destructive or one-shot tasks; leave idempotent tasks unguarded so template evolution propagates."**

| Task | Guarded to `copy` only? | Why |
|---|---|---|
| `cp "{{ portfolio_file }}" ade-repos.txt` | no | Trivial; no-op when `portfolio_file` is empty. |
| Portfolio sync (clone-if-missing loop) | **no** | Must propagate new repos added to `ade-repos.txt` on update. Idempotent: 3× execution results in 1 clone + 2 no-op `[ -d ]` checks. See D-007. |
| GSD install (`npx -y get-shit-done-cc@latest --local --cursor`) | **no** | `@latest` is the point — template bumps should land on existing ADEs. 3× execution = 3× registry check, which is the acknowledged cost. |
| `git init && git add -A && git commit` | **yes** | On copy, establishes the `.git/` that `copier update` requires. On update there's no `.git/` in copier's internal temp directories and `git add -A` would fail with `fatal: not a git repository` (original v0.1.x motivation for D-004). |
| `open -a Cursor '{{ ade_name }}.code-workspace'` | **yes** | Otherwise Cursor would re-launch on every template update. |

**Context — the copier double-render algorithm:** Copier's `update` does a structural 3-way merge by re-rendering the template twice:

1. Re-render the **old baseline** version (from `.copier-answers.yml`'s `_commit`) into an internal temp directory, executing `_tasks` there.
2. Re-render the **new target** version into a second temp directory, executing `_tasks` there too.
3. Diff (1) against (2), apply the delta to the real project, execute `_tasks` in the real target.

Any unguarded `_tasks` entry runs **three times** per `copier update`. This constraint is the whole reason the guard/no-guard decision matters: you either ensure the task is idempotent and cheap on repeated invocation, or you guard it to `copy` only. There is no third option.

**Version history:**

- **v0.7.0:** All sync/install tasks unguarded, but the sync loop did clone-**or-pull**. 3× execution caused 3× `git pull` on every existing repo per update (~30–90s of wasted network traffic) and 3× `npx get-shit-done-cc` downloads.
- **v0.7.1:** Everything non-trivial guarded to `copy`. Killed the cost, but regressed propagation: new repos added to `ade-repos.txt` in the template no longer landed on existing ADEs via `copier update`. The "single entry point for updates" story was broken.
- **v0.7.2+ (current):** Sync + GSD install unguarded again; sync rewritten as **clone-if-missing, never pull** so 3× execution is idempotent (1 clone + 2 skips per new repo). GSD install is still 3×, accepted as the cost of `@latest` tracking. `git init` and Cursor launch remain guarded for the reasons in the table above.

**Trade-off:** `copier update` does not auto-pull existing repos (only clones new ones). Users wanting to refresh all existing clones run the explicit pull one-liner from the scaffolded `README.md`. This is deliberate: silently `git pull`-ing over a user's WIP branch is a class of side-effect a scaffolder should never produce.

## D-010: Include ade-template in its own portfolio

**Decision:** `ade-repos.txt` includes `git@github.com:madi-parloa/ade-template.git`.

**Context:** User requested it so the template source is available inside every ADE for reference and potential modification.

## D-011: Version tags for copier

**Decision:** Tag releases with PEP 440-compatible versions (`v0.1.0`, `v0.2.0`, etc.).

**Context:** Copier uses git tags to track template versions. Without tags, copier prints "No git tags found" and can't do proper version comparison for `copier update`.

## D-012: Broken tags are unrecoverable in updates

**Decision:** Never tag a release without first running `bash test.sh` successfully. If a broken tag ships, delete it from the remote immediately.

**Context:** `copier update` computes its diff by re-rendering the template at BOTH the current baseline version (stored in `.copier-answers.yml`) and the target version. If the baseline tag has a jinja error (missing include, bad syntax, etc.), the baseline render crashes and the entire update fails — with no flag to skip baseline regeneration. The only user-side workarounds are:

1. Hand-edit `.copier-answers.yml` to point `_commit` at the last known-good tag (destructive to copier's merge semantics on the affected file).
2. Delete the broken tag upstream so copier falls back to the previous tag.

Neither is acceptable in a shared template. Therefore: pre-tag tests are mandatory, and `v0.6.0` was force-deleted after it shipped a broken `{% include %}` path that only manifested at `copier update` time (the broken-baseline double-render path).

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

**Decision:** `template/.gitignore` ignores every top-level directory by default via `/*/`, then allowlists `.planning/` with `!/.planning/`. Individual portfolio repo names are not enumerated. Inside `.planning/`, GSD-volatile subdirs are re-ignored explicitly.

**Context:** Prior versions enumerated every cloned repo in `.gitignore`:

```
parloa-infra/
parloa-k8s/
claudes-kitchen/
...
```

This had two failure modes:

1. **Missed entries caused gitlink pollution.** `ade-template/` was absent from the list, so during `_tasks` on first scaffold, `git add -A` tracked the freshly cloned `ade-template/` as a **gitlink** (`160000` mode) — git's way of recording a nested repo's HEAD pointer. On subsequent `copier update`, as the template's HEAD advanced (e.g., to `v0.7.1`), the working tree reported `ade-template` as modified, which tripped copier's "Destination repository is dirty; cannot continue" check. The user worked around this by deleting `ade-template/` from the destination — exactly the kind of manual unblock the template is supposed to prevent.
2. **Maintenance burden.** Adding a new repo to `ade-repos.txt` required remembering to add it to `.gitignore` as well. Silent coupling; easy to forget; fails only on the second `copier update` after the miss.

**Allowlist approach:** Invert the default. Ignore every top-level directory unconditionally (`/*/`), then surface only the template-managed ones with `!/.planning/`. Effects:

- Every current and future repo in `ade-repos.txt` is ignored with no `.gitignore` edit.
- `.cursor/` is ignored (no longer needs an explicit entry).
- Template-managed **files** at root (`AGENTS.md`, `README.md`, `.copier-answers.yml`, `<ade>.code-workspace`, `ade-repos.txt`, etc.) are unaffected — `/*/` matches only directories.
- `.planning/` is allowlisted; GSD-volatile subdirs inside it (`milestones/`, `phases/`, `intel/`, `research/`, `threads/`, `state/`) and two files (`config.json`, `ROADMAP.md`) are still ignored. Only `PROJECT.md` and `codebase/*.md` ship via the template.

**Trade-off:** If someone genuinely wanted to track a cloned repo's working copy (e.g., ship it as part of the scaffolded project), they'd need to add an explicit `!/name/` allowlist. No current use case needs this, and doing so would be conceptually wrong — portfolio repos are external dependencies, not scaffolded content.

**Gitlink cleanup for existing ADEs:** ADEs scaffolded before v0.7.2 already have nested repos tracked as gitlinks in their `.git/index`. After `copier update` brings in the new `.gitignore`, run `git rm --cached -r <repo-name>` (without `-f`) to drop each stale pointer; the working tree is untouched. The new `.gitignore` then keeps them out on every future `git add`.

## D-015: Skip `_tasks` in copier's temp render dirs (supersedes the "3× execution accepted" stance in D-007 / D-009)

**Decision:** The portfolio-sync task, the GSD install task, and the `cp portfolio_file` task each guard their own body with a `case "$PWD" in */copier._main.*) exit 0 ;; esac` check at the top. On `copier update`, this causes those tasks to **no-op** in copier's internal render temp directories (`/private/var/folders/.../copier._main.old_copy.*` and `.../copier._main.new_copy.*`) and run **only once**, in the real destination.

**Context — how we got here:** D-007 and D-009 accepted that `_tasks` fires three times per `copier update` because copier's update algorithm re-renders the template at the old baseline and the new target for its three-way merge. The earlier conclusion was "make every unguarded task idempotent and cheap under 3× execution." For the portfolio sync that was fine (after the clone-if-missing rewrite in v0.7.2, 3× = 1 real clone + 2 `[ -d ]` skips). For the GSD install it was the acknowledged cost — 3× `npx -y get-shit-done-cc@latest --local --cursor`, which is one npm registry round-trip plus a re-install of ~79 skills each time.

In practice the GSD install cost was not cheap: each invocation prints its full banner, refetches the npm manifest, and rewrites `.cursor/`. On a realistic `copier update` this meant three back-to-back GSD banners in the log and ~5–10 seconds of redundant work per invocation. The "accepted cost" story also made reading `copier update` output confusing — the user sees cloning output twice and GSD install output three times, which reads like a bug even though it was correctly documented as a feature.

The pwd gate eliminates both cost and confusion. After v0.8.3, a clean `copier update` on an already-synced ADE produces: two `==> [skip]` lines for the old_copy render, the real sync/install output for the destination, and two more `==> [skip]` lines for the new_copy render.

**Why a pwd check, not some other gate:**

- **Checking `_copier_operation`** — copier exposes this Jinja variable (`copy` vs `update`), but all three renders on update set it identically. It does not distinguish the temp renders from the real destination.
- **Checking for `.git/` in `$PWD`** — the real destination has `.git/` (either pre-existing or created by task 4 on copy). Temp render dirs do not. BUT: on `copier copy`, task 2 (sync) and task 3 (GSD install) run **before** task 4 (`git init`), so at that moment the real destination also has no `.git/`. Using `.git/` as the gate would false-skip every fresh scaffold. Rejected.
- **Checking `_copier_conf.answers_file`** — copier renders `.copier-answers.yml` in every render, including temp dirs. Not a discriminator.
- **Sentinel file / lockfile** — works, but requires a cleanup step on success and opens the question "what if the cleanup is missed, does the ADE become stuck?" More moving parts than the pwd match.
- **Moving expensive work to `_migrations`** — `_migrations` fire only on update, not copy. Would require duplicating the bash across `_tasks` (for copy) and `_migrations` (for update). Worse DRY.
- **Waiting for a copier upstream fix** — no issue filed; copier's current behavior is defensible (tasks ARE part of the template, and the diff renders ARE template renders). Unknown timeline.

**Why the pwd check is correct:** On `copier copy`, there are no temp render dirs — copier renders straight into the destination. The gate's `case` never matches, every task runs once. On `copier update`, copier always names its temp dirs with `copier._main.<phase>_copy.<random>` where `<phase>` is `old` or `new`. The gate matches both and skips. Empirically validated with an instrumented template: copy produced `clone=1 gsd=1 git-init=1`; update produced `clone=1 gsd=1 git-init=0` plus visible `==> [skip]` messages for both temp renders.

**Risks:**

1. **Copier renames its temp dirs in a future version** (e.g., `copier._main.*` → `copier._render.*`). The gate would silently stop matching and updates would regress to 3× execution. Correct but wasteful — same shape as pre-v0.8.3 behavior. Mitigation: a comment in `copier.yml` points at this decision; `test.sh` exercises `copier update` end-to-end so any regression in temp-dir naming would surface as more-than-expected sync output in test logs.
2. **A user's real destination path happens to contain the literal substring `copier._main.`.** Theoretically a false positive. Practically unreachable — that string doesn't occur in natural directory names.

**One-time migration cost:** The very first `copier update` from v0.8.2 (no gate) to v0.8.3 (with gate) still does 2× execution instead of 3×. Copier's three-way merge renders the **old baseline** using the old template code, and v0.8.2's `_tasks` have no gate — so the old_copy temp render still does a full sync + GSD install that gets thrown away. The new_copy render uses v0.8.3's gate and correctly skips. From v0.8.3 onward, every update is fully clean. Retroactively fixing v0.8.2 is not possible (the tag is immutable and multiple ADEs in the wild point to it).

**What this replaces:**

- D-007's narrative that `v0.7.2+` "accepts 1 clone + 2 skips per new repo" under 3× execution is still factually accurate for v0.7.2 – v0.8.2 but is **no longer the policy from v0.8.3 onward**. Update is 1× execution in the destination.
- D-009's table of "Which tasks are guarded, and why" stays correct for the `when: copy` guards on `git init` and Cursor launch. The three `_copier_operation`-unguarded rows (`cp portfolio_file`, portfolio sync, GSD install) are now additionally `PWD`-gated via this decision. See `copier.yml` for the authoritative current state.

**Related changes in the same v0.8.3 release:**

- D-016 documents the switch to alphabetical-with-root-first ordering in the generated Cursor workspace file.
- D-017 documents the switch to `--skip-answered` in the `README.md` update instructions.

## D-016: Workspace file: root first, repos alphabetical

**Decision:** In the generated `<ade_name>.code-workspace`, the ADE root folder is the first entry, and portfolio repos are sorted case-insensitive alphabetically. Previously, portfolio repos appeared first in the order they were declared in `ade-repos.txt` (grouped by section: "Parloa infra core", "Stamps and Deployment Units", etc.) and the root appeared last.

**Context:** The user reported that finding a specific repo in the Cursor sidebar required scanning a non-obvious order that matched `ade-repos.txt`'s editorial grouping rather than the alphabet. With 15+ repos in the Parloa portfolio this was friction. Moving root to the top also makes workspace-level files (`AGENTS.md`, `README.md`, `.planning/`, `.copier-answers.yml`) the first thing the user sees when they open the workspace — which aligns with the "root contains orientation, subdirs contain the work" mental model baked into `AGENTS.md`.

**Implementation:** The Jinja template pipes `repo_names` through `| sort(case_sensitive=false)` and emits the root folder outside the loop, before the sorted entries. A `{% if sorted_names %},{% endif %}` guard handles the edge case of an empty `ade-repos.txt`.

**Trade-offs:**

- The section grouping in `ade-repos.txt` (`# Parloa infra core`, `# Stamps and Deployment Units`, ...) no longer propagates to the workspace view. That grouping is still meaningful for humans reading the portfolio file, just not rendered in the sidebar.
- Alphabetical ordering means `ade-template` (the template's own clone) is the first folder after root. Acceptable — consistent with the alphabetical rule and easy to find.

## D-017: Use `--skip-answered` in documented `copier update` invocations (where appropriate)

**Decision:** The scaffolded `README.md` documents `uvx copier update --trust --skip-answered` (not `--trust` alone) in the routine "Updating" and "Different repos" sections. The `agentic-stack.md` "Changing your choices" section intentionally does NOT use `--skip-answered` — that section is explicitly about re-answering questions, and skipping them would defeat the purpose.

**Context:** Without `--skip-answered`, every `copier update` re-prompts for the answers already stored in `.copier-answers.yml` (`ade_name`, `description`, `portfolio_file`, and four optional-integration toggles). The user has to press Enter seven times to accept the defaults, or think about each prompt again if they're in a hurry. For a command that's supposed to be routine — "just refresh my ADE" — seven prompts are friction.

The `--skip-answered` flag (copier 9.x, documented in `uvx copier update --help`) suppresses prompts for questions that already have stored answers. New questions (e.g., if a future template version adds `include_xyz`) still prompt — which is the correct behavior.

The user originally tried `--skip-answers` (plural) and got `Error: Unknown switch --skip-answers`. The correct flag is `--skip-answered`.

**Where `--skip-answered` should NOT be used:** The `agentic-stack.md` "Changing your choices" block specifically exists for the case "I want to enable a code-graph MCP now, so I need to re-answer `include_code_graph_mcp`". Adding `--skip-answered` there would silently keep the old answer and confuse the user. Left as `--trust` only.

**Trade-off:** None that we can see. `--skip-answered` is strictly better for the routine-update case and orthogonal to the new-question-added case.

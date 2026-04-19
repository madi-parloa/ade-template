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

## D-018: `copier update` auto-commits its own changes (one-command-forever update)

**Decision:** A final `_task` in `copier.yml`, gated to `_copier_operation == 'update'` and pwd-gated like the other update tasks, runs `git add -A && git commit -m "chore: copier update to <new_commit>"` at the end of every successful `copier update`. If the 3-way merge left unresolved conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) in any modified file, the auto-commit is aborted with a loud message and the tree is left dirty for the user to resolve manually. If nothing changed (the update was a no-op), the task exits silently with `==> [auto-commit] nothing to commit`.

**Context — what problem this solves:** From v0.8.3 onward, `copier update` renders its changes into the working tree and exits, leaving a dirty tree for the user to review and commit. This is copier's designed-in behavior — it cannot safely auto-commit because a 3-way merge may produce conflicts that a human must resolve. The consequence in practice:

1. User runs `uvx copier update --trust --skip-answered`.
2. Three files show as `M` in `git status`.
3. User forgets to `git commit` (or defers it "until after reviewing").
4. Days later, user runs `uvx copier update --trust --skip-answered` again → copier refuses with "Destination repository is dirty; cannot continue".
5. User has to figure out what the old dirty files were, commit them, then re-run update.

This broke the stated promise of the `Updating` section in the generated `README.md` ("Single entry point. Pulls template/docs changes…") because the single entry point, in practice, sometimes required a second manual step that wasn't documented.

**Why auto-commit is safe here (even though copier itself refuses to do it generically):**

Copier refuses to auto-commit because the general case includes:
- Unrelated WIP in the working tree at update time.
- 3-way merge conflicts that a human must resolve.
- Projects with commit hooks, signing requirements, or review rules that prohibit automated commits.

Each of those is addressed:
- **Unrelated WIP:** copier already refuses updates on a dirty working tree. At the moment our auto-commit task runs, every dirty path in the destination is copier-managed by definition (either a rendered template file or `.copier-answers.yml` itself). `git add -A` is therefore safe in scope. If the user wants to keep WIP separate, they should be committing or stashing it before the update, which is already required.
- **Merge conflicts:** the task scans every modified file for `^(<{7}|={7}|>{7})( |$)` markers (the three canonical git conflict markers as whole-line starts) and aborts auto-commit if any are found. The message directs the user to resolve and commit manually, which matches the pre-v0.8.4 behavior exactly. Zero regression when conflicts happen.
- **Commit hooks / GPG signing:** the task does NOT pass `--no-verify` or `--no-gpg-sign`. If the user's gitconfig requires signing or runs pre-commit hooks, those run. If they fail, the commit fails, the tree is left dirty, and the user gets the hook/gpg error — again, same as pre-v0.8.4. No regression; we respect user git policy.

**Why a separate `_task`, not wrapping `copier update` in a shell script:**

- The docs have always pointed users at `uvx copier update --trust --skip-answered` as the single entry point. A wrapper script (say, `./update.sh`) would either require users to learn a new invocation or create a second, inconsistent entry point. Keeping the behavior inside `copier.yml` means the existing `uvx copier update --trust --skip-answered` command keeps working unchanged, and the auto-commit is transparent.
- Tasks in `copier.yml` are versioned with the template. A wrapper script at the ADE root would be versioned with the ADE's own history and could drift from what the template expects.
- The `when: "{{ _copier_operation == 'update' }}"` clause makes scaffold vs. update behavior precisely expressible in one file.

**Why `_copier_operation == 'update'` and not `!= 'copy'`:**

Copier's documented operations are `copy` and `update`. Using an equality check is more defensive than a not-equals check in case copier adds a new operation in a future major version. A hypothetical `bootstrap` operation shouldn't auto-commit.

**Why use `git add -A` and not a curated file list:**

Copier does not expose "the set of files copier just wrote" in a way `_tasks` can consume. The only reliable signal that a path is copier-managed is "it's dirty and we got here, and copier refused to run on a dirty tree". `git add -A` captures that cleanly. A curated list would drift from `template/` over time (every new template file would need manual maintenance) and would fail silently when drift happened.

**Commit message format:** `chore: copier update to <new_commit_tag>`, e.g. `chore: copier update to v0.8.4`. Matches the convention the user was already using manually (confirmed in the v0.8.2→v0.8.3 cycle log: `chore: copier update v0.8.2 -> v0.8.3` was typed manually — the auto-commit format is the same concept). Uses `chore:` prefix so it sorts alongside other maintenance commits in conventional-commit tooling.

**Trade-offs:**

1. **Loss of per-file review opportunity.** Previously, the user could `git diff` the modified files after update and reject the whole update by `git checkout -- .` before committing. Now the update is committed immediately. Mitigation: `git revert HEAD` or `git reset HEAD^` is a one-liner if the user decides they don't want the update after all. The auto-commit is atomic and isolated, so reverting is clean.
2. **Commit-hook-heavy projects may see surprising hook runs during update.** If an ADE's repo has a pre-commit hook that takes 30 seconds to run, `copier update` now includes that cost. Acceptable — the hooks exist for a reason, and running them on copier-managed commits is consistent with running them on any other commit.
3. **First update from v0.8.3 (no auto-commit task) to v0.8.4 (with auto-commit task) still gets auto-committed.** The destination render uses the NEW template, which has the task. So v0.8.3 → v0.8.4 is self-committing. No awkward transition.
4. **The task still runs GSD install on a no-op update** (where `_commit` matches and nothing rendered differently). The GSD install is idempotent and cheap on subsequent runs, so this is accepted — a finer gate ("only run GSD if version bumped") is a possible future optimization but out of scope here. The auto-commit correctly detects nothing-to-commit in this case and does not produce a commit.

**What this replaces / relates to:**

- D-007 and D-009 describe the `_tasks` evolution for portfolio sync and GSD install. Auto-commit joins that family as a fourth update-phase task with its own gate (`when: update` + pwd).
- D-015 (pwd gate to run tasks once) is a direct prerequisite — without it, auto-commit would run in the old_copy and new_copy temp render dirs as well, polluting a non-destination directory's git state. The `when: update` clause plus the pwd gate together mean auto-commit runs exactly once per real update invocation.
- D-017 (`--skip-answered`) removes prompt friction; D-018 removes commit friction. Together they realize the "single entry point" promise of the generated README.

**Validation:** `test.sh` now asserts the full lifecycle:
- After `copier copy`: exactly one commit (`ADE scaffold`), clean tree.
- After `copier update v0.0.0 → v0.0.1` on a content-changing bump: exactly two commits (`ADE scaffold`, then `chore: copier update to v0.0.1`), clean tree.
- After a second `copier update` at v0.0.1 (no-op): still two commits, clean tree, auto-commit correctly emits `nothing to commit`.

> **Superseded by D-020 (v0.8.5):** the mechanism described above (final `_task` with `when: update` + pwd gate) was found to commit pre-merge state. See D-020 for the fix — the auto-commit is now an `_migrations` entry with `when: "{{ _stage == 'after' }}"`. The external contract (auto-commit fires at end of every successful update; same conflict-marker abort behavior; same commit-message format) is unchanged.

## D-019: `portfolio_file` is a scaffold-time seed, not an update-time sync source

**Decision:** The `_task` that seeds `ade-repos.txt` from `portfolio_file` is gated with `when: "{{ _copier_operation == 'copy' }}"`. It runs exactly once, during `copier copy`. On `copier update` the task is a no-op; `ade-repos.txt` is treated as user-owned and merged by copier's built-in 3-way merge (with template additions landing automatically where the user hasn't diverged).

**Context — what v0.8.4 got wrong:** Up through v0.8.4 the seed task was `when`-unrestricted and pwd-gated, so it ran on every `copier update` in the destination. The rendered command was literally `cp "{{ portfolio_file }}" ade-repos.txt`. Three concrete failure modes flowed from that:

1. **Update breaks when `portfolio_file` is no longer on disk.** User scaffolds with `--data portfolio_file=/tmp/my-list.txt`, deletes `/tmp/my-list.txt` later (it was a scratch file), then runs `uvx copier update`. The task fails under `set -euo pipefail` (`cp: /tmp/my-list.txt: No such file or directory`) → update aborts mid-flight → dirty tree → user cannot update and isn't told how to recover.
2. **Template additions get clobbered.** Copier's merge lands new default repos into `ade-repos.txt` during the render phase. Our seed `_task` then runs `cp "$portfolio_file" ade-repos.txt`, overwriting the merged result. Custom-portfolio users never see template additions.
3. **Local edits to `ade-repos.txt` get reverted.** Scaffolded with a `portfolio_file`, then added a personal repo by editing `ade-repos.txt` directly → next update reverts to whatever `portfolio_file` currently contains.

All three follow from treating `portfolio_file` as a live source-of-truth on update. It isn't, and the docs never framed it that way — it's a convenience for the first scaffold.

**Why copy-only is the right semantics:**

- **Scaffold:** user picks a portfolio at copy time (either via the default `template/ade-repos.txt` or by passing `--data portfolio_file=<abs-path>`). The seed task copies it in. From this point `ade-repos.txt` is the project's portfolio state, owned by the project's git repo.
- **Update:** `ade-repos.txt` is a regular template-tracked file. Copier's update applies `diff(old_template, new_template)` to the destination. New default repos in the template propagate through the merge; user's local edits are preserved by the same merge. No separate codepath needed.
- **Changing portfolios later:** edit `ade-repos.txt` directly, run `uvx copier update`, and the portfolio-sync `_task` clones anything newly listed. This was already the documented path for portfolio edits; v0.8.5 makes it the only path.

**Why not "copy on update only if the file still exists":**

We considered making the task best-effort on update (skip if source missing, copy otherwise). Rejected because failure mode #2 (clobbering template additions) persists even if source exists. Copy-only is the only option that gets all three failure modes right, and it matches how every other copier answer behaves (stored at scaffold, referenced for re-prompt suppression, not re-executed on update).

**Trade-offs:**

- **Custom-portfolio users who expected `portfolio_file` to be a live pointer lose that behavior.** Not a real regression: nobody was known to be using it that way, the behavior was never documented, and the failure mode it exhibited (silent clobber of template additions) was worse than the current "scaffold-time only" semantics. The `portfolio_file` answer remains in `.copier-answers.yml` as a historical record; it just no longer triggers a `cp`.
- **Answers file still contains a potentially stale path.** Fine. Copier treats the answer as data. It's only consulted when the scaffold task is re-evaluated, which no longer happens post-scaffold. Users who care can edit `.copier-answers.yml` to clear `portfolio_file: ""`, but there's no functional need to.

**Commit tasks around this decision:**

- `_tasks[0]` gains `when: "{{ _copier_operation == 'copy' }}"` and loses its pwd gate (copy has no temp renders; the gate was only needed because the task previously ran on update too).
- Fallback rendering: when `portfolio_file` is empty the command renders to `true`, keeping the task valid under all inputs.

**Validation:** `test.sh` now includes a scenario specifically for failure mode #1 — scaffold with `portfolio_file=<tmpfile>`, delete the tmpfile, bump the template to v0.0.2, run `copier update`. Must exit 0, `ade-repos.txt` unchanged (still custom), auto-commit fires, tree clean.

**Related decisions:**

- D-005 introduced `portfolio_file` as a scaffold input. This decision narrows its scope to match original intent.
- D-015 introduced the pwd gate for tasks 2 and 3 (portfolio sync, GSD install). Task 1 no longer needs the gate because `when: copy` eliminates the temp-render run entirely.
- D-018 / D-020: the auto-commit at end of update ensures template-merge changes to `ade-repos.txt` don't leave the tree dirty.

## D-020: Auto-commit uses `_migrations` (not `_tasks`) to run AFTER copier's diff is applied

**Decision:** The auto-commit introduced in D-018 is implemented as an `_migrations` entry with `when: "{{ _stage == 'after' }}"`, not as a final `_tasks` entry with `when: "{{ _copier_operation == 'update' }}"`. The external contract described in D-018 is unchanged (auto-commit fires after every successful update, aborts loudly on conflict markers, emits `nothing to commit` for no-op updates, commit message format is `chore: copier update to <new_commit_tag>`). Only the implementation hook changes.

**Context — the bug we hit in v0.8.5 testing:** While adding the D-019 fix (portfolio_file copy-only), the test script's existing "`copier update v0.0.0 → v0.0.1` leaves a clean tree" assertion started failing. The auto-commit ran and produced a commit with `3 files changed`, but immediately after the commit `git status` reported `M ade-repos.txt`. The `ade-repos.txt` content in the commit was 15 repos (the template default); the working-tree content after copier finished was empty (the scaffold seed). Something was reverting the file after the `_task` ran.

Reading `copier/_main.py:_apply_update()` revealed the actual update flow:

1. Render old template (v_from) into a temp directory `old_copy`.
2. Snapshot the current destination index as a git tree (`subproject_head`) — this is the user's *current, pre-update* state.
3. Run `current_worker.run_copy()` on the destination. **This is the inner copy pass**: it overwrites destination files with the new template's rendered output, and it runs all `_tasks`. Our `_tasks`-based auto-commit fires here, capturing the new-template state written to destination.
4. Render new template (v_to) into another temp directory `new_copy`.
5. Compute `diff(old_copy → subproject_head)` — this is exactly "what the user had diverged from the old template." Apply this diff to the destination via `git apply --reject`.
6. Run `migration_tasks("after", ...)` — these run post-diff-apply.

Step 5 restores the user's pre-update divergence on top of the new template. That's the 3-way-merge-semantic: template additions land where user didn't touch, user customizations survive where template didn't touch. But it runs *after* our `_tasks`-based auto-commit. In the test scenario, the user's "divergence" was `ade-repos.txt = empty` (seeded from `/dev/null`), so step 5 reverted `ade-repos.txt` back to empty after the commit captured it as the 15-repos template default. Committed state and working-tree state ended up out of sync → dirty tree with the impossibility of resolving it without rewriting the commit.

This bug was present in v0.8.4 too but *masked by v0.8.4's task 1*. In v0.8.4 task 1 (`cp /dev/null ade-repos.txt`) ran on every update, pre-reverting `ade-repos.txt` to empty *before* the auto-commit saw it — which matched the post-diff-apply state, so the commit was accidentally correct. Removing that masking (D-019) exposed the underlying bug.

**Why `_migrations` is the right hook:**

`_migrations` tasks with `_stage == "after"` run at step 6 in the flow above — after the diff from step 5 has been applied. By the time our command runs, the working tree reflects the final post-merge state that `copier update` will leave behind. Committing that state is correct: it matches what the user would see on exit.

Confirmed behavior in `copier/_main.py` and `copier/_template.py`:
- `_apply_update()` calls `migration_tasks("after", ...)` at the very end, after `apply_cmd << diff` and after `_remove_old_files`. No further mutation of the destination happens after this point.
- `_execute_tasks()` (line 353) exposes migration extra-vars to Jinja prefixed with `_`: `stage` → `_stage`, `version_from` → `_version_from`, `version_to` → `_version_to`, plus `_copier_operation`. So `{{ _version_to }}` expands to the new template ref (e.g. `v0.8.5`) — same value that would have been parsed from `.copier-answers.yml`, but available directly in the render context.
- A migration with no `version:` key fires on every update (including no-op updates where `version_from == version_to`), which matches our "commit whatever copier left dirty, or silently no-op" semantics. The no-op case is handled by the `git diff --quiet` check inside the command.

**Why the `_tasks`-based implementation was never going to be right:**

The copier documentation describes `_tasks` as running "after generation" but doesn't specify that during update, "after generation" means "after the inner copy pass, still before the final diff-apply." The distinction only matters when a task tries to commit or otherwise observe the final state. For our auto-commit, the distinction is fatal. No amount of pwd-gating or `when:` tweaking on a `_task` can move its execution point past step 5.

**Trade-offs:**

1. **`_migrations` only fires on update (not on copy).** That's the behavior we want anyway — on `copy`, the dedicated `git init && git add -A && git commit -m 'ADE scaffold'` task (D-004) handles the initial commit. No redundancy.
2. **`_migrations` doesn't participate in copier's "number of tasks" reporting alongside `_tasks`.** Cosmetic. The migration prints its own `==> [auto-commit] copier update to <ref>` banner, which is clearer than "Running task N of M" anyway.
3. **`_migrations` without a `version:` key is technically intended for per-version one-shot migrations in the copier docs, but it works on every update when the key is omitted.** We verified this behavior in `_template.py:migration_tasks()`; without a version key the `if "version" in migration` range check is skipped and the task is unconditionally appended to the result. This is stable API in copier 9.x.
4. **Commit message source changed from awk-parsing `.copier-answers.yml` to `{{ _version_to }}`.** Strictly better: avoids reading a file that copier just re-rendered, and `_version_to` is the canonical value copier itself uses.

**What this replaces / relates to:**

- D-018 described the auto-commit feature and its safety analysis. Everything in D-018 about *why* we auto-commit, *why* it's safe, and *what to do about conflict markers* still applies. Only the "final `_task` with `when: update` + pwd gate" mechanism is replaced; the pwd gate is no longer needed because `_migrations` inherently run in the destination, never in temp render dirs.
- D-015 explains copier's inner-copy pass running tasks in temp dirs. The same flow is what mis-timed the auto-commit in v0.8.4 — the pwd gate fixed the "runs 3×" symptom but not the "runs at wrong lifecycle point" root cause. `_migrations` addresses the root cause.
- D-019's "copy-only portfolio_file seed" is what surfaced this bug. Without the masking effect of that task, any `copier update` that left `ade-repos.txt` divergent from template would have shown the same tree-dirty-after-commit result.

**Validation:** `test.sh` continues to assert the full commit-count + commit-message + clean-tree lifecycle (scaffold produces 1 commit, content-changing update adds exactly 1 auto-commit with message `chore: copier update to v0.0.1`, no-op update adds 0 commits, tree clean throughout). The new D-019 scenario (scaffold with `portfolio_file`, delete source, update to v0.0.2) additionally verifies that the auto-commit message reads `chore: copier update to v0.0.2` and the tree is clean — end-to-end proof that `_version_to` resolves correctly and the post-diff state is what gets committed.

#!/usr/bin/env bash
# End-to-end test for the ade-template copier template.
#
# Exercises the recopy model (see docs/DECISIONS.md D-022, D-023, D-024):
#   - defaults scaffold + auto-commit
#   - recopy clones new repos added via template bump
#   - no-op recopy produces no new commits
#   - partial selection (some toggles / groups off)
#   - short-name DSL resolves correctly for bare / org-prefixed / full-URL inputs
#   - local edits to generated files (ade-repos.txt, workspace) are reverted on recopy
#
# Stubs `open`, `npx`, and `git clone` so the test runs offline. Tests the
# working tree, not HEAD — copies the template sans .git so uncommitted
# changes are exercised. Run before tagging any release that touches
# template/ or copier.yml.

set -euo pipefail

TEMPLATE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Stay inside /tmp (macOS /var/folders/... gets GC'd aggressively, losing
# KEEP_SCRATCH output between shell invocations).
SCRATCH="${ADE_TEST_SCRATCH:-$(mktemp -d /tmp/ade-template-test.XXXXXX)}"
# Set KEEP_SCRATCH=1 to skip cleanup for debugging.
cleanup() {
  rc=$?
  if [ "${KEEP_SCRATCH:-0}" = "1" ]; then
    echo "==> KEEP_SCRATCH=1 — leaving $SCRATCH for inspection"
  else
    # Git pack files inside scratch dirs are sometimes chmod'd to read-only
    # (macOS / some git versions). Force-open perms before rm so cleanup never
    # fails, and swallow errors so the test's true exit code survives.
    chmod -R u+w "$SCRATCH" 2>/dev/null || true
    rm -rf "$SCRATCH" 2>/dev/null || true
  fi
  exit $rc
}
trap cleanup EXIT

STUB_BIN="$SCRATCH/stub-bin"
mkdir -p "$STUB_BIN"

for cmd in open npx; do
  printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/$cmd"
  chmod +x "$STUB_BIN/$cmd"
done

# `git clone` stub: for network URLs (git@... / https://... / etc), create an
# empty git repo at the target path instead of hitting the network. Local-path
# clones (file://... or absolute paths that exist on disk) pass through to the
# real git — copier itself clones the local template via `git clone` during
# its VCS workflow, and stubbing that would leave the render dir empty.
# Other git subcommands always pass through.
REAL_GIT="$(command -v git)"
cat > "$STUB_BIN/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ "\${1:-}" = "clone" ]; then
  raw_args=("\$@")
  shift
  branch=""
  while [ "\$#" -gt 0 ]; do
    case "\$1" in
      -b|--branch) branch="\$2"; shift 2 ;;
      --) shift; break ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  url="\$1"
  dir="\${2:-\$(basename "\$url" .git)}"
  case "\$url" in
    file://*|/*)
      # Local path — pass through to real git.
      exec "$REAL_GIT" "\${raw_args[@]}"
      ;;
  esac
  if [ -e "\$url" ]; then
    # Relative local path that resolves on disk — pass through.
    exec "$REAL_GIT" "\${raw_args[@]}"
  fi
  # Network URL — simulate an empty-repo clone.
  "$REAL_GIT" init -q -b "\${branch:-main}" "\$dir"
  "$REAL_GIT" -C "\$dir" -c user.email=test@test -c user.name=test \\
    commit --allow-empty -q -m "stub: simulated clone of \$url" --no-gpg-sign
  exit 0
fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$STUB_BIN/git"
export PATH="$STUB_BIN:$PATH"

TEMPLATE_COPY="$SCRATCH/template"
mkdir -p "$TEMPLATE_COPY"
(cd "$TEMPLATE_ROOT" && tar --exclude='./.git' -cf - .) | (cd "$TEMPLATE_COPY" && tar -xf -)

# copier needs a tagged git source. Init a throwaway repo with a tag.
(
  cd "$TEMPLATE_COPY"
  "$REAL_GIT" init -q
  "$REAL_GIT" -c user.email=test@test -c user.name=test commit --allow-empty -q -m "init" --no-gpg-sign
  "$REAL_GIT" add -A
  "$REAL_GIT" -c user.email=test@test -c user.name=test commit -q -m "template" --no-gpg-sign
  "$REAL_GIT" tag v0.0.0
) >/dev/null

# ----------------------------------------------------------------------------
# Scenario 1: defaults scaffold — every toggle + group enabled, empty extras.
# ----------------------------------------------------------------------------
TEST_ADE="$SCRATCH/test-ade"

echo "==> [1/6] Scaffolding with defaults (all toggles, all groups, empty extras)..."
uvx copier copy --trust --defaults \
  --data ade_name=test-ade \
  "$TEMPLATE_COPY" "$TEST_ADE"

WS="$TEST_ADE/test-ade.code-workspace"
REPOS="$TEST_ADE/ade-repos.txt"

[ -f "$WS" ]    || { echo "FAIL: workspace file missing at $WS" >&2; exit 1; }
[ -f "$REPOS" ] || { echo "FAIL: ade-repos.txt missing at $REPOS" >&2; exit 1; }

# Full default portfolio resolves to exactly this set of URLs:
#   platform: gsd-docs, madi-parloa/agent-guardrails, madi-parloa/cursor-self-hosted-agent
#   core-infra: parloa-infra, parloa-infra-global, parloa-infra-it, parloa-infra-pre-stamp, parloa-k8s, parloa-terraform-modules
#   stamps: stamps-catalog, stamps-release-channels, crossplane-xrd
#   catalog: engineering-catalog
#   kitchens: claudes-kitchen, open-kitchen
#   template-source: madi-parloa/ade-template
# Total: 16 repos.
EXPECTED_DEFAULT_URLS=(
  "git@github.com:parloa/gsd-docs.git"
  "git@github.com:madi-parloa/agent-guardrails.git"
  "git@github.com:madi-parloa/cursor-self-hosted-agent.git"
  "git@github.com:parloa/engineering-catalog.git"
  "git@github.com:parloa/claudes-kitchen.git"
  "git@github.com:parloa/open-kitchen.git"
  "git@github.com:parloa/parloa-infra.git"
  "git@github.com:parloa/parloa-infra-global.git"
  "git@github.com:parloa/parloa-infra-it.git"
  "git@github.com:parloa/parloa-infra-pre-stamp.git"
  "git@github.com:parloa/parloa-k8s.git"
  "git@github.com:parloa/parloa-terraform-modules.git"
  "git@github.com:parloa/stamps-catalog.git"
  "git@github.com:parloa/stamps-release-channels.git"
  "git@github.com:parloa/crossplane-xrd.git"
  "git@github.com:madi-parloa/ade-template.git"
)
for url in "${EXPECTED_DEFAULT_URLS[@]}"; do
  if ! grep -qxF "$url" "$REPOS"; then
    echo "FAIL: expected '$url' in ade-repos.txt, not found" >&2
    cat "$REPOS" >&2
    exit 1
  fi
done
# Generated header is present.
if ! grep -qF 'Generated from .copier-answers.yml' "$REPOS"; then
  echo "FAIL: ade-repos.txt missing 'Generated from .copier-answers.yml' header" >&2
  exit 1
fi
echo "  ok: ade-repos.txt contains all 16 default URLs and the generated header"

# Workspace file: root first, 16 portfolio folders, sorted case-insensitive.
python3 - "$WS" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
folders = data.get("folders", [])
settings = data.get("settings", {})
problems = []
if len(folders) != 17:
    problems.append(f"expected 17 folders (16 portfolio + ADE root), got {len(folders)}")
if settings.get("git.autoRepositoryDetection") is not False:
    problems.append("git.autoRepositoryDetection should be False")
if settings.get("git.openRepositoryInParentFolders") != "never":
    problems.append("git.openRepositoryInParentFolders should be 'never'")
if settings.get("files.exclude", {}).get("**/.DS_Store") is not True:
    problems.append("settings.files.exclude should hide **/.DS_Store")
if folders and folders[0].get("path") != ".":
    problems.append(f"first folder should be ADE root at path '.', got {folders[0]!r}")
if folders and folders[0].get("name") != "test-ade (root)":
    problems.append(f"first folder name should be 'test-ade (root)', got {folders[0].get('name')!r}")
portfolio_names = [f.get("name") for f in folders[1:]]
expected_sorted = sorted(portfolio_names, key=lambda s: s.lower())
if portfolio_names != expected_sorted:
    problems.append(
        "portfolio folders not case-insensitive sorted\n"
        f"    got:      {portfolio_names}\n    expected: {expected_sorted}"
    )
if problems:
    print("FAIL:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)
print(f"  ok: workspace file has {len(folders)} folders, root-first, alpha-sorted")
PY

echo "==> Verifying scaffold commit state..."
cd "$TEST_ADE"
[ -d .git ] || { echo "FAIL: .git missing" >&2; exit 1; }
commit_count="$("$REAL_GIT" rev-list --count HEAD)"
if [ "$commit_count" -ne 1 ]; then
  echo "FAIL: expected 1 commit after copy, got $commit_count" >&2
  "$REAL_GIT" log --oneline >&2
  exit 1
fi
if [ "$("$REAL_GIT" log -1 --pretty=%s)" != "ADE scaffold" ]; then
  echo "FAIL: expected 'ADE scaffold' commit, got '$("$REAL_GIT" log -1 --pretty=%s)'" >&2
  exit 1
fi
if ! "$REAL_GIT" diff --quiet || ! "$REAL_GIT" diff --cached --quiet; then
  echo "FAIL: tree dirty after scaffold" >&2
  "$REAL_GIT" status --short >&2
  exit 1
fi
echo "  ok: 1 'ADE scaffold' commit, clean tree"

# ----------------------------------------------------------------------------
# Scenario 2: recopy picks up a new repo added to a group in the template bump.
# ----------------------------------------------------------------------------
echo ""
echo "==> [2/6] Template bump adds a repo to core-infra; recopy must pick it up..."
(
  cd "$TEMPLATE_COPY"
  python3 - <<'PY'
from pathlib import Path
p = Path("_portfolio.jinja")
text = p.read_text()
# Insert 'parloa-infra-newthing' into the core-infra group block.
old = "parloa-k8s\nparloa-terraform-modules\n{%- elif group == 'stamps' -%}"
new = "parloa-k8s\nparloa-newthing\nparloa-terraform-modules\n{%- elif group == 'stamps' -%}"
assert old in text, "could not find core-infra insertion point in _portfolio.jinja"
p.write_text(text.replace(old, new))
PY
  "$REAL_GIT" -c user.email=test@test -c user.name=test commit -aq -m "add parloa-newthing" --no-gpg-sign
  "$REAL_GIT" tag v0.0.1
) >/dev/null

cd "$TEST_ADE"
uvx copier recopy --trust --skip-answered --overwrite --defaults

if ! grep -qxF "git@github.com:parloa/parloa-newthing.git" "$REPOS"; then
  echo "FAIL: recopy did not pick up parloa-newthing in ade-repos.txt" >&2
  cat "$REPOS" >&2
  exit 1
fi

commit_count="$("$REAL_GIT" rev-list --count HEAD)"
if [ "$commit_count" -ne 2 ]; then
  echo "FAIL: expected 2 commits (scaffold + auto-commit), got $commit_count" >&2
  "$REAL_GIT" log --oneline >&2
  exit 1
fi
last_msg="$("$REAL_GIT" log -1 --pretty=%s)"
if [[ "$last_msg" != chore:\ copier\ recopy\ to\ * ]]; then
  echo "FAIL: expected 'chore: copier recopy to <hash>', got '$last_msg'" >&2
  exit 1
fi
if ! "$REAL_GIT" diff --quiet || ! "$REAL_GIT" diff --cached --quiet; then
  echo "FAIL: tree dirty after recopy" >&2
  "$REAL_GIT" status --short >&2
  exit 1
fi
if [ ! -d parloa-newthing/.git ]; then
  echo "FAIL: new repo parloa-newthing/ was not cloned by recopy" >&2
  exit 1
fi
echo "  ok: recopy cloned parloa-newthing/, updated ade-repos.txt, auto-committed ($last_msg), clean tree"

# ----------------------------------------------------------------------------
# Scenario 3: no-op recopy — template unchanged, recopy must add 0 commits.
# ----------------------------------------------------------------------------
echo ""
echo "==> [3/6] Re-running recopy at the same version must be a no-op..."
uvx copier recopy --trust --skip-answered --overwrite --defaults
commit_count_after="$("$REAL_GIT" rev-list --count HEAD)"
if [ "$commit_count_after" -ne 2 ]; then
  echo "FAIL: no-op recopy produced a new commit ($commit_count_after commits total)" >&2
  "$REAL_GIT" log --oneline >&2
  exit 1
fi
if ! "$REAL_GIT" diff --quiet || ! "$REAL_GIT" diff --cached --quiet; then
  echo "FAIL: tree dirty after no-op recopy" >&2
  "$REAL_GIT" status --short >&2
  exit 1
fi
echo "  ok: no-op recopy produced 0 new commits, clean tree"

# ----------------------------------------------------------------------------
# Scenario 4: template wins — local edits to generated files are reverted.
# ----------------------------------------------------------------------------
echo ""
echo "==> [4/6] Local edits to ade-repos.txt must be reverted on recopy (D-022)..."
# Commit a local edit so we can tell whether recopy reverts it.
echo "git@github.com:bogus/injected.git" >> "$REPOS"
"$REAL_GIT" -c user.email=test@test -c user.name=test commit -aq -m "local: inject bogus repo" --no-gpg-sign

# Sanity check: edit is present now.
if ! grep -qxF "git@github.com:bogus/injected.git" "$REPOS"; then
  echo "FAIL: pre-recopy sanity check — local edit not present" >&2
  exit 1
fi

uvx copier recopy --trust --skip-answered --overwrite --defaults

if grep -qxF "git@github.com:bogus/injected.git" "$REPOS"; then
  echo "FAIL: local edit to ade-repos.txt survived recopy (template did not win)" >&2
  cat "$REPOS" >&2
  exit 1
fi
if ! "$REAL_GIT" diff --quiet || ! "$REAL_GIT" diff --cached --quiet; then
  echo "FAIL: tree dirty after 'template wins' recopy" >&2
  "$REAL_GIT" status --short >&2
  exit 1
fi
echo "  ok: local edit reverted, tree clean"

# ----------------------------------------------------------------------------
# Scenario 5: partial selection — a subset of groups/toggles.
# ----------------------------------------------------------------------------
echo ""
echo "==> [5/6] Partial selection (core-infra only, no gsd-docs, no guardrails)..."
TEST_ADE_PARTIAL="$SCRATCH/test-partial"
uvx copier copy --trust --defaults \
  --data ade_name=test-partial \
  --data include_gsd_docs=false \
  --data include_agent_guardrails=false \
  --data include_cursor_self_hosted_agent=false \
  --data 'portfolio_groups=["core-infra"]' \
  "$TEMPLATE_COPY" "$TEST_ADE_PARTIAL"

PREPOS="$TEST_ADE_PARTIAL/ade-repos.txt"
EXPECTED_PARTIAL_URLS=(
  "git@github.com:parloa/parloa-infra.git"
  "git@github.com:parloa/parloa-infra-global.git"
  "git@github.com:parloa/parloa-infra-it.git"
  "git@github.com:parloa/parloa-infra-pre-stamp.git"
  "git@github.com:parloa/parloa-k8s.git"
  "git@github.com:parloa/parloa-newthing.git"
  "git@github.com:parloa/parloa-terraform-modules.git"
)
NOT_EXPECTED=(
  "git@github.com:parloa/gsd-docs.git"
  "git@github.com:madi-parloa/agent-guardrails.git"
  "git@github.com:madi-parloa/cursor-self-hosted-agent.git"
  "git@github.com:parloa/stamps-catalog.git"
  "git@github.com:parloa/claudes-kitchen.git"
  "git@github.com:parloa/engineering-catalog.git"
  "git@github.com:madi-parloa/ade-template.git"
)
for url in "${EXPECTED_PARTIAL_URLS[@]}"; do
  if ! grep -qxF "$url" "$PREPOS"; then
    echo "FAIL: partial selection missing expected URL: $url" >&2
    cat "$PREPOS" >&2
    exit 1
  fi
done
for url in "${NOT_EXPECTED[@]}"; do
  if grep -qxF "$url" "$PREPOS"; then
    echo "FAIL: partial selection leaked excluded URL: $url" >&2
    cat "$PREPOS" >&2
    exit 1
  fi
done
# AGENTS.md / CLAUDE.md / README.md must have no gsd-docs content.
for f in AGENTS.md CLAUDE.md README.md; do
  if grep -qF gsd-docs "$TEST_ADE_PARTIAL/$f"; then
    echo "FAIL: $f mentions gsd-docs despite include_gsd_docs=false" >&2
    grep -n gsd-docs "$TEST_ADE_PARTIAL/$f" >&2
    exit 1
  fi
done
# .planning/ must be a real directory when gsd-docs is disabled.
if [ -L "$TEST_ADE_PARTIAL/.planning" ]; then
  echo "FAIL: .planning is a symlink with include_gsd_docs=false" >&2
  exit 1
fi
echo "  ok: partial selection portfolio correct, gsd-docs content omitted, .planning/ local"

# ----------------------------------------------------------------------------
# Scenario 6: short-name DSL in extra_repos resolves all three shapes.
# ----------------------------------------------------------------------------
echo ""
echo "==> [6/6] Short-name DSL in extra_repos resolves correctly (D-024)..."
TEST_ADE_DSL="$SCRATCH/test-dsl"
EXTRA_REPOS_INPUT=$'thing\nmadi-parloa/other-thing\ngit@github.com:foo/bar.git\n# comment — ignored\n\nparloa/parloa-newthing'
uvx copier copy --trust --defaults \
  --data ade_name=test-dsl \
  --data 'portfolio_groups=[]' \
  --data include_gsd_docs=false \
  --data include_agent_guardrails=false \
  --data include_cursor_self_hosted_agent=false \
  --data "extra_repos=$EXTRA_REPOS_INPUT" \
  "$TEMPLATE_COPY" "$TEST_ADE_DSL"

DREPOS="$TEST_ADE_DSL/ade-repos.txt"

# Assert exact set: bare → parloa/; org/repo → that org; full URL → pass-through;
# comment/blank → dropped; 'parloa/parloa-newthing' resolves identically to bare
# 'parloa-newthing' (which isn't in this list, so we only see one entry).
assertions=(
  "git@github.com:parloa/thing.git"
  "git@github.com:madi-parloa/other-thing.git"
  "git@github.com:foo/bar.git"
  "git@github.com:parloa/parloa-newthing.git"
)
for url in "${assertions[@]}"; do
  if ! grep -qxF "$url" "$DREPOS"; then
    echo "FAIL: DSL resolution missing expected URL: $url" >&2
    cat "$DREPOS" >&2
    exit 1
  fi
done
# Comment and blank lines must not produce spurious URLs.
non_comment_line_count="$(grep -Ev '^\s*(#|$)' "$DREPOS" | wc -l | tr -d ' ')"
if [ "$non_comment_line_count" -ne 4 ]; then
  echo "FAIL: expected 4 resolved URLs in extra_repos DSL test, got $non_comment_line_count" >&2
  cat "$DREPOS" >&2
  exit 1
fi

# Resolver correctness (D-024): 'parloa-infra' (not in this test, just verifying
# the rule) would resolve identically to 'parloa/parloa-infra'. Verify on the
# test-ade defaults instead, which has 'parloa-infra' as part of core-infra.
if ! grep -qxF "git@github.com:parloa/parloa-infra.git" "$REPOS"; then
  echo "FAIL: bare 'parloa-infra' did not resolve to parloa/ org" >&2
  exit 1
fi
# madi-parloa/agent-guardrails must NOT have been rewritten under parloa/.
if grep -qxF "git@github.com:parloa/agent-guardrails.git" "$REPOS"; then
  echo "FAIL: madi-parloa/agent-guardrails was incorrectly rewritten under parloa/" >&2
  exit 1
fi

# Workspace file folders for the DSL test: thing, other-thing, bar, parloa-newthing.
python3 - "$TEST_ADE_DSL/test-dsl.code-workspace" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
folders = {f["path"]: f["name"] for f in data["folders"]}
expected = {".", "thing", "other-thing", "bar", "parloa-newthing"}
actual = set(folders.keys())
if actual != expected:
    print(f"FAIL: workspace folders mismatch\n  got:      {sorted(actual)}\n  expected: {sorted(expected)}", file=sys.stderr)
    sys.exit(1)
print("  ok: workspace folders for DSL shapes are correct")
PY

echo "  ok: bare/org-prefixed/full-URL all resolve; comments/blanks ignored"

echo ""
echo "==> All scenarios passed"

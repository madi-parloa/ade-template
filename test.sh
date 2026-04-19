#!/usr/bin/env bash
# End-to-end test for the ade-template copier template.
#
# Runs `copier copy` with stubbed `open` and `npx` (so Cursor doesn't launch
# and GSD doesn't install) and validates the rendered workspace file. Tests
# the working tree, not HEAD — copies the template sans .git so uncommitted
# changes are exercised.
#
# Run before tagging any release that touches template/ or copier.yml.

set -euo pipefail

TEMPLATE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRATCH="$(mktemp -d -t ade-template-test.XXXXXX)"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

STUB_BIN="$SCRATCH/stub-bin"
mkdir -p "$STUB_BIN"
for cmd in open npx; do
  printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/$cmd"
  chmod +x "$STUB_BIN/$cmd"
done
export PATH="$STUB_BIN:$PATH"

TEMPLATE_COPY="$SCRATCH/template"
mkdir -p "$TEMPLATE_COPY"
(cd "$TEMPLATE_ROOT" && tar --exclude='./.git' -cf - .) | (cd "$TEMPLATE_COPY" && tar -xf -)

# copier needs a tagged git source to support `copier update`. Init a throwaway
# repo with a tag so the update path can be exercised.
(
  cd "$TEMPLATE_COPY"
  git init -q
  git -c user.email=test@test -c user.name=test commit --allow-empty -q -m "init" --no-gpg-sign
  git add -A
  git -c user.email=test@test -c user.name=test commit -q -m "template" --no-gpg-sign
  git tag v0.0.0
) >/dev/null

TEST_ADE="$SCRATCH/test-ade"

echo "==> Running copier copy (ade_name=test-ade, portfolio_file=/dev/null)..."
uvx copier copy --trust --defaults \
  --data ade_name=test-ade \
  --data portfolio_file=/dev/null \
  "$TEMPLATE_COPY" "$TEST_ADE"

WS="$TEST_ADE/test-ade.code-workspace"

echo "==> Validating rendered workspace file..."
[ -f "$WS" ] || { echo "FAIL: workspace file missing at $WS" >&2; exit 1; }

python3 - "$WS" <<'PY'
import json
import sys

ws_path = sys.argv[1]
with open(ws_path) as f:
    data = json.load(f)

folders = data.get("folders", [])
settings = data.get("settings", {})
problems = []

if len(folders) != 16:
    problems.append(f"expected 16 folders (15 portfolio + ADE root), got {len(folders)}")
if settings.get("git.autoRepositoryDetection") is not False:
    problems.append(
        f"git.autoRepositoryDetection should be False, "
        f"got {settings.get('git.autoRepositoryDetection')!r}"
    )
if settings.get("git.openRepositoryInParentFolders") != "never":
    problems.append(
        f"git.openRepositoryInParentFolders should be 'never', "
        f"got {settings.get('git.openRepositoryInParentFolders')!r}"
    )
if settings.get("files.exclude", {}).get("**/.DS_Store") is not True:
    problems.append("settings.files.exclude should hide **/.DS_Store")
for i, f in enumerate(folders):
    if not isinstance(f, dict) or "name" not in f or "path" not in f:
        problems.append(f"malformed folder entry at index {i}: {f!r}")
# Per D-016: ADE root is first, portfolio repos follow in case-insensitive alphabetical order.
if folders and folders[0].get("path") != ".":
    problems.append(
        f"first folder should be the ADE root at path '.', "
        f"got {folders[0] if folders else None!r}"
    )
if folders and folders[0].get("name") != "test-ade (root)":
    problems.append(
        f"first folder name should be 'test-ade (root)' "
        f"(templated from ade_name), got {folders[0].get('name')!r}"
    )
portfolio_names = [f.get("name") for f in folders[1:]]
expected_sorted = sorted(portfolio_names, key=lambda s: s.lower())
if portfolio_names != expected_sorted:
    problems.append(
        "portfolio folders are not case-insensitive sorted:\n"
        f"    got:      {portfolio_names}\n"
        f"    expected: {expected_sorted}"
    )

if problems:
    print("FAIL:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)

print(f"  ok: {len(folders)} folders, managed settings correct")
PY

echo ""
echo "==> Verifying copier copy created exactly one 'ADE scaffold' commit (D-018 baseline)..."
cd "$TEST_ADE"
[ -d .git ] || { echo "FAIL: .git missing in $TEST_ADE" >&2; exit 1; }
commit_count="$(git rev-list --count HEAD)"
if [ "$commit_count" -ne 1 ]; then
  echo "FAIL: expected 1 commit after copy, got $commit_count" >&2
  git log --oneline >&2
  exit 1
fi
latest_msg="$(git log -1 --pretty=%s)"
if [ "$latest_msg" != "ADE scaffold" ]; then
  echo "FAIL: expected 'ADE scaffold' commit, got '$latest_msg'" >&2
  exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "FAIL: tree dirty immediately after copy" >&2
  git status --short >&2
  exit 1
fi
echo "  ok: 1 'ADE scaffold' commit, clean tree"

echo ""
echo "==> Bumping template to v0.0.1 (forces content delta on next update)..."
(
  cd "$TEMPLATE_COPY"
  # Harmless append to a rendered file so the ADE's README.md changes on update.
  printf '\n<!-- template bump v0.0.1 -->\n' >> template/README.md.jinja
  git -c user.email=test@test -c user.name=test commit -aq -m "bump" --no-gpg-sign
  git tag v0.0.1
) >/dev/null

echo ""
echo "==> Running copier update v0.0.0 -> v0.0.1 (must auto-commit per D-018)..."
cd "$TEST_ADE"
uvx copier update --trust --defaults
[ -f "$WS" ] || { echo "FAIL: workspace file missing after update" >&2; exit 1; }

echo "==> Verifying auto-commit fired and tree is clean..."
commit_count="$(git rev-list --count HEAD)"
if [ "$commit_count" -ne 2 ]; then
  echo "FAIL: expected 2 commits after update (scaffold + auto-commit), got $commit_count" >&2
  git log --oneline >&2
  exit 1
fi
latest_msg="$(git log -1 --pretty=%s)"
expected_msg="chore: copier update to v0.0.1"
if [ "$latest_msg" != "$expected_msg" ]; then
  echo "FAIL: expected commit message '$expected_msg', got '$latest_msg'" >&2
  git log --oneline >&2
  exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "FAIL: tree dirty after auto-commit — auto-commit is broken" >&2
  git status --short >&2
  exit 1
fi
echo "  ok: auto-commit landed ('$expected_msg'), tree clean"

echo ""
echo "==> Running copier update again at v0.0.1 (must be a no-op; no new commit)..."
uvx copier update --trust --defaults
commit_count_after="$(git rev-list --count HEAD)"
if [ "$commit_count_after" -ne 2 ]; then
  echo "FAIL: no-op update created a new commit (idempotency broken): $commit_count_after" >&2
  git log --oneline >&2
  exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "FAIL: tree dirty after no-op update" >&2
  git status --short >&2
  exit 1
fi
echo "  ok: no-op update created 0 new commits, tree clean"

python3 -c "
import json
with open('$WS') as f:
    data = json.load(f)
assert len(data['folders']) == 16, 'folders count wrong after update'
print('  ok: update preserved 16 folders')
"

echo ""
echo "==> All tests passed"

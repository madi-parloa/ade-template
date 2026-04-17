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
if folders and folders[-1].get("path") != ".":
    problems.append(
        f"last folder should be the ADE root at path '.', "
        f"got {folders[-1] if folders else None!r}"
    )
if folders and folders[-1].get("name") != "test-ade (root)":
    problems.append(
        f"last folder name should be 'test-ade (root)' "
        f"(templated from ade_name), got {folders[-1].get('name')!r}"
    )

if problems:
    print("FAIL:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)

print(f"  ok: {len(folders)} folders, managed settings correct")
PY

echo ""
echo "==> Running copier update (no-op; exercises the double-render path)..."
cd "$TEST_ADE"
uvx copier update --trust --defaults
[ -f "$WS" ] || { echo "FAIL: workspace file missing after update" >&2; exit 1; }
python3 -c "
import json
with open('$WS') as f:
    data = json.load(f)
assert len(data['folders']) == 16, 'folders count wrong after update'
print('  ok: update preserved 16 folders')
"

echo ""
echo "==> All tests passed"

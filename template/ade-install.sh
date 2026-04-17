#!/usr/bin/env bash
set -euo pipefail

CLONE_FAILURES=0

if [ ! -f ade-repos.txt ]; then
  echo "==> ERROR: ade-repos.txt not found. Nothing to clone."
  exit 1
fi

echo "==> Syncing portfolio repos..."
while read -r url; do
  dir="$(basename "$url" .git)"
  if [ -d "$dir" ]; then
    echo "    $dir/ exists, pulling latest..."
    git -C "$dir" pull --ff-only 2>/dev/null || echo "    WARNING: pull failed for $dir (may have local changes)"
  else
    echo "    cloning $dir..."
    if ! git clone "$url" "$dir"; then
      echo "    WARNING: failed to clone $url (check access rights)"
      CLONE_FAILURES=$((CLONE_FAILURES + 1))
    fi
  fi
done < <(grep -Ev '^\s*(#|$)' ade-repos.txt)

if [ "$CLONE_FAILURES" -gt 0 ]; then
  echo "    $CLONE_FAILURES repo(s) failed to clone — continuing with the rest"
fi

echo "==> Generating Cursor workspace file..."
WORKSPACE_FILE="$(basename "$(pwd)").code-workspace"
python3 - "$WORKSPACE_FILE" <<'PY'
import json
import os
import sys

workspace_file = sys.argv[1]

portfolio_folders = []
portfolio_paths = set()
with open("ade-repos.txt") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name = os.path.basename(line)
        if name.endswith(".git"):
            name = name[:-4]
        if os.path.isdir(name):
            portfolio_folders.append({"name": name, "path": name})
            portfolio_paths.add(name)

managed_settings = {
    "git.autoRepositoryDetection": False,
    "git.openRepositoryInParentFolders": "never",
}

existing = {}
if os.path.exists(workspace_file):
    try:
        with open(workspace_file) as f:
            existing = json.load(f)
        if not isinstance(existing, dict):
            existing = {}
    except (json.JSONDecodeError, OSError):
        existing = {}

preserved_folders = [
    f for f in existing.get("folders", [])
    if isinstance(f, dict) and f.get("path") not in portfolio_paths
]

workspace = dict(existing)
workspace["folders"] = portfolio_folders + preserved_folders

merged_settings = dict(existing.get("settings") or {})
merged_settings.update(managed_settings)
workspace["settings"] = merged_settings

tmp = workspace_file + ".tmp"
with open(tmp, "w") as f:
    json.dump(workspace, f, indent=2)
    f.write("\n")
os.replace(tmp, workspace_file)

extra = len(preserved_folders)
msg = f"    wrote {workspace_file} with {len(portfolio_folders)} portfolio folders"
if extra:
    msg += f" (+ {extra} preserved non-portfolio root{'s' if extra != 1 else ''})"
print(msg)
PY

echo "==> Installing GSD workspace-locally..."
npx -y get-shit-done-cc@latest --local --cursor

echo "==> Running kitchen setup scripts..."
echo "    (kitchen scripts that prompt for input may need to be run manually afterwards)"
if [ -d claudes-kitchen ]; then
  echo "    setting up claudes-kitchen..."
  bash claudes-kitchen/setup-cooking-environment.sh </dev/null || {
    echo "    WARNING: claudes-kitchen setup exited non-zero (may need interactive setup later)"
  }
fi

if [ -f open-kitchen/setup-cargo-jfrog.sh ]; then
  echo "    setting up open-kitchen..."
  bash open-kitchen/setup-cargo-jfrog.sh </dev/null || {
    echo "    WARNING: open-kitchen setup exited non-zero (may need interactive setup later)"
  }
fi

echo "==> ADE install complete."

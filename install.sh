#!/usr/bin/env bash
set -euo pipefail

CLONE_FAILURES=0

echo "==> Cloning portfolio repos..."
while read -r url; do
  dir="$(basename "$url" .git)"
  if [ -d "$dir" ]; then
    echo "    $dir/ already exists, skipping"
  else
    echo "    cloning $dir..."
    if ! git clone "$url" "$dir"; then
      echo "    WARNING: failed to clone $url (check access rights)"
      CLONE_FAILURES=$((CLONE_FAILURES + 1))
    fi
  fi
done < <(grep -Ev '^\s*(#|$)' portfolio.txt)

if [ "$CLONE_FAILURES" -gt 0 ]; then
  echo "    $CLONE_FAILURES repo(s) failed to clone — continuing with the rest"
fi

echo "==> Installing GSD workspace-locally..."
npx -y get-shit-done-cc@latest

echo "==> Running kitchen setup scripts..."
if [ -d claudes-kitchen ]; then
  echo "    setting up claudes-kitchen..."
  bash claudes-kitchen/setup-cooking-environment.sh
fi

if [ -d open-kitchen ]; then
  echo "    setting up open-kitchen..."
  bash open-kitchen/scripts/install.sh
fi

echo "==> ADE setup complete. Open this directory in Cursor: cursor ."

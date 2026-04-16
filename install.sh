#!/usr/bin/env bash
set -euo pipefail

echo "==> Cloning portfolio repos..."
grep -Ev '^\s*(#|$)' portfolio.txt \
  | while read -r url; do
      dir="$(basename "$url" .git)"
      if [ -d "$dir" ]; then
        echo "    $dir/ already exists, skipping"
      else
        echo "    cloning $dir..."
        git clone "$url" "$dir"
      fi
    done

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

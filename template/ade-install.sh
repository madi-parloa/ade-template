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
done < <(grep -Ev '^\s*(#|$)' ade-repos.txt)

if [ "$CLONE_FAILURES" -gt 0 ]; then
  echo "    $CLONE_FAILURES repo(s) failed to clone — continuing with the rest"
fi

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

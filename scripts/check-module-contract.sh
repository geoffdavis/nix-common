#!/usr/bin/env bash
# check-module-contract.sh — structural guardrail for nix-common's shared
# modules. This is the machine-checkable half of the "module contract" that
# agents (and humans) must follow when adding a shared module.
#
# It asserts the two-way contract between the modules/ tree and flake.nix:
#
#   1. Every module file is referenced (exported) from flake.nix.
#   2. Every ./modules/... path referenced in flake.nix exists on disk.
#
# modules/shared/ holds internal helpers that other modules import directly
# (not flake outputs), so it is exempt from rule 1. A file belongs under
# modules/shared/ precisely when it is NOT meant to be a flake output.
#
# Run via: `task contract`, the pre-commit hook, or CI (no nix required).
set -eu

# Resolve repo root from this script's location so it works from any CWD
# and under `git worktree` (where invocation paths vary).
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

if [ ! -f flake.nix ]; then
  echo "check-module-contract: flake.nix not found in $root" >&2
  exit 1
fi

fail=0

# All ./modules/<...>.nix paths referenced anywhere in flake.nix. Covers both
# `homeModules.x = ./modules/...;` and `import ./modules/... inputs` forms.
refs=$(grep -oE '\./modules/[A-Za-z0-9/_.-]+\.nix' flake.nix | sort -u)

# Rule 2: referenced paths must exist.
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  if [ ! -f "${ref#./}" ]; then
    echo "::error::flake.nix references a module that does not exist: $ref"
    fail=1
  fi
done <<EOF
$refs
EOF

# Rule 1: every module file (outside modules/shared/) must be referenced.
while IFS= read -r f; do
  case "$f" in
    modules/shared/*) continue ;;
  esac
  if ! printf '%s\n' "$refs" | grep -qxF "./$f"; then
    echo "::error::module file is not exported from flake.nix: $f"
    echo "  -> add an export (e.g. homeModules.<name> = ./$f;) or, if it is an"
    echo "     internal helper imported by another module, move it to modules/shared/."
    fail=1
  fi
done <<EOF
$(find modules -type f -name '*.nix' | sort)
EOF

if [ "$fail" -ne 0 ]; then
  echo "module contract check FAILED" >&2
  exit 1
fi

count=$(printf '%s\n' "$refs" | grep -c .)
echo "module contract OK: $count module reference(s) in flake.nix, all consistent with modules/."

# scripts/sync-pin.sh — rewrite this repo's `uses:` pins on nix-common
# reusable workflows so they match the nix-common rev in ./flake.lock.
#
# Run from a CONSUMER repo root, right after `nix flake update nix-common`:
#
#     nix run github:geoffdavis/nix-common#sync-pin
#
# With no arguments it walks every workflow in .github/workflows/. Pass
# explicit paths to narrow it.
#
# SCOPE, deliberately narrow in two directions:
#
#   1. Only `uses:` lines are rewritten, so a pin quoted in a comment as
#      documentation (nix-common's own lint.yml header does this) is left
#      alone. The previous version matched anywhere on the line.
#
#   2. Only refs that are ALREADY a commit SHA, or the
#      REPLACE_WITH_NIX_COMMON_SHA bootstrap placeholder, are rewritten. A
#      floating `@main` / `@v1` ref is reported but NOT changed: whether a
#      given ref should float is a policy question, and a pin-sync tool has
#      no business answering it silently. `--report-only` lists them and
#      changes nothing; `--check` does the same but exits non-zero when a
#      pin disagrees with flake.lock, which is what a verify-pin CI job wants.
#
# History: this used to hardcode `lint\.yml` and only ever read ci.yml, so it
# could not maintain any other reusable-workflow pin — and pointed at a file
# with no lint.yml pin it failed its own post-sed verification and exited 1.

readonly WF_PREFIX='geoffdavis/nix-common/\.github/workflows'
readonly PLACEHOLDER='REPLACE_WITH_NIX_COMMON_SHA'
# A `uses:` line pinning a nix-common reusable workflow, ref captured.
readonly USES_RE="^[[:space:]]*uses:[[:space:]]*${WF_PREFIX}/[A-Za-z0-9._-]+\.ya?ml@"

report_only=0
check_only=0
case "${1:-}" in
--report-only)
  report_only=1
  shift
  ;;
--check)
  # Same detection, no writes, non-zero exit if anything is out of sync.
  # This is what a consumer's verify-pin CI job should call, so the check
  # and the fix can never disagree about what "in sync" means.
  check_only=1
  report_only=1
  shift
  ;;
--help | -h)
  echo "usage: sync-pin [--check | --report-only] [workflow-file...]"
  exit 0
  ;;
esac

if [ ! -f flake.lock ]; then
  echo "sync-pin: flake.lock not found in $PWD (run from the consumer repo root)" >&2
  exit 1
fi

sha=$(jq -r '.nodes."nix-common".locked.rev // empty' flake.lock)
if [ -z "$sha" ]; then
  echo "sync-pin: could not read nix-common rev from flake.lock" >&2
  exit 1
fi

files=()
if [ "$#" -gt 0 ]; then
  files=("$@")
else
  if [ ! -d .github/workflows ]; then
    echo "sync-pin: no .github/workflows directory in $PWD" >&2
    exit 1
  fi
  while IFS= read -r f; do
    files+=("$f")
  done < <(find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "sync-pin: no workflow files to inspect" >&2
  exit 1
fi

changed=0
floating=0

for f in "${files[@]}"; do
  if [ ! -f "$f" ]; then
    echo "sync-pin: workflow file not found: $f" >&2
    exit 1
  fi

  tmp=$(mktemp "${TMPDIR:-/tmp}/sync-pin.XXXXXXXX")
  # '#' as the s/// delimiter, NOT '|': the pattern carries an alternation,
  # and sed splits on the delimiter before it ever parses the regex.
  sed -E "s#(${USES_RE%@})@([0-9a-fA-F]{7,}|${PLACEHOLDER})(.*)\$#\1@${sha}\3#" "$f" >"$tmp"
  if cmp -s "$f" "$tmp"; then
    rm -f "$tmp"
  elif [ "$check_only" -eq 1 ]; then
    rm -f "$tmp"
    echo "sync-pin: OUT OF SYNC — $f does not match flake.lock ($sha)" >&2
    changed=$((changed + 1))
  elif [ "$report_only" -eq 1 ]; then
    rm -f "$tmp"
    echo "sync-pin: would update $f"
    changed=$((changed + 1))
  else
    # Write through the existing file rather than mv, so its mode survives
    # (mktemp creates 0600).
    cat "$tmp" >"$f"
    rm -f "$tmp"
    echo "sync-pin: updated $f"
    changed=$((changed + 1))
  fi

  # Anything still pinned to something other than $sha after the rewrite is
  # either a deliberately floating ref or a rev this tool declined to touch.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    echo "sync-pin: NOT pinned to flake.lock — $f:$line"
    floating=$((floating + 1))
  done < <(grep -nE "$USES_RE" "$f" | grep -vE "@${sha}([^0-9a-fA-F]|$)" || true)
done

# Post-condition, WRITE MODE ONLY: after rewriting, no SHA-shaped pin may
# still disagree with flake.lock — that would mean the rewrite silently
# missed one, which is precisely the drift this tool exists to prevent. In
# read-only modes a disagreement is the expected finding, not a fault, so it
# is reported through $changed instead.
if [ "$report_only" -eq 0 ]; then
  stale=0
  for f in "${files[@]}"; do
    if grep -qE "${USES_RE}[0-9a-fA-F]{7,}" "$f" &&
      grep -E "${USES_RE}[0-9a-fA-F]{7,}" "$f" | grep -qvE "@${sha}([^0-9a-fA-F]|$)"; then
      echo "sync-pin: stale SHA pin remains in $f" >&2
      stale=1
    fi
  done
  [ "$stale" -eq 0 ] || exit 1
fi

if [ "$floating" -gt 0 ]; then
  echo "sync-pin: $floating floating ref(s) left unchanged (see above)"
fi

if [ "$check_only" -eq 1 ]; then
  if [ "$changed" -gt 0 ]; then
    echo "sync-pin: $changed file(s) out of sync with flake.lock ($sha) — run sync-pin" >&2
    exit 1
  fi
  echo "sync-pin: all pins match flake.lock ($sha)"
elif [ "$report_only" -eq 1 ]; then
  echo "sync-pin: report-only; nix-common rev is $sha ($changed file(s) would change)"
elif [ "$changed" -eq 0 ]; then
  echo "sync-pin: already in sync at $sha"
else
  echo "sync-pin: $changed file(s) -> $sha"
fi

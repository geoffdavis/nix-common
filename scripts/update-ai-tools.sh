#!/usr/bin/env bash
# scripts/update-ai-tools.sh — fetch latest versions and update ai-tools.nix
#
# Queries the GitHub API for the newest releases of github-copilot-cli and
# claude-code, downloads all platform variants to compute SRI hashes, then
# patches the version pins in modules/home/ai-tools.nix in-place.
#
# Usage:
#   ./scripts/update-ai-tools.sh
#   task update:ai-tools
#
# Requires: curl, openssl, python3 (for JSON parsing)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODULE="${REPO_ROOT}/modules/home/ai-tools.nix"

# ── helpers ──────────────────────────────────────────────────────────────────

latest_gh_release() {
  local repo="$1"
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
    "https://api.github.com/repos/${repo}/releases/latest" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'].lstrip('v'))"
}

# Download URL to a temp file, print the SRI sha256 (sha256-<base64>), clean up.
fetch_sri() {
  local url="$1"
  local tmp
  tmp="$(mktemp)"
  curl -fsSL "$url" -o "$tmp"
  local b64
  b64="$(openssl dgst -sha256 -binary "$tmp" | openssl base64 -A)"
  rm -f "$tmp"
  printf "sha256-%s" "$b64"
}

# Replace the value on the line that carries the given marker comment.
# Line format in ai-tools.nix:
#   varName = "old-value"; # update-ai-tools: marker
update_nix_var() {
  local name="$1" value="$2"
  # Escape / in value for sed (hashes contain +, = which are fine)
  local escaped_value="${value//\//\\/}"
  sed -i "s|  ${name} *= *\"[^\"]*\";|  ${name} = \"${escaped_value}\";|" "$MODULE"
}

# ── check current pins ────────────────────────────────────────────────────────

current_copilot="$(grep 'copilotVersion' "$MODULE" | grep -oP '(?<=\")[^\"]+(?=\")')"
current_claude="$(grep 'claudeVersion' "$MODULE" | grep -oP '(?<=\")[^\"]+(?=\")')"

echo "Current pins: copilot=${current_copilot}  claude=${current_claude}"

# ── fetch latest versions ────────────────────────────────────────────────────

echo "Fetching latest release tags…"
latest_copilot="$(latest_gh_release "github/copilot-cli")"
latest_claude="$(latest_gh_release "anthropics/claude-code")"

echo "Latest:   copilot=${latest_copilot}  claude=${latest_claude}"

# ── update copilot ───────────────────────────────────────────────────────────

if [[ "$current_copilot" == "$latest_copilot" ]]; then
  echo "github-copilot-cli already at ${latest_copilot}, skipping."
else
  echo "Updating github-copilot-cli ${current_copilot} → ${latest_copilot}"

  hash_linux_x64="$(fetch_sri \
    "https://github.com/github/copilot-cli/releases/download/v${latest_copilot}/github-copilot-${latest_copilot}-linux-x64.tgz")"
  hash_darwin_arm64="$(fetch_sri \
    "https://github.com/github/copilot-cli/releases/download/v${latest_copilot}/github-copilot-${latest_copilot}-darwin-arm64.tgz")"

  update_nix_var "copilotVersion"         "$latest_copilot"
  update_nix_var "copilotHashLinuxX64"    "$hash_linux_x64"
  update_nix_var "copilotHashDarwinArm64" "$hash_darwin_arm64"

  echo "  copilot linux-x64:    ${hash_linux_x64}"
  echo "  copilot darwin-arm64: ${hash_darwin_arm64}"
fi

# ── update claude-code ────────────────────────────────────────────────────────

if [[ "$current_claude" == "$latest_claude" ]]; then
  echo "claude-code already at ${latest_claude}, skipping."
else
  echo "Updating claude-code ${current_claude} → ${latest_claude}"

  hash_linux_x64="$(fetch_sri \
    "https://downloads.claude.ai/claude-code-releases/${latest_claude}/linux-x64/claude")"
  hash_darwin_arm64="$(fetch_sri \
    "https://downloads.claude.ai/claude-code-releases/${latest_claude}/darwin-arm64/claude")"

  update_nix_var "claudeVersion"         "$latest_claude"
  update_nix_var "claudeHashLinuxX64"    "$hash_linux_x64"
  update_nix_var "claudeHashDarwinArm64" "$hash_darwin_arm64"

  echo "  claude linux-x64:    ${hash_linux_x64}"
  echo "  claude darwin-arm64: ${hash_darwin_arm64}"
fi

echo "Done."

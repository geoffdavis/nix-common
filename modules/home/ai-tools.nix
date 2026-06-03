# modules/home/ai-tools.nix — version-pinned AI CLI tools for all hosts.
#
# Provides claude-code (Anthropic), github-copilot-cli (GitHub), and
# codex (OpenAI), pinned past whatever nixpkgs-25.11 ships and tracking
# each vendor's PRODUCTION/stable release channel via nvfetcher
# (/nvfetcher.toml → /_sources/generated.nix). Auth configuration
# (apiKeyHelper, ANTHROPIC_BASE_URL, etc.) is intentionally not set
# here — each consumer host wires its own; see PR #15 for context.
#
# Versions bumped automatically by .github/workflows/update-sources.yml;
# also manually via `task update:sources`.
#
# Platform coverage:
#   - claude-code, copilot-cli: x86_64-linux + aarch64-darwin
#   - codex: x86_64-linux only (darwin gets it via Homebrew cask;
#     see nix-personal hosts/windansea/default.nix)
{
  lib,
  pkgs,
  ...
}: let
  sources = import ../../_sources/generated.nix {
    inherit (pkgs) fetchgit fetchurl fetchFromGitHub dockerTools;
  };

  platformSuffix =
    {
      "x86_64-linux" = "linux-x64";
      "aarch64-darwin" = "darwin-arm64";
    }
    .${
      pkgs.stdenv.hostPlatform.system
    }
    or null;

  # Override base with sources["<pkg>-<platformSuffix>"], skipping silently
  # if there's no key for this platform.
  override = base: pkg: let
    key = "${pkg}-${platformSuffix}";
  in
    if platformSuffix == null || !(sources ? ${key})
    then null
    else
      base.overrideAttrs (_: {
        inherit (sources.${key}) version src;
      });

  # codex needs a custom derivation: nixpkgs builds it from Cargo source
  # (would force a cargoHash bump every release), but the vendor publishes
  # a self-contained static-musl binary. Linux-x64 only.
  codex =
    if pkgs.stdenv.hostPlatform.system != "x86_64-linux"
    then null
    else
      pkgs.stdenv.mkDerivation {
        pname = "codex";
        inherit (sources.codex-linux-x64) version src;
        sourceRoot = ".";
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          runHook preInstall
          install -Dm755 codex-x86_64-unknown-linux-musl $out/bin/codex
          runHook postInstall
        '';
        meta.mainProgram = "codex";
      };
in {
  home.packages = lib.filter (p: p != null) [
    (override pkgs.claude-code "claude-code")
    (override pkgs.github-copilot-cli "copilot-cli")
    codex
  ];
}

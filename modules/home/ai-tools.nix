# modules/home/ai-tools.nix — version-pinned AI CLI tools for all hosts.
#
# Provides claude-code (Anthropic), github-copilot-cli (GitHub), and
# codex (OpenAI), pinned past whatever nixpkgs ships and tracking each
# vendor's PRODUCTION/stable release channel via nvfetcher
# (/nvfetcher.toml → /_sources/generated.nix). Auth configuration
# (apiKeyHelper, ANTHROPIC_BASE_URL, etc.) is intentionally not set
# here — each consumer host wires its own; see PR #15 for context.
#
# Per-tool knobs (all default true — existing consumers are unaffected):
#   aiTools.claude.enable    = false  # opt out of claude-code
#   aiTools.codex.enable     = false  # opt out of codex (Linux-x64 only)
#   aiTools.copilotCli.enable = false  # opt out of github-copilot-cli
#
# Versions bumped automatically by .github/workflows/update-sources.yml;
# also manually via `task update:sources`.
#
# Platform coverage:
#   - claude-code, copilot-cli: x86_64-linux + aarch64-darwin
#   - codex: x86_64-linux only (darwin gets it via Homebrew cask;
#     see nix-personal hosts/windansea/default.nix)
# IMPORT-IS-OPT-IN: base/profile module — importing it IS the enable;
# config applies unconditionally (module-contract.md, "Two module classes").
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.aiTools;
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
  # if there's no key for this platform. extraBuildInputs are appended to the
  # base derivation's buildInputs — for runtime libs a vendor adds to a
  # prebuilt release that nixpkgs' pin doesn't yet cover (see copilot below).
  override = base: pkg: extraBuildInputs: let
    key = "${pkg}-${platformSuffix}";
  in
    if platformSuffix == null || !(sources ? ${key})
    then null
    else
      base.overrideAttrs (prev: {
        inherit (sources.${key}) version src;
        buildInputs = (prev.buildInputs or []) ++ extraBuildInputs;
      });

  # copilot-cli ≥1.0.71 bundles @webviewjs/webview — a prebuilt native module
  # (webview.linux-x64-gnu.node) that dynamically links GTK3, WebKit2GTK-4.1,
  # libsoup-3, and xdotool. nixpkgs' github-copilot-cli pin predates it, so
  # its buildInputs lack these and autoPatchelfHook fails the build. Add them
  # (Linux-x64 only; the darwin-arm64 tarball uses the system WebKit
  # framework) so the module patches cleanly and the webview functions.
  copilotWebviewLibs = lib.optionals pkgs.stdenv.hostPlatform.isLinux (with pkgs; [
    webkitgtk_4_1 # libwebkit2gtk-4.1.so.0, libjavascriptcoregtk-4.1.so.0
    gtk3 # libgtk-3.so.0, libgdk-3.so.0
    gdk-pixbuf # libgdk_pixbuf-2.0.so.0
    cairo # libcairo.so.2
    libsoup_3 # libsoup-3.0.so.0
    wayland # libwayland-client.so.0
    dbus # libdbus-1.so.3
    xdotool # libxdo.so.3
  ]);

  # codex needs a custom derivation: nixpkgs builds it from Cargo source
  # (would force a cargoHash bump every release), but the vendor publishes
  # prebuilt static-musl binaries. Linux-x64 only.
  #
  # The pinned asset is the `codex-package-` tarball, which carries the whole
  # upstream layout — `codex-package.json` plus `bin/`, `codex-path/` (rg) and
  # `codex-resources/` (bwrap, zsh) — and it is installed verbatim so codex
  # finds each part where it expects it, relative to its own executable.
  # Installing only `bin/codex` (what the single-binary asset gives you) is
  # NOT a smaller-but-working subset: `codex exec` and `codex review` spawn
  # `bin/codex-code-mode-host`, and when that is missing they degrade to a
  # warning plus "no actionable findings" AND STILL EXIT 0 — a review that
  # inspected nothing is indistinguishable from a clean one. Hence the
  # installCheck below: an incomplete codex must fail the build, never ship.
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
        # Vendor binaries are static-musl (no interpreter, no shared libs) and
        # ship pre-stripped; leave them exactly as upstream signed/shipped them.
        dontPatchELF = true;
        dontStrip = true;
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp -r codex-package.json bin codex-path codex-resources $out/
          chmod -R u+w $out
          runHook postInstall
        '';
        doInstallCheck = true;
        installCheckPhase = ''
          runHook preInstallCheck
          for f in bin/codex bin/codex-code-mode-host codex-path/rg codex-resources/bwrap; do
            if [ ! -x "$out/$f" ]; then
              echo "codex: upstream package tarball is missing $f — refusing to" >&2
              echo "       ship an incomplete codex (see the comment above)." >&2
              exit 1
            fi
          done
          $out/bin/codex --version
          $out/bin/codex-code-mode-host --help > /dev/null
          runHook postInstallCheck
        '';
        meta.mainProgram = "codex";
      };
in {
  # Skills ride along with claude-code: a host that installs the tool also gets
  # the guidance that makes it safe to point at this fleet's secrets. Its own
  # module (opt out with claudeSkills.enable = false) rather than inlined here;
  # see modules/home/claude-skills.nix for why skills ship declaratively at all.
  imports = [./claude-skills.nix];

  options.aiTools = {
    claude.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install claude-code (Anthropic). Set false to opt out on a host.";
    };
    codex.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install codex (OpenAI). Linux-x64 only; darwin uses the Homebrew cask. Set false to opt out on a host.";
    };
    copilotCli.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install github-copilot-cli. Set false to opt out on a host.";
    };
  };

  config.home.packages =
    lib.filter (p: p != null) (
      lib.optional cfg.claude.enable (override pkgs.claude-code "claude-code" [])
      ++ lib.optional cfg.copilotCli.enable (override pkgs.github-copilot-cli "copilot-cli" copilotWebviewLibs)
      ++ lib.optional cfg.codex.enable codex
    )
    # codex's Linux sandbox shells out to bubblewrap (bwrap) and degrades
    # noisily without it. Linux-only tool (namespaces); darwin codex uses
    # Seatbelt instead.
    ++ lib.optional (cfg.codex.enable && pkgs.stdenv.hostPlatform.isLinux) pkgs.bubblewrap;
}

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
  home.packages =
    lib.filter (p: p != null) [
      (override pkgs.claude-code "claude-code" [])
      (override pkgs.github-copilot-cli "copilot-cli" copilotWebviewLibs)
      codex
    ]
    # codex's Linux sandbox shells out to bubblewrap (bwrap) and degrades
    # noisily without it. Linux-only tool (namespaces); darwin codex uses
    # Seatbelt instead.
    ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.bubblewrap;
}

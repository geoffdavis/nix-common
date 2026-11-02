# Home-manager module: Obsidian, with stale-Chromium-cache reset (my.obsidian).
#
# nixpkgs' obsidian runs Obsidian's app.asar on nixpkgs' own Electron, so a
# flake bump can swap the Electron build under an existing profile. Chromium's
# on-disk caches in the profile (GPUCache, Dawn*, Code Cache, ...) are not
# reliably invalidated by that: on 2026-11-02 Electron 43.7.11 -> 43.8.3 left
# every Linux desktop host (NixOS and standalone home-manager) with a mapped
# but blank window — the renderer failed with `i.webFrame[t] is not a
# function` — until those directories were removed. Settings, vault list and plugins live
# elsewhere in the profile and are untouched.
#
# The installed `obsidian` is wrapped so that, at launch, it compares the
# package's store path with the one recorded in the profile and clears the
# caches when they differ. Done at launch rather than in HM activation because
# the old instance is usually still running across a switch and would write
# its caches back on exit; while any Obsidian is running the reset is skipped
# and the marker is left alone, so the next launch retries.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.obsidian;

  cacheDirs = [
    "GPUCache"
    "DawnGraphiteCache"
    "DawnWebGPUCache"
    "Code Cache"
    "ShaderCache"
    "GrShaderCache"
  ];

  resetCaches = pkgs.writeShellScript "obsidian-reset-stale-caches" ''
    dir=${lib.escapeShellArg cfg.configDir}
    marker="$dir/.nix-package"
    want=${cfg.package}
    [ -d "$dir" ] || exit 0
    [ "$(cat "$marker" 2>/dev/null)" = "$want" ] && exit 0
    # Another instance (likely the pre-switch build) still owns the profile.
    ${pkgs.procps}/bin/pgrep -u "$(id -u)" -f '/share/obsidian/app\.asar' >/dev/null && exit 0
    ${lib.concatMapStringsSep "\n" (d: ''rm -rf "$dir"/${lib.escapeShellArg d}'') cacheDirs}
    printf '%s\n' "$want" > "$marker"
  '';

  wrapped = pkgs.symlinkJoin {
    name = "obsidian-cache-reset-${lib.getVersion cfg.package}";
    paths = [cfg.package];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      rm "$out/bin/obsidian"
      makeWrapper ${cfg.package}/bin/obsidian "$out/bin/obsidian" \
        --run ${lib.escapeShellArg "${resetCaches} || true"}
    '';
  };
in {
  options.my.obsidian = {
    enable = lib.mkEnableOption "Obsidian, clearing its Chromium caches when the package changes";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.obsidian;
      defaultText = lib.literalExpression "pkgs.obsidian";
      description = ''
        Obsidian package to install and wrap. Hosts that need a GL wrapper
        (nixGL on non-NixOS) pass the wrapped package here; it must provide
        bin/obsidian.
      '';
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default =
        if pkgs.stdenv.isDarwin
        then "${config.home.homeDirectory}/Library/Application Support/obsidian"
        else "${config.xdg.configHome}/obsidian";
      defaultText = lib.literalExpression ''"''${config.xdg.configHome}/obsidian"'';
      description = "Obsidian's Electron user-data directory.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [wrapped];
  };
}

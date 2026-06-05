# modules/home/onepassword.nix — version-pinned 1Password CLI + GUI on Linux.
#
# The pinned derivations live in modules/shared/onepassword-packages.nix
# (vendor stable channel via nvfetcher; see the rationale there).
#
# Linux-x86_64 only. macOS hosts install 1Password via Homebrew casks
# declared in modules/darwin/common.nix.
#
# Imported transitively by cli-tools.nix, so every consumer of cli-tools /
# desktop-base / gnome-desktop-base picks up the pinned versions
# transparently — no host-side opt-in needed.
#
# NixOS hosts: set onepassword.installPackages = false here and import
# nixosModules.onepassword at the system layer instead. The 1Password app
# only accepts CLI-integration connections from the setgid `op` wrapper
# that programs._1password creates — a plain home.packages `op` gets
# "connecting to desktop app: read: connection reset".
#
# Non-NixOS Linux desktops (Ubuntu + home-manager) hit the same wall: the
# app checks that the connecting `op` runs with effective gid
# `onepassword-cli`, and the nix store can't hold setgid binaries. There
# the system layer (e.g. ansible) must install a small setgid shim that
# execs the real CLI; set onepassword.setgidShim.enable = true to wire the
# user-layer half (see the option description for the contract).
{
  lib,
  pkgs,
  config,
  ...
}: let
  pinned = import ../shared/onepassword-packages.nix {inherit lib pkgs;};
  isLinuxX64 = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
  cfg = config.onepassword;
in {
  options.onepassword = {
    installPackages = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install the pinned 1Password CLI + GUI as user packages (Linux-x64
        only). Set to false on NixOS hosts, where nixosModules.onepassword
        installs the same pinned versions via programs._1password /
        programs._1password-gui so the desktop-app CLI integration works.
      '';
    };

    setgidShim = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Route `op` through a system-layer setgid shim so the CLI can talk
          to the desktop app on non-NixOS Linux hosts (NixOS hosts get this
          via nixosModules.onepassword / /run/wrappers instead).

          Contract with the system layer: something outside nix (e.g. an
          ansible role) must install a root-owned, setgid-`onepassword-cli`
          shim at `setgidShim.shimPath` that execs
          `~/.local/share/1password/op-cli`. This module maintains that
          symlink — repointing it at the current pinned CLI on every switch
          so the shim never goes stale — and shadows the plain `op` with a
          hiPrio wrapper routing through the shim, so interactive shells
          and activation scripts (anything resolving `op` from PATH) all
          get desktop-app integration.
        '';
      };

      shimPath = lib.mkOption {
        type = lib.types.str;
        default = "/usr/local/bin/op";
        description = ''
          Where the system layer installs the setgid shim.
        '';
      };
    };
  };

  config = lib.mkMerge [
    {
      home.packages =
        lib.mkIf (cfg.installPackages && isLinuxX64)
        [pinned.cli pinned.gui];
    }

    (lib.mkIf cfg.setgidShim.enable {
      # Stable exec target for the setgid shim; tracks the pinned CLI.
      home.file.".local/share/1password/op-cli".source = "${pinned.cli}/bin/op";

      home.packages = [
        (lib.hiPrio (pkgs.writeShellScriptBin "op" ''
          if [ -x ${cfg.setgidShim.shimPath} ]; then
            exec ${cfg.setgidShim.shimPath} "$@"
          fi
          # Shim not provisioned yet (system layer hasn't run); fall back
          # to the plain CLI — works, but without desktop-app integration.
          echo "op: setgid shim missing; running without desktop-app integration" >&2
          exec ${pinned.cli}/bin/op "$@"
        ''))
      ];
    })
  ];
}

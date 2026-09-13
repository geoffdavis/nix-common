# modules/home/onepassword.nix — 1Password CLI + GUI as user packages on
# Linux.
#
# The packages come from nixpkgs. On NixOS hosts nixosModules.common applies
# the onepassword-unstable overlay (see flake.nix for why unstable), and
# useGlobalPkgs means this module sees it too; consumers that are not NixOS
# should add overlays.onepassword-unstable themselves.
#
# Linux-x86_64 only. macOS hosts install 1Password via Homebrew casks
# declared in modules/darwin/common.nix.
#
# Imported transitively by cli-tools.nix, so every consumer of cli-tools /
# desktop-base / gnome-desktop-base picks these up transparently — no
# host-side opt-in needed.
#
# Where these packages should actually be used:
#
# - NixOS hosts: set installPackages = false and import
#   nixosModules.onepassword at the system layer instead — the app only
#   accepts CLI-integration connections from the setgid `op` wrapper that
#   programs._1password places in /run/wrappers ("connecting to desktop
#   app: read: connection reset" otherwise).
# - Non-NixOS Linux *desktops*: set installPackages = false and install
#   the vendor .deb via the system layer. The desktop app's integration
#   points (setgid op + BrowserSupport, polkit policy, native-messaging
#   manifests, op-ssh-sign) are undocumented vendor contracts; a
#   setgid-shim reimplementation lived here briefly (2026-06-05, see git
#   history) and was reverted as unmaintainable.
# - Non-NixOS *headless* hosts: use these packages as-is (with
#   installGui = false) — standalone `op` needs none of the desktop glue.
{
  lib,
  pkgs,
  config,
  ...
}: let
  isLinuxX64 = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
  cfg = config.onepassword;
in {
  options.onepassword = {
    installPackages = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install the 1Password CLI + GUI as user packages (Linux-x64
        only). Set to false on hosts where 1Password comes from the system
        layer: NixOS (nixosModules.onepassword) and non-NixOS desktops
        (vendor .deb).
      '';
    };

    installGui = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether installPackages includes the GUI. Disable on headless
        hosts that only need `op` (there's no desktop session for the GUI
        — or the CLI's app integration — to talk to anyway).
      '';
    };
  };

  config.home.packages =
    lib.mkIf (cfg.installPackages && isLinuxX64)
    ([pkgs._1password-cli] ++ lib.optional cfg.installGui pkgs._1password-gui);
}

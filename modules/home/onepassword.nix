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
    ([pinned.cli] ++ lib.optional cfg.installGui pinned.gui);
}

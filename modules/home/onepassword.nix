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
{
  lib,
  pkgs,
  config,
  ...
}: let
  pinned = import ../shared/onepassword-packages.nix {inherit lib pkgs;};
  isLinuxX64 = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
in {
  options.onepassword.installPackages = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Install the pinned 1Password CLI + GUI as user packages (Linux-x64
      only). Set to false on NixOS hosts, where nixosModules.onepassword
      installs the same pinned versions via programs._1password /
      programs._1password-gui so the desktop-app CLI integration works.
    '';
  };

  config.home.packages =
    lib.mkIf (config.onepassword.installPackages && isLinuxX64)
    [pinned.cli pinned.gui];
}

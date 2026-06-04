# modules/nixos/onepassword.nix — 1Password GUI + CLI on NixOS hosts,
# version-pinned to the vendor's stable channel (same sources as the home
# module; see modules/shared/onepassword-packages.nix).
#
# Why not home.packages (modules/home/onepassword.nix)? The 1Password app
# only accepts CLI-integration connections from an `op` binary it can
# verify — on NixOS that's the setgid wrapper (group onepassword-cli) that
# programs._1password places under /run/wrappers/bin. A plain user-package
# `op` gets "connecting to desktop app: read: connection reset", and the
# GUI misses the polkit policy it needs for system-auth prompts. Import
# this at the system layer and set onepassword.installPackages = false in
# the host's home-manager config.
#
# Hosts must set programs._1password-gui.polkitPolicyOwners (the usernames
# allowed to drive 1Password's polkit-backed auth prompts) themselves —
# this module can't know the host's user.
{
  lib,
  pkgs,
  ...
}: let
  pinned = import ../shared/onepassword-packages.nix {inherit lib pkgs;};
in {
  programs._1password = {
    enable = true;
    package = pinned.cli;
  };
  programs._1password-gui = {
    enable = true;
    package = pinned.gui;
  };
}

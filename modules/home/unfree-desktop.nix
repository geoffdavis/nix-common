# IMPORT-IS-OPT-IN: base/profile module — importing it IS the enable;
# config applies unconditionally (module-contract.md, "Two module classes").
{lib, ...}: let
  unfreePackageNames = import ../shared/unfree-package-names.nix;
in {
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) unfreePackageNames;
}

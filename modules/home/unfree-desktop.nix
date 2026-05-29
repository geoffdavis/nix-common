{lib, ...}: let
  unfreePackageNames = import ../shared/unfree-package-names.nix;
in {
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) unfreePackageNames;
}

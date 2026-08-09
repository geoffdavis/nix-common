# IMPORT-IS-OPT-IN: base/profile module — importing it IS the enable;
# config applies unconditionally (module-contract.md, "Two module classes").
{...}: {
  imports = [
    ./desktop-base.nix
    ./gnome-dconf.nix
    ./unfree-desktop.nix
  ];
}

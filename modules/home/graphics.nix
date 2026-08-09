# IMPORT-IS-OPT-IN: base/profile module — importing it IS the enable;
# config applies unconditionally (module-contract.md, "Two module classes").
{pkgs, ...}: {
  # Graphics and diagramming tools
  home.packages = with pkgs; [
    drawio
  ];
}

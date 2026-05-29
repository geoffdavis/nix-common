{pkgs, ...}: {
  # Graphics and diagramming tools
  home.packages = with pkgs; [
    drawio
  ];
}

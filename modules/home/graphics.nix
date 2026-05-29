{
  lib,
  pkgs,
  ...
}: {
  # Central unfree allowlist for shared desktop packages.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "drawio"
      "obsidian"
    ];

  # Graphics and diagramming tools
  home.packages = with pkgs; [
    drawio
  ];
}

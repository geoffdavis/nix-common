# Shared neovim / LazyVim editor config + the global EDITOR default.
# Cross-platform (macOS + Linux). Consumers wire `lazyvim` in via
# home-manager `extraSpecialArgs = { inherit lazyvim; }`.
{
  lazyvim,
  pkgs,
  ...
}: {
  imports = [lazyvim.homeManagerModules.default];

  # Global editor for every host that imports this module.
  home.sessionVariables.EDITOR = "nvim";

  programs.lazyvim = {
    enable = true;

    extras = {
      lang.nix.enable = true;
      lang.python = {
        enable = true;
        installDependencies = true;
        installRuntimeDependencies = true;
      };
      lang.go = {
        enable = true;
        installDependencies = true;
        installRuntimeDependencies = true;
      };
    };

    extraPackages = with pkgs; [
      tree-sitter # required by nvim-treesitter; mason is disabled in nix setups
      nixd # Nix LSP
      alejandra # Nix formatter
      statix # Nix linter (LazyVim lang.nix expects it on PATH)
      deadnix # dead-code linter for Nix (LazyVim lang.nix)
    ];

    treesitterParsers = with pkgs.vimPlugins.nvim-treesitter-parsers; [
      dockerfile
      sql
      wgsl # WebGPU Shading Language
      templ # Go templ files
      # LazyVim's default ensure_installed requests these; without nix
      # providing them nvim-treesitter downloads + compiles at runtime
      # (slow / fails on nix). Keep prebuilt instead.
      git_config
      git_rebase
      gitattributes
      gitcommit
      gitignore
      hcl
      ruby
      terraform
    ];
  };
}

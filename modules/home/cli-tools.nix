# Shared CLI tooling, cross-platform (macOS + Linux).
# Imported from each host's home-manager user config.
{
  lib,
  pkgs,
  ...
}: {
  home.packages =
    (with pkgs; [
      # cloud / infra
      ansible
      awscli2
      cilium-cli
      cloudflared
      cosign
      crane
      fluxcd
      kubernetes-helm
      jfrog-cli
      k9s
      opentofu
      pulumi
      talhelper
      talosctl
      terragrunt

      # git / source control
      gh
      git-filter-repo
      git-secrets
      gitleaks

      # shells & terminal
      bashInteractive
      tmux
      pay-respects # `thefuck` replacement; nixpkgs dropped thefuck

      # languages / runtimes
      go
      go-task
      nodejs
      hugo

      # python tooling
      python312
      pipenv
      pipx
      pre-commit
      python3Packages.pytest
      uv

      # perl tooling
      perlPackages.Appcpanminus

      # general utilities
      btop
      dtc
      expect
      gnugrep
      gnumake
      gnupatch
      ipcalc
      jq
      markdownlint-cli
      mise
      ripgrep
      tree
      yamllint
      yq-go

      # nix tooling
      alejandra

      # editor support
      # (neovim itself is provided by lazyvim-nix)
    ])
    ++ lib.optionals pkgs.stdenv.isLinux [
      _1password-cli
    ];
}

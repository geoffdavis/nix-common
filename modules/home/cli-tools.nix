# Shared CLI tooling, cross-platform (macOS + Linux).
# Imported from each host's home-manager user config.
# IMPORT-IS-OPT-IN: base/profile module — importing it IS the enable;
# config applies unconditionally (module-contract.md, "Two module classes").
{
  pkgs,
  lib,
  ...
}: let
  # pipx 1.8.0's test suite fails under nixpkgs 26.05: the `packaging`
  # library now normalizes PEP 508 direct-reference URLs with spaces
  # around `@` (e.g. `pkg @ git+ssh://…`), so pipx's hard-coded
  # expectations in these two parametrized tests no longer match. The
  # package itself works fine — disable just the affected tests.
  pipx = pkgs.pipx.overridePythonAttrs (old: {
    disabledTests =
      (old.disabledTests or [])
      ++ [
        "test_fix_package_name"
        "test_parse_specifier_for_metadata"
      ];
  });

  # cliamp's IPC test (TestServerMultipleRequestsSameConnection) binds a
  # unix-domain socket under the sandbox build dir. On Darwin that path is
  # 107 bytes — over macOS's 104-byte sun_path limit — so bind() fails with
  # EINVAL and the build dies. (Linux's limit is 108, so Hydra never catches
  # it.) Skip just that test on Darwin. Upstream fix: NixOS/nixpkgs#535492 —
  # drop this override once it merges and we bump nixpkgs.
  cliamp = pkgs.cliamp.overrideAttrs (old: {
    checkFlags =
      (old.checkFlags or [])
      ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
        "-skip=^TestServerMultipleRequestsSameConnection$"
      ];
  });
in {
  imports = [
    ./onepassword.nix
    ./terraform.nix
  ];

  home.sessionPath = ["$HOME/.local/bin"];

  home.packages = with pkgs;
    [
      # cloud / infra
      ansible
      azure-cli
      google-cloud-sdk
      azure-storage-azcopy
      awscli2
      cilium-cli
      cloudflared
      cosign
      crane
      fluxcd
      fluxcd-operator-mcp # MCP server for the Flux Operator (was the controlplaneio-fluxcd brew tap)
      # kubectl was missing while fluxcd, k9s, helm, talhelper and talosctl
      # were all here -- every one of which assumes a working kubectl next
      # to it. Adding it rather than reaching for `nix shell` each time.
      kubectl
      kubernetes-helm
      jfrog-cli
      k9s
      opentofu
      # pulumi (+ pulumi-esc) intentionally NOT here — not daily-use; pull them
      # per-project via a direnv/devshell instead. Both are in nixpkgs.
      # terraform itself is pinned via modules/home/terraform.nix (imported
      # above) so it tracks HashiCorp's stable channel rather than lagging
      # nixpkgs.
      # secrets. Every host in the fleet keys its sops-nix secrets on its own
      # SSH ed25519 key (hosts/<name>/secrets/secrets.yaml), and NONE of the
      # three tools needed to work with that were installed anywhere:
      # `sops` to edit, `ssh-to-age` to derive the age recipient from a host
      # key, `age` underneath both.
      sops
      ssh-to-age
      age

      talhelper
      talosctl
      terragrunt

      # git / source control
      gh
      git-filter-repo
      git-secrets
      gitleaks
      lazygit # git TUI

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
      bat # cat/pager with syntax highlighting; also colored MANPAGER (zsh.nix)
      btop
      # CRLF<->LF conversion (dos2unix/unix2dos/mac2unix). Fleet-wide rather
      # than per-host: Windows-authored files land on whichever machine is
      # nearest -- the work laptops pull them out of SharePoint/Teams, and
      # they arrive on the personal boxes as email attachments and repo
      # checkouts. In stable on both channels, so it is safe for this list.
      dos2unix
      dtc
      expect
      eza # iconified ls/tree, aliased over ls (zsh.nix)
      fastfetch # neofetch-like system info
      file # mime detection for the ff fzf preview (zsh.nix)
      fzf
      gnugrep
      gnumake
      gnupatch
      gum # confirm prompts in shell functions (gwd in zsh.nix)
      dnsutils # dig. The estate runs FreeIPA DNS with delegation, netbird
      # nameserver groups, external-dns and UDM static records -- diagnosing
      # any of it without dig means guessing.
      ipcalc
      nmap # subnet sweeps when a fleet host stops answering; the fallback is
      # a hand-rolled 254-iteration ping loop, which is how this gap was found
      jq
      lazydocker # docker/compose TUI
      markdownlint-cli
      actionlint # GitHub Actions workflow linter; used by pre-commit language:system hooks
      markdownlint-cli2
      mise
      ripgrep
      shellcheck # shell linter; used by pre-commit language:system hooks
      tree
      watch
      yamllint
      yq # kislyuk/yq (python): bare `yq .` emits JSON, which the shared
      # terraform aliases (tfcd/tfstackshow/y2j*) pipe into jq. mikefarah
      # yq-go's `yq .` prints YAML instead, breaking those `yq . | jq`
      # pipelines with "jq: parse error: Invalid numeric literal".

      # nix tooling
      alejandra
      deadnix
      statix
      # closure analysis. This fleet reasons about closure size constantly
      # (armv7l has no binary cache, so every derivation is paid for), and
      # doing it by hand with `nix path-info` invites double-counting shared
      # paths. nix-tree answers "what pulls this in", nvd diffs generations.
      nix-tree
      nvd

      # python linting (the runtime is python312 above)
      ruff

      # editor support
      # (neovim itself is provided by lazyvim-nix)
    ]
    # cliamp (terminal Winamp) — darwin only; see the override above for the
    # darwin-specific test-skip rationale.
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      cliamp
    ];
}

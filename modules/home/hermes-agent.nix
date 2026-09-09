# modules/home/hermes-agent.nix — Hermes Agent package, extended with Mnemosyne.
# IMPORT-IS-OPT-IN: importing this module selects the package.
#
# Imports Hermes' upstream Home Manager module for its `programs.hermes-agent`
# (CLI + Desktop) options and package plumbing only, and changes the default
# package (`services.hermes-agent.package`, inherited by
# `programs.hermes-agent.package`) to one extended with the Mnemosyne provider.
# Every Hermes surface a consumer builds from
# `config.services.hermes-agent.package` — the CLI, Desktop backend, and a
# systemd/launchd gateway — shares that one package.
#
# This module does NOT enable `services.hermes-agent`. That upstream service
# owns config.yaml declaratively (deep-merging `settings` on every activation)
# and writes a `~/.hermes/.managed` marker with `HERMES_MANAGED=home-manager`,
# which makes Hermes itself refuse `hermes config set`/`config edit` and any
# other programmatic config write — including from provider profiles like
# Donna. Runtime config.yaml and per-profile config must stay mutable, so
# ownership of the provider selection and other runtime settings is left
# entirely to the mutable config.yaml, not to Nix. A consumer that wants the
# gateway/backend units runs its own systemd/launchd units against
# `config.services.hermes-agent.package` instead of enabling the upstream
# service.
inputs: {
  config,
  lib,
  pkgs,
  ...
}: let
  hermesPkgs = inputs.hermes-nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  pythonPackages = hermesPkgs.python312Packages;

  # Hermes' sealed uv2nix environment already contains most of fastembed's
  # runtime dependencies. Keep only the dependencies absent from that venv so
  # Hermes' package-collision check remains useful rather than rejecting the
  # same Python distribution from both environments.
  fastembed = pythonPackages.fastembed.overridePythonAttrs (_: {
    dependencies = with pythonPackages; [
      loguru
      mmh3
      py-rust-stemmers
      pystemmer
    ];
    pythonImportsCheck = [];
    dontCheckRuntimeDeps = true;
  });

  sqlite-vec = pythonPackages.sqlite-vec.overridePythonAttrs (_: {
    nativeCheckInputs = [];
    doCheck = false;
    dontCheckRuntimeDeps = true;
  });

  mnemosyne-memory = pythonPackages.buildPythonPackage rec {
    pname = "mnemosyne-memory";
    version = "3.15.1";
    pyproject = true;

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/42/58/968d0f74505fdb2db9a7508192720c5faa9a351313f04acd0ba09b553a9f/mnemosyne_memory-3.15.1.tar.gz";
      hash = "sha256-lspUMxc0pUSkhSUrNdiiO5OJ1NMC/S853EYSanXtXKM=";
    };

    build-system = [pythonPackages.setuptools];
    dependencies = [
      fastembed
      sqlite-vec
    ];

    doCheck = false;
    pythonImportsCheck = [];
    dontCheckRuntimeDeps = true;
  };

  mnemosyne-hermes = pythonPackages.buildPythonPackage rec {
    pname = "mnemosyne-hermes";
    version = "0.5.0";
    pyproject = true;

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/d2/cb/ceb7afc9ef1e61a78f29446c81b62ec0dd1f101fb62f16a09156ead5007e/mnemosyne_hermes-0.5.0.tar.gz";
      hash = "sha256-CzEvnUw5oPFtT5bHQQ/GBdy2C/E7qShQn32irIRYKqw=";
    };

    build-system = [pythonPackages.setuptools];
    dependencies = [mnemosyne-memory];

    doCheck = false;
    pythonImportsCheck = [];
    dontCheckRuntimeDeps = true;
  };

  hermesWithMnemosyne = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    extraPythonPackages = [mnemosyne-hermes];
  };
in {
  imports = [inputs.hermes-agent.homeManagerModules.default];

  # Package only. `enable` stays at its upstream default (false): no managed
  # service, no activation-owned config.yaml, no `.managed` marker. A
  # consumer can still read `config.services.hermes-agent.package` for its own
  # units, or opt into the upstream service with `enable = true` if it
  # actually wants Nix to own config.yaml.
  services.hermes-agent.package = lib.mkDefault hermesWithMnemosyne;

  # The CLI (and HERMES_HOME) on PATH, and the Desktop application, both
  # built from the same extended package above. Neither depends on
  # `services.hermes-agent.enable`.
  programs.hermes-agent = {
    enable = lib.mkDefault true;
    package = lib.mkDefault config.services.hermes-agent.package;
  };
}

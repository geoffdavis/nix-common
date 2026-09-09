# modules/home/hermes-agent.nix — Hermes Agent with Mnemosyne memory.
# IMPORT-IS-OPT-IN: importing this module selects and configures the backend.
#
# Imports Hermes' upstream Home Manager module and changes its default package
# to include the Mnemosyne provider. Importing this module opts the consumer in:
# every Hermes surface uses the same provider-capable package and Mnemosyne is
# selected unless the consumer overrides the service settings.
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

  services.hermes-agent = {
    enable = lib.mkDefault true;
    package = lib.mkDefault hermesWithMnemosyne;
    settings = {
      memory = {
        provider = "mnemosyne";
        # Mnemosyne owns durable memory when selected. Leaving the built-in files
        # enabled duplicates writes and injects the same facts twice.
        memory_enabled = false;
        user_profile_enabled = false;
      };
    };
  };

  programs.hermes-agent = {
    enable = lib.mkDefault true;
    package = lib.mkDefault config.services.hermes-agent.package;
  };
}

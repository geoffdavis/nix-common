# modules/shared/onepassword-packages.nix — version-pinned 1Password CLI +
# GUI derivations for Linux-x64, shared by modules/home/onepassword.nix
# (plain home.packages install for non-NixOS hosts) and
# modules/nixos/onepassword.nix (programs._1password* install for NixOS).
#
# Tracks 1Password's PRODUCTION/stable release channel via nvfetcher
# (/nvfetcher.toml → /_sources/generated.nix). nixpkgs-25.11 lags upstream
# (e.g. nixpkgs ships _1password-cli 2.32.0 while the apt repo on Ubuntu is
# at 2.34.0); the older nix builds cannot read config/cache written by the
# newer apt builds, so we override both packages to the vendor's current
# release.
#
# Bumped automatically by .github/workflows/update-sources.yml; also
# manually via `task update:sources`.
{
  lib,
  pkgs,
}: let
  sources = import ../../_sources/generated.nix {
    inherit (pkgs) fetchgit fetchurl fetchFromGitHub dockerTools;
  };

  # Upstream nixpkgs derivations use fetchzip / fetchTarball, which extract
  # at fetch time. nvfetcher emits fetchurl (raw archive), so we let stdenv
  # unpack at build time — adding the matching unpacker to nativeBuildInputs,
  # and overriding sourceRoot for archives that extract flat (the CLI zip
  # contains `op` at the root, no enclosing directory).
  override = base: srcKey: {
    extraUnpackers ? [],
    sourceRoot ? null,
  }:
    base.overrideAttrs (old:
      {
        inherit (sources.${srcKey}) version src;
        nativeBuildInputs = (old.nativeBuildInputs or []) ++ extraUnpackers;
      }
      // lib.optionalAttrs (sourceRoot != null) {inherit sourceRoot;});
in {
  cli = override pkgs._1password-cli "_1password-cli-linux-x64" {
    extraUnpackers = [pkgs.unzip];
    sourceRoot = ".";
  };
  gui = override pkgs._1password-gui "_1password-gui-linux-x64" {};
}

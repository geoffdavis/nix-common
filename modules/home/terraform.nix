# modules/home/terraform.nix — version-pinned terraform tracking
# HashiCorp's stable release channel via nvfetcher (/nvfetcher.toml →
# /_sources/generated.nix).
#
# Why a custom derivation instead of `pkgs.terraform.overrideAttrs`?
# nixpkgs builds terraform from Go source via buildGoModule, which means
# every bump would force a vendorHash recompute — defeating the
# auto-update story. HashiCorp ships signed prebuilt static binaries
# at releases.hashicorp.com; we install those directly.
#
# Bumped automatically by .github/workflows/update-sources.yml; also
# manually via `task update:sources`.
#
# Platform coverage: x86_64-linux + aarch64-darwin. Imported
# transitively by cli-tools.nix so every consumer host picks up the
# pinned version without a per-host change.
{
  lib,
  pkgs,
  ...
}: let
  sources = import ../../_sources/generated.nix {
    inherit (pkgs) fetchgit fetchurl fetchFromGitHub dockerTools;
  };

  srcKey =
    {
      "x86_64-linux" = "terraform-linux-x64";
      "aarch64-darwin" = "terraform-darwin-arm64";
    }
    .${
      pkgs.stdenv.hostPlatform.system
    }
    or null;

  terraform =
    if srcKey == null
    then null
    else
      pkgs.stdenv.mkDerivation {
        pname = "terraform";
        inherit (sources.${srcKey}) version src;
        nativeBuildInputs = [pkgs.unzip];
        # HashiCorp's zip extracts to a flat directory containing only the
        # `terraform` binary.
        sourceRoot = ".";
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          runHook preInstall
          install -Dm755 terraform $out/bin/terraform
          runHook postInstall
        '';
        meta.mainProgram = "terraform";
      };
in {
  home.packages = lib.optional (terraform != null) terraform;
}

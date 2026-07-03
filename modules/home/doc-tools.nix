# modules/home/doc-tools.nix — document generation tools for macOS hosts.
#
# Installs docx2pdf via pipx on activation. docx2pdf drives Microsoft Word
# via AppleScript to convert DOCX files to PDF headlessly; it is macOS-only
# and not packaged in nixpkgs. pipx is expected to be present (cli-tools.nix).
#
# Usage in a host config:
#
#   imports = [ nix-common.homeModules.doc-tools ];
#   docTools.enable = true;
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.docTools;
in {
  options.docTools.enable =
    lib.mkEnableOption "document generation tools (docx2pdf via pipx, macOS only)";

  config = lib.mkIf (cfg.enable && pkgs.stdenv.isDarwin) {
    # pipx is expected to be in PATH via homeModules.cli-tools. We do not pull
    # in pkgs.pipx here because nixpkgs 26.05 pipx 1.8.0 has failing tests that
    # require an override (see cli-tools.nix). Using the PATH pipx avoids
    # duplicating that override.
    home.activation.installDocx2pdf = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if command -v pipx >/dev/null 2>&1; then
        if ! pipx list --short 2>/dev/null | grep -q '^docx2pdf'; then
          $VERBOSE_ECHO "doc-tools: installing docx2pdf via pipx"
          $DRY_RUN_CMD pipx install docx2pdf
        fi
      else
        echo "doc-tools: pipx not found in PATH; skipping docx2pdf install" >&2
      fi
    '';
  };
}

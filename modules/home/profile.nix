{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.sharedProfile;
in {
  options.sharedProfile.snippets = lib.mkOption {
    type = lib.types.listOf lib.types.lines;
    default = [];
    description = ''
      Snippets to append to ~/.profile on Linux systems.
      Use this to centralize GUI/login session environment setup.
    '';
  };

  config = lib.mkIf (pkgs.stdenv.isLinux && cfg.snippets != []) {
    home.file.".profile".text = lib.concatStringsSep "\n\n" cfg.snippets + "\n";
  };
}

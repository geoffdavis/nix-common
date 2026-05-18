# Shared git config for every host.
# Per-host modules set programs.git.settings.user.email and
# programs.git.signing.key (the ed25519 pubkey 1Password signs commits with).
{
  config,
  lib,
  pkgs,
  ...
}: let
  signingEmail = lib.attrByPath ["programs" "git" "settings" "user" "email"] null config;
  signingKey = lib.attrByPath ["programs" "git" "signing" "key"] null config;
  allowedSignersFile = "${config.home.homeDirectory}/.config/git/allowed_signers";
in {
  programs.git = {
    enable = true;

    settings = {
      user.name = "Geoff Davis";

      alias = {
        st = "status";
        co = "checkout";
      };

      gpg.ssh.program =
        if pkgs.stdenv.hostPlatform.isDarwin
        then "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
        else "/opt/1Password/op-ssh-sign";

      gpg.ssh.allowedSignersFile = allowedSignersFile;
    };

    signing = {
      format = "ssh";
      signByDefault = true;
    };
  };

  home.file.".config/git/allowed_signers" = lib.mkIf (signingEmail != null && signingKey != null) {
    text = ''
      ${signingEmail} ${signingKey}
    '';
  };
}

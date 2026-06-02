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
  hasSigning = signingEmail != null && signingKey != null;
  allowedSignersFile = "${config.home.homeDirectory}/.config/git/allowed_signers";

  # Default op-ssh-sign location per platform: the macOS app bundle on darwin,
  # the 1Password .deb install path on Linux. NixOS hosts (where /opt isn't
  # populated) override `programs.git.settings.gpg.ssh.program` to the nix
  # store path themselves.
  defaultOpSshSign =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
    else "/opt/1Password/op-ssh-sign";
in {
  programs.git = {
    enable = true;

    settings = {
      user.name = "Geoff Davis";

      alias = {
        st = "status";
        co = "checkout";
      };

      gpg.ssh = {
        program = lib.mkDefault defaultOpSshSign;
        inherit allowedSignersFile;
      };
    };

    # Sign commits only on hosts that have wired up a key. Hosts without one
    # (e.g. NixOS dev boxes) leave signing untriggered, so a missing or
    # mis-pathed op-ssh-sign never blocks `git commit`.
    signing = {
      format = "ssh";
      signByDefault = hasSigning;
    };
  };

  home.file.".config/git/allowed_signers" = lib.mkIf hasSigning {
    text = ''
      ${signingEmail} ${signingKey}
    '';
  };
}

# Shared git config for every host.
# Per-host modules set programs.git.settings.user.email and
# programs.git.signing.key (the ed25519 pubkey 1Password signs commits with).
{pkgs, ...}: {
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
    };

    signing = {
      format = "ssh";
      signByDefault = true;
    };
  };
}

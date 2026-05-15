# Shared git config for every host.
# Per-host modules set programs.git.userEmail and programs.git.signing.key
# (the ed25519 pubkey 1Password signs commits with).
{pkgs, ...}: {
  programs.git = {
    enable = true;
    userName = "Geoff Davis";

    aliases = {
      st = "status";
      co = "checkout";
    };

    signing = {
      format = "ssh";
      signByDefault = true;
    };

    extraConfig = {
      gpg.ssh.program =
        if pkgs.stdenv.hostPlatform.isDarwin
        then "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
        else "/opt/1Password/op-ssh-sign";
    };
  };
}

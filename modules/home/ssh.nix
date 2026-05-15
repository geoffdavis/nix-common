{pkgs, ...}: let
  opAgent =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    else "~/.1password/agent.sock";
in {
  programs.ssh = {
    enable = true;
    extraConfig = ''
      IdentityAgent ${opAgent}
    '';
  };
}

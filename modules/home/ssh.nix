{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.onepassword-ssh;
  opAgent =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    else "~/.1password/agent.sock";
in {
  options.onepassword-ssh.keys = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        item = lib.mkOption {
          type = lib.types.str;
          description = "1Password item name holding the SSH key.";
        };
        vault = lib.mkOption {
          type = lib.types.str;
          description = "1Password vault containing the item.";
        };
      };
    });
    default = [];
    description = ''
      SSH keys to expose via the 1Password SSH agent. Generates
      ~/.config/1Password/ssh/agent.toml. When empty, no file is written
      and 1Password falls back to its default behavior.
    '';
  };

  config = {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks."*" = {
        forwardAgent = false;
        addKeysToAgent = "no";
        compression = false;
        serverAliveInterval = 0;
        serverAliveCountMax = 3;
        hashKnownHosts = false;
        userKnownHostsFile = "~/.ssh/known_hosts";
        controlMaster = "no";
        controlPath = "~/.ssh/master-%r@%n:%p";
        controlPersist = "no";
        extraOptions = {
          IdentityAgent = opAgent;
        };
      };
    };

    home.file.".config/1Password/ssh/agent.toml" = lib.mkIf (cfg.keys != []) {
      text =
        lib.concatMapStringsSep "\n\n" (k: ''
          [[ssh-keys]]
          item = "${k.item}"
          vault = "${k.vault}"
        '')
        cfg.keys;
    };
  };
}

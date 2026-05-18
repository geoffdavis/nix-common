{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.onepassword-ssh;
  opAgent =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "${config.home.homeDirectory}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    else "${config.home.homeDirectory}/.1password/agent.sock";
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
    # Ensure git SSH signing uses the 1Password agent instead of desktop keyring agents.
    # SSH_AUTH_SOCK on both Linux + Darwin. The opAgent let-binding at the
    # top of the file is already platform-conditional (1P's per-OS socket
    # paths), so this works uniformly. Previously this was Linux-only, but
    # that meant macOS shells inherited Apple's default launchd socket
    # (/private/tmp/com.apple.launchd.*/Listeners), which has no identities
    # — so tools that honor SSH_AUTH_SOCK (rsync, custom CLIs, fallback
    # paths in op-ssh-sign for transient XPC hiccups) couldn't reach the
    # 1P agent. ssh client itself already gets the right agent via the
    # IdentityAgent matchBlock below, but env-var-based tools need this.
    home.sessionVariables = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux || pkgs.stdenv.hostPlatform.isDarwin) {
      SSH_AUTH_SOCK = opAgent;
    };

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

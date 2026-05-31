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

  # ssh_config value: the darwin agent socket lives under "Group Containers"
  # (spaces), so it must be double-quoted or ssh treats the spaces as extra
  # arguments and rejects the whole config. SSH_AUTH_SOCK (an env var) keeps the
  # bare path.
  opAgentSsh = "\"${opAgent}\"";

  sanitize = name: lib.replaceStrings [" " "/"] ["_" "_"] name;
  pubFileRel = k: ".ssh/op-${sanitize k.item}.pub";
  pubFileSsh = k: "~/${pubFileRel k}";

  keysWithPub = builtins.filter (k: k.publicKey != null) cfg.keys;
  scopedKeys = builtins.filter (k: k.hosts != []) cfg.keys;
  defaultKeys = builtins.filter (k: k.default) cfg.keys;
  defaultKey =
    if defaultKeys == []
    then null
    else builtins.head defaultKeys;
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
        publicKey = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            OpenSSH-format public key. Written to ~/.ssh/op-<item>.pub so
            ssh can match it against the agent's identities under
            IdentitiesOnly. Required when this key is set as `default` or
            referenced in `hosts`.
          '';
        };
        hosts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = ''
            SSH Host patterns that should use this key (and only this key).
            Each entry list becomes one `Host <pattern1> <pattern2> ...`
            block with IdentityFile pointing at this key and
            IdentitiesOnly yes.
          '';
        };
        default = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Use this as the fallback identity for the global `*` block.
            At most one key may set this. When set, destinations not
            otherwise covered will only be offered this key (via
            IdentitiesOnly yes).
          '';
        };
      };
    });
    default = [];
    description = ''
      SSH keys to expose via the 1Password SSH agent. Generates
      ~/.config/1Password/ssh/agent.toml plus per-key public-key files
      under ~/.ssh/op-<item>.pub for ssh_config IdentityFile use.
    '';
  };

  config = {
    assertions =
      [
        {
          assertion = builtins.length defaultKeys <= 1;
          message = "onepassword-ssh.keys: at most one key may set default = true.";
        }
      ]
      ++ map (k: {
        assertion = k.publicKey != null;
        message = "onepassword-ssh.keys: key \"${k.item}\" sets hosts or default but has no publicKey.";
      }) (builtins.filter (k: (k.hosts != [] || k.default) && k.publicKey == null) cfg.keys);

    # SSH_AUTH_SOCK on both Linux + Darwin. opAgent is platform-conditional
    # so this works uniformly. Tools that honor SSH_AUTH_SOCK (rsync,
    # op-ssh-sign fallback paths, custom CLIs) reach the 1P agent through
    # this; the ssh client itself uses IdentityAgent below.
    home.sessionVariables = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux || pkgs.stdenv.hostPlatform.isDarwin) {
      SSH_AUTH_SOCK = opAgent;
    };

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks =
        {
          "*" =
            {
              extraOptions = {
                IdentityAgent = opAgentSsh;
              };
            }
            // lib.optionalAttrs (defaultKey != null) {
              identityFile = pubFileSsh defaultKey;
              identitiesOnly = true;
            };
        }
        // builtins.listToAttrs (map (k: {
            name = builtins.concatStringsSep " " k.hosts;
            value = {
              identityFile = pubFileSsh k;
              identitiesOnly = true;
              extraOptions = {
                IdentityAgent = opAgentSsh;
              };
            };
          })
          scopedKeys);
    };

    home.file =
      {
        ".config/1Password/ssh/agent.toml" = lib.mkIf (cfg.keys != []) {
          text =
            lib.concatMapStringsSep "\n\n" (k: ''
              [[ssh-keys]]
              item = "${k.item}"
              vault = "${k.vault}"
            '')
            cfg.keys;
        };
      }
      // builtins.listToAttrs (map (k: {
          name = pubFileRel k;
          value = {
            text = k.publicKey + "\n";
          };
        })
        keysWithPub);
  };
}

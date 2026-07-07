# modules/nixos/ansible-user.nix — a reusable, drop-in local `ansible`
# service account for hosts under nix + FreeIPA management.
#
# Rationale: automation should not ride on a human's account. Ansible connects
# as this dedicated LOCAL user — so it keeps working during a FreeIPA or ZFS
# pool outage, like a break-glass account — with a plain shell (no interactive
# zsh config to trip over; automation runs non-interactively via /bin/sh
# anyway, but belt-and-braces), the op-ansible key, and passwordless sudo for
# `become`. Separating it from the human break-glass admin keeps the audit
# trail clean and lets the automation key rotate independently.
#
# Drop-in: enable per host with `my.ansibleUser.enable = true`; the op-ansible
# public key is the default, so folding a new host into management is just the
# enable flip (plus pointing the inventory's ansible_user at `ansible`).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.ansibleUser;
in {
  options.my.ansibleUser = {
    enable = lib.mkEnableOption "dedicated local `ansible` automation account (SSH key + NOPASSWD sudo)";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 2000;
      description = ''
        Stable uid (and matching gid) so files ansible creates have consistent
        ownership across every host in the fleet.
      '';
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII0B2u7OLCcWmYnQZ2vzXo/hBPSV9f8mGPWLyV+jgbcd op-ansible"
      ];
      description = ''
        SSH public keys allowed to log in as `ansible`. Defaults to the
        op-ansible automation key (public — safe to ship), so the module is
        drop-in; override to add/replace keys per deployment.
      '';
    };

    extraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Extra groups for the ansible user — e.g. a container-socket group — for
        the rare host whose plays need a specific capability without going
        through full `become`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.ansible.gid = cfg.uid;

    users.users.ansible = {
      isNormalUser = true;
      group = "ansible";
      inherit (cfg) uid extraGroups;
      # Off /home (and thus off any /home-on-ZFS mapping) — a service account,
      # and its home should exist even if the pool doesn't import.
      home = "/var/lib/ansible";
      createHome = true;
      # Plain login shell: automation never wants an interactive rc.
      shell = pkgs.bashInteractive;
      description = "Ansible automation service account";
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
    };

    # `become` without a password prompt — standard for an ansible service
    # account, scoped to just this user.
    security.sudo.extraRules = [
      {
        users = ["ansible"];
        commands = [
          {
            command = "ALL";
            options = ["NOPASSWD" "SETENV"];
          }
        ];
      }
    ];
  };
}

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

  # Default op-ssh-sign location per platform: the macOS app bundle on
  # darwin, the 1Password .deb install path on Linux (non-NixOS desktops
  # run the vendor deb). NixOS hosts override
  # `programs.git.settings.gpg.ssh.program` to the nix store path of the
  # GUI that nixosModules.onepassword installs.
  defaultOpSshSign =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
    else "/opt/1Password/op-ssh-sign";
in {
  programs.git = {
    enable = true;

    settings = {
      user.name = "Geoff Davis";

      # Fallback pager for the non-diff commands delta doesn't own
      # (branch/tag -l/config -l/grep/stash list/help): -F quits if the
      # output fits one screen, -R keeps colours. This replaces git's
      # built-in `LESS=FRX` default, whose deprecated -X flashes the
      # alternate buffer and drops short output on modern less. delta still
      # overrides diff/log/show/blame (it drives less with the same
      # --quit-if-one-screen behaviour).
      core.pager = lib.mkDefault "less -FR";

      alias = {
        st = "status";
        co = "checkout";
      };

      gpg.ssh = {
        # Only set on signing hosts: the Linux default embeds the pinned
        # GUI's store path, which would otherwise drag the GUI into the
        # closure of headless hosts that never sign.
        program = lib.mkIf hasSigning (lib.mkDefault defaultOpSshSign);
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

  # Syntax-highlighted diff pager. enableGitIntegration wires delta up as
  # git's core.pager / interactive.diffFilter and points to the pinned
  # git-delta package. delta drives less with --quit-if-one-screen
  # --RAW-CONTROL-CHARS by default, so short output (git log/diff/show, and
  # non-diff git output it just forwards) stays on the main screen instead of
  # flashing the alternate buffer and vanishing — the behaviour the old
  # built-in `less -FRX` default no longer delivers on modern less.
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true; # n/N to jump between diff hunks
      line-numbers = true;
    };
  };

  home.file.".config/git/allowed_signers" = lib.mkIf hasSigning {
    text = ''
      ${signingEmail} ${signingKey}
    '';
  };
}

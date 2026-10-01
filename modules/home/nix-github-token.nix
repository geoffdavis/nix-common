# Home-manager module: authenticate the user's nix client for `github:`
# fetches.
#
# `nix flake update` (and any `github:owner/repo` without a rev) resolves refs
# against api.github.com. Anonymous, that is 60 requests/hour per source IP —
# shared with every other machine behind the same NAT — and it fails as:
#
#   warning: unable to download 'https://api.github.com/repos/<o>/<r>/commits/HEAD':
#   HTTP error 403 ... API rate limit exceeded for <ip>.
#
# With `access-tokens = github.com=<token>` the same calls are metered against
# the token's account (5000/hour). Flake inputs are fetched by the nix CLIENT,
# not the daemon, so the user's own ~/.config/nix/nix.conf is enough — this
# works the same on standalone HM (Ubuntu) and under nix-darwin/NixOS, with no
# root and no daemon restart.
#
# ## Shape
#
#   ~/.config/nix/nix.conf            HM-managed (store symlink), contains
#                                     `!include <tokenFile>`
#   ~/.config/nix/access-tokens.conf  0600, NOT in the store, contains
#                                     `access-tokens = github.com=<token>`
#
# `!include` (not `include`) ignores a missing file, so a host whose token
# file has not been written yet just stays anonymous instead of breaking nix.
#
# ## Populating the token file
#
# Either set `my.nixGithubToken.opRef` (written at every `switch` via
# op-file-secrets; skipped with a warning if op is locked/absent), or write it
# once by hand on hosts whose repo must not name a vault/item:
#
#   (umask 077; printf 'access-tokens = github.com=%s\n' "$(op read 'op://…')" \
#     > ~/.config/nix/access-tokens.conf)
#
# Use a fine-grained PAT with public-repo read-only access and nothing else —
# every input is public, and the token buys rate limit, not access.
#
# ## nix.package
#
# Home-manager only writes nix.conf when `nix.package` is set; it uses the
# package to validate the generated file and does NOT install it. Set one
# step BELOW mkDefault (mkOverride 1001): the package type refuses two
# definitions at equal priority, and nas-cache already sets it at mkDefault —
# so any other setter wins and this only fills the gap.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.nixGithubToken;
in {
  imports = [./op-file-secrets.nix];

  options.my.nixGithubToken = {
    enable = lib.mkEnableOption "an access token for the nix client's github: fetches";

    tokenFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.configHome}/nix/access-tokens.conf";
      defaultText = lib.literalExpression ''"''${config.xdg.configHome}/nix/access-tokens.conf"'';
      description = ''
        nix.conf fragment holding `access-tokens = github.com=<token>`,
        pulled in with `!include`. Must stay outside the nix store.
      '';
    };

    opRef = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "op://<vault>/<item>/credential";
      description = ''
        1Password reference to the BARE token. When set, tokenFile is
        rendered from it on every switch. When null, tokenFile is left for
        the user to manage (see the module header).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    nix.package = lib.mkOverride 1001 pkgs.nix;
    nix.extraOptions = ''
      !include ${cfg.tokenFile}
    '';

    op-file-secrets = lib.optional (cfg.opRef != null) {
      dest = cfg.tokenFile;
      ref = cfg.opRef;
      prefix = "access-tokens = github.com=";
      suffix = "\n";
    };
  };
}

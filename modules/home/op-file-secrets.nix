# Home-manager module: write 1Password secrets to standalone files at
# activation time.
#
# Sibling of op-json-secrets for non-JSON consumers — password files, token
# files — anywhere an application expects a secret as the entire file
# content.
#
# ## Usage
#
#   op-file-secrets = [
#     {
#       dest = "${config.home.homeDirectory}/.config/myapp/password";
#       ref = "op://MyVault/MyItem/password";
#       mode = "0600"; # default
#     }
#   ];
#
# ## Degradation contract (same as op-json-secrets)
#
# If `op` is not in PATH, or a read fails (locked vault, missing item), the
# affected file is skipped with a warning on stderr; `home-manager switch`
# never fails because of it. Existing file contents are left untouched on
# skip — stale secrets, not broken activations.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.op-file-secrets;

  fileScript = entry: ''
    _val=$($_op read ${lib.escapeShellArg entry.ref} 2>/dev/null) || _val=""
    if [ -n "$_val" ]; then
      _f=${lib.escapeShellArg entry.dest}
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$_f")"
      (umask 077; printf '%s' "$_val" > "$_f")
      ${pkgs.coreutils}/bin/chmod ${lib.escapeShellArg entry.mode} "$_f"
    else
      echo "[op-file-secrets] skipping ${entry.ref} (unavailable or empty)" >&2
    fi
  '';
in {
  options.op-file-secrets = lib.mkOption {
    default = [];
    description = ''
      Files whose entire content is a secret fetched from 1Password during
      `home-manager switch`.
    '';
    type = lib.types.listOf (lib.types.submodule {
      options = {
        dest = lib.mkOption {
          description = "Absolute path of the file to write.";
          type = lib.types.str;
        };
        ref = lib.mkOption {
          description = "1Password secret reference: `op://<vault>/<item>/<field>`.";
          type = lib.types.str;
        };
        mode = lib.mkOption {
          default = "0600";
          description = "File mode (chmod argument).";
          type = lib.types.str;
        };
      };
    });
  };

  config = lib.mkIf (cfg != []) {
    home.activation.opFileSecrets = lib.hm.dag.entryAfter ["writeBoundary"] ''
      _op=$(command -v op 2>/dev/null) || true
      # Activations run with a minimal PATH that often lacks op — a HM-as-NixOS
      # module, or standalone HM on a non-NixOS host. Fall back to well-known
      # setgid-shim locations across OSes: the NixOS wrappers, plus /usr/bin/op
      # (the Ubuntu/Debian 1Password desktop-CLI integration shim) and a
      # /usr/local manual-install path.
      if [ -z "$_op" ]; then
        for _c in /run/wrappers/bin/op /run/current-system/sw/bin/op /etc/profiles/per-user/"$USER"/bin/op /usr/bin/op /usr/local/bin/op; do
          if [ -x "$_c" ]; then
            _op="$_c"
            break
          fi
        done
      fi
      if [ -z "$_op" ]; then
        echo "[op-file-secrets] 1Password CLI not in PATH — skipping secret files" >&2
      else
        ${lib.concatMapStrings fileScript cfg}
      fi
    '';
  };
}

# Home-manager module: inject 1Password secrets into JSON config files at
# activation time.
#
# ## Why this module exists
#
# Some applications store both plain config and sensitive values (passwords,
# tokens) in the same JSON file.  Committing the file to a host repo leaks
# secrets; managing it entirely with `home.file` replaces the whole file on
# every switch, wiping runtime-generated values.  This module takes a middle
# path: it patches only the declared keys via `jq`, leaving every other key
# untouched.
#
# ## Usage
#
# 1. Add `nix-common.homeModules.op-json-secrets` to your
#    `homeManagerConfiguration.modules` list (or to a shared bundle module).
#
# 2. Declare which files and fields to patch in any module or host config that
#    is part of the same home-manager configuration:
#
#      op-json-secrets = [
#        {
#          dest = "${config.home.homeDirectory}/.config/myapp/config.json";
#          patches = [
#            { path = ".password";        ref = "op://MyVault/MyItem/password"; }
#            { path = ".db.apiKey";       ref = "op://MyVault/DBItem/api_key"; }
#            { path = ".nested.deep.key"; ref = "op://MyVault/OtherItem/token"; }
#          ];
#        }
#      ];
#
# ## How it works
#
# During `home-manager switch`, the activation script:
#   1. Looks for `op` in PATH.  Skips entirely (with a warning) if absent.
#   2. For each declared file, ensures the parent directory and an initial `{}`
#      exist so that `jq` always has a valid target.
#   3. For each patch, calls `op read <ref>` and runs:
#        jq --arg v "<secret>" '<path> = $v' config.json
#      then atomically replaces the file via a temp file.
#   4. If `op read` fails (session expired, item not found, etc.) that single
#      patch is skipped; the rest continue.
#
# ## Requirements
#
#   - 1Password CLI (`op`) must be in PATH at activation time.
#   - A valid 1Password session (biometric unlock or `op signin`).
#
# ## Static (non-secret) values
#
# Use `home.activation` with `jq` directly for values that are not sensitive.
# This module only covers fields that should come from 1Password.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.op-json-secrets;

  # Shell fragment: fetch one secret and patch $_f at the given jq path.
  patchScript = patch: ''
    _val=$($_op read ${lib.escapeShellArg patch.ref} 2>/dev/null) || _val=""
    if [ -n "$_val" ]; then
      _tmp=$(${pkgs.coreutils}/bin/mktemp)
      ${pkgs.jq}/bin/jq --arg _v "$_val" \
        ${lib.escapeShellArg "${patch.path} = \$_v"} "$_f" > "$_tmp" \
        && ${pkgs.coreutils}/bin/mv "$_tmp" "$_f"
    else
      echo "[op-json-secrets] skipping ${patch.ref} (unavailable or empty)" >&2
    fi
  '';

  # Shell fragment: prepare the target file and apply all patches for one entry.
  fileScript = entry: ''
    _f=${lib.escapeShellArg entry.dest}
    ${pkgs.coreutils}/bin/mkdir -p \
      "$(${pkgs.coreutils}/bin/dirname "$_f")"
    [ -f "$_f" ] || echo '{}' > "$_f"
    ${lib.concatMapStrings patchScript entry.patches}
  '';
in {
  options.op-json-secrets = lib.mkOption {
    default = [];
    description = ''
      JSON config files to patch with secrets fetched from 1Password during
      `home-manager switch`.

      Each entry names a destination file and a list of jq-path → op://
      reference mappings.  Secrets are merged one key at a time so unmanaged
      keys (e.g. runtime-generated tokens or local-only config) are preserved.
    '';
    type = lib.types.listOf (lib.types.submodule {
      options = {
        dest = lib.mkOption {
          description = ''
            Absolute path to the JSON file to patch.  Created as `{}` if it
            does not yet exist.
          '';
          type = lib.types.str;
        };
        patches = lib.mkOption {
          default = [];
          description = "jq-path / op:// pairs to apply to `dest`.";
          type = lib.types.listOf (lib.types.submodule {
            options = {
              path = lib.mkOption {
                description = ''
                  A jq assignment path, e.g. `.password` or `.db.apiKey`.
                  Must be a valid left-hand side for `jq … path = $v`.
                '';
                type = lib.types.str;
              };
              ref = lib.mkOption {
                description = ''
                  1Password secret reference: `op://<vault>/<item>/<field>`.
                '';
                type = lib.types.str;
              };
            };
          });
        };
      };
    });
  };

  config = lib.mkIf (cfg != []) {
    # jq is required by the activation script; pull it in automatically so
    # consumers don't have to remember to add it.
    home.packages = [pkgs.jq];

    home.activation.opJsonSecrets = lib.hm.dag.entryAfter ["writeBoundary"] ''
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
        echo "[op-json-secrets] 1Password CLI not in PATH — skipping secret injection" >&2
      else
        ${lib.concatMapStrings fileScript cfg}
      fi
    '';
  };
}

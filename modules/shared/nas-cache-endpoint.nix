# modules/shared/nas-cache-endpoint.nix — single source of truth for the
# personal NAS binary-cache endpoint (nix-personal's Harmonia instance,
# nix-personal#164). Imported by modules/nas-cache.nix (system) and
# modules/home/nas-cache.nix (standalone home-manager) so the URL and the
# signing key can never drift between them.
#
# Not a module and not a flake export — a plain attrset, per the
# modules/shared/ internal-helper convention.
{
  # Harmonia HTTP endpoint. The netbird overlay name resolves both at home
  # (WireGuard takes the LAN path) and away — no separate LAN entry needed.
  cacheUrl = "http://nas-sdg.netbird.cloud:30500";

  # Public half of the cache signing key.
  # Derived from: op read "op://nas-overlay/nix-cache-signing-key/password" \
  #   | nix key convert-secret-to-public
  cachePublicKey = "nas-sdg-nix-cache-1:5FXUg5ik7av8CDnsngWpuM2Xe9RJ3WYoewH6t+rt9mo=";
}

# modules/nas-cache.nix — NAS-hosted Nix binary cache + x86_64-linux remote
# builder (native NixOS services on nas-sdg since the TrueNAS→NixOS cutover;
# server side lives in nix-personal, modules/nas/nix-cache.nix — Harmonia on
# :30500 + the dedicated `nix-remote-builder` ssh-ng user, nix-personal#164).
#
# Imported as nixosModules.nas-cache or darwinModules.nas-cache. Platform-
# agnostic: only touches nix.settings / nix.distributedBuilds /
# nix.buildMachines / programs.ssh.extraConfig — present in both NixOS and
# nix-darwin system modules. For standalone home-manager on Linux use
# homeModules.nas-cache instead (substituter only; buildMachines is not a
# home-manager option).
#
# One-time per-client setup (the nix-daemon runs as root):
#   sudo ssh-keygen -t ed25519 -N "" -f /etc/nix/builder_ed25519 \
#     -C "nix-builder@$(hostname -s)"
#   # add the .pub to my.nixCache.builderKeys in nix-personal
#   # hosts/nas-sdg/default.nix and deploy nas-sdg
{lib, ...}: let
  # Harmonia HTTP endpoint. The netbird overlay name resolves both at home
  # (WireGuard takes the LAN path) and away — no separate LAN entry needed.
  cacheUrl = "http://nas-sdg.netbird.cloud:30500";

  # Public half of the cache signing key.
  # Derived from: op read "op://nas-overlay/nix-cache-signing-key/password" \
  #   | nix key convert-secret-to-public
  cachePublicKey = "nas-sdg-nix-cache-1:5FXUg5ik7av8CDnsngWpuM2Xe9RJ3WYoewH6t+rt9mo=";

  # Builder sshd host key — pinned so root's nix-daemon never hits an
  # interactive host-key prompt. This is nas-sdg's REAL host key (salvaged
  # across the NixOS migration, so it is stable); the old value was the
  # dissolved nix-cache container's own sshd key. base64 of the pubkey line
  # (type + key, no comment):
  #   ssh-keyscan -t ed25519 nas-sdg.netbird.cloud 2>/dev/null \
  #     | awk '{printf "%s %s", $2, $3}' | base64
  builderPublicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUV2YzgwdFcrNEhMNW9mb0kzRkduVk1XT3ByZHN3cjhyZitNNzFCRys0UDU=";
in {
  config = lib.mkMerge [
    # Substitution: pull paths the NAS has already built instead of rebuilding.
    # Harmonia priority 50 keeps cache.nixos.org (40) preferred; the NAS
    # supplements with our own builds.
    (lib.mkIf (cachePublicKey != null) {
      nix.settings = {
        extra-substituters = [cacheUrl];
        extra-trusted-public-keys = [cachePublicKey];
      };
    })

    # Remote builder: offload x86_64-linux derivations to the NAS. The big
    # win is on aarch64-darwin (windansea and other Apple-silicon laptops —
    # native x86_64 builds); on birdrock it adds spillover capacity.
    (lib.mkIf (builderPublicHostKey != null) {
      nix = {
        distributedBuilds = true;
        settings.builders-use-substitutes = true;
        buildMachines = [
          {
            # Alias resolved by the ssh config below — buildMachines has no
            # port field, so the alias carries HostName + Port + key.
            hostName = "nix-builder-nas-sdg";
            systems = ["x86_64-linux"];
            protocol = "ssh-ng";
            sshUser = "nix-remote-builder";
            sshKey = "/etc/nix/builder_ed25519";
            maxJobs = 4;
            speedFactor = 1;
            supportedFeatures = ["big-parallel"];
            publicHostKey = builderPublicHostKey;
          }
        ];
      };

      # System-level ssh config — root's nix-daemon never sees user-level
      # ~/.ssh/config or the 1Password agent.
      programs.ssh.extraConfig = ''
        Host nix-builder-nas-sdg
          HostName nas-sdg.netbird.cloud
          Port 22
          User nix-remote-builder
          IdentityFile /etc/nix/builder_ed25519
          IdentitiesOnly yes
          # nix pins publicHostKey in a temp known_hosts under the MACHINE
          # name; without HostKeyAlias, ssh looks up [nas-sdg.netbird.cloud]:30222
          # instead, misses the pin, and dies at the interactive prompt —
          # the daemon has no TTY.
          HostKeyAlias nix-builder-nas-sdg
      '';
    })
  ];
}

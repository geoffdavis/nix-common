# modules/nas-cache.nix — NAS-hosted Nix binary cache + x86_64-linux remote
# builder (the `nix-cache` TrueNAS app on nas-sdg; server side lives in the
# ugreen-nas-compose repo, ansible/roles/truenas_nix_cache_app/).
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
#   # add the .pub to truenas_nix_cache_app_authorized_keys in
#   # ugreen-nas-compose host_vars/nas-sdg.yml and re-run
#   # ansible/playbooks/truenas-nix-cache-app.yml
{lib, ...}: let
  # Harmonia HTTP endpoint. The netbird overlay name resolves both at home
  # (WireGuard takes the LAN path) and away — no separate LAN entry needed.
  cacheUrl = "http://nas-sdg.netbird.cloud:30500";

  # Public half of the cache signing key.
  # Derived from: op read "op://nas-overlay/nix-cache-signing-key/password" \
  #   | nix key convert-secret-to-public
  cachePublicKey = "nas-sdg-nix-cache-1:5FXUg5ik7av8CDnsngWpuM2Xe9RJ3WYoewH6t+rt9mo=";

  # Builder sshd host key — pinned so root's nix-daemon never hits an
  # interactive host-key prompt. base64 of the pubkey line (type + key, no
  # comment):
  #   ssh truenas_admin@nas-sdg \
  #     "sudo cat /mnt/tank/nix-cache/ssh/ssh_host_ed25519_key.pub" | base64
  builderPublicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUV0dHFIbTNRUXgydnBnT3h4d3RKZjE2WTh5cmszSGQxMVlZK2VsSFhwMGk=";
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
            sshUser = "root";
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
          Port 30222
          User root
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

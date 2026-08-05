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
# IMPORT-IS-OPT-IN: base/profile module — importing it IS the enable;
# config applies unconditionally (module-contract.md, "Two module classes").
{pkgs, ...}: let
  # cacheUrl + cachePublicKey live in the shared endpoint file so this module
  # and homeModules.nas-cache can never drift apart.
  inherit (import ./shared/nas-cache-endpoint.nix) cacheUrl cachePublicKey;

  # Builder sshd host key — pinned so root's nix-daemon never hits an
  # interactive host-key prompt. This is nas-sdg's REAL host key (salvaged
  # across the NixOS migration, so it is stable); the old value was the
  # dissolved nix-cache container's own sshd key. base64 of the pubkey line
  # (type + key, no comment):
  #   ssh-keyscan -t ed25519 nas-sdg.netbird.cloud 2>/dev/null \
  #     | awk '{printf "%s %s", $2, $3}' | base64
  builderPublicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUV2YzgwdFcrNEhMNW9mb0kzRkduVk1XT3ByZHN3cjhyZitNNzFCRys0UDU=";

  # nas-sdg's host key in known_hosts wire form, decoded from the single-source
  # base64 above (no second literal to drift out of sync). nix's remote-BUILD
  # path injects builderPublicHostKey via a temp known_hosts on the fly, but a
  # plain `nix copy --to ssh-ng://…` — e.g. cache-push's post-build-hook — has
  # no such injection, and the nix-daemon runs with no HOME (so no user
  # known_hosts). Pin the key here, keyed on the HostKeyAlias, so that plain-ssh
  # copy can verify the host instead of dying at "failed to start SSH connection".
  builderKnownHosts = pkgs.runCommand "nix-builder-nas-sdg.known_hosts" {} ''
    printf 'nix-builder-nas-sdg %s\n' "$(printf %s '${builderPublicHostKey}' | base64 -d)" > "$out"
  '';
in {
  config = {
    # Substitution: pull paths the NAS has already built instead of rebuilding.
    # Harmonia priority 50 keeps cache.nixos.org (40) preferred; the NAS
    # supplements with our own builds.
    #
    # Remote builder: offload x86_64-linux derivations to the NAS. The big
    # win is on aarch64-darwin (windansea and other Apple-silicon laptops —
    # native x86_64 builds); on birdrock it adds spillover capacity.
    nix = {
      settings = {
        extra-substituters = [cacheUrl];
        extra-trusted-public-keys = [cachePublicKey];
        builders-use-substitutes = true;
      };
      distributedBuilds = true;
      buildMachines = [
        {
          # Alias resolved by the ssh config below — buildMachines has no
          # port field, so the alias carries HostName + Port + key.
          hostName = "nix-builder-nas-sdg";
          # aarch64-linux is EMULATED on nas-sdg (boot.binfmt.emulatedSystems),
          # not native. Listed so aarch64-DARWIN clients — which cannot build
          # aarch64-linux at all — have somewhere to send a Raspberry Pi
          # closure; without it there is nowhere in the fleet to build one.
          #
          # Cheap in practice: aarch64-linux is a first-class Hydra platform,
          # so packages substitute prebuilt and only trivial per-host
          # derivations execute under qemu. A host that pins a NON-cached
          # kernel (e.g. nixos-hardware's linux-rpi) would instead compile it
          # emulated, which is hours — pin mainline on aarch64 hosts.
          #
          # If this ever gets slow, the fix is a NATIVE aarch64 builder as an
          # additional buildMachines entry, not a redesign.
          systems = ["x86_64-linux" "aarch64-linux"];
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
        # Fast-fail when the netbird overlay is down (laptop off-VPN): the
        # cache-push post-build-hook relies on `nix copy` connecting or
        # failing quickly so a build never stalls on a dead cache. Also
        # bounds remote-build offload when nas-sdg is unreachable.
        ConnectTimeout 4
        # nix pins publicHostKey in a temp known_hosts under the MACHINE
        # name; without HostKeyAlias, ssh looks up [nas-sdg.netbird.cloud]:30222
        # instead, misses the pin, and dies at the interactive prompt —
        # the daemon has no TTY.
        HostKeyAlias nix-builder-nas-sdg
        # Pin nas-sdg's host key for plain-ssh `nix copy` (cache-push). nix's
        # remote-BUILD ssh passes its own -oUserKnownHostsFile on the command
        # line, which overrides this, so builds are unaffected.
        UserKnownHostsFile ${builderKnownHosts}
    '';
  };
}

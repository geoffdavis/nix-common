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
#   # add the .pub to my.nixCache.builderKeys in nix-personal on EVERY builder
#   # host that should accept it (hosts/nas-sdg, hosts/nas-sct) and deploy them
#
# The same client key authorises against every builder — builderKeys is a
# per-SERVER allow-list, so a client added to one builder and not another
# fails only against the one it was missed on, and only under load, when the
# scheduler first reaches for the second builder.
#
# IMPORT-IS-OPT-IN: base/profile module — importing it IS the enable;
# config applies unconditionally (module-contract.md, "Two module classes").
{
  config,
  pkgs,
  ...
}: let
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

  # torrey's sshd host key. Same derivation as above:
  #   ssh-keyscan -t ed25519 torrey.netbird.cloud 2>/dev/null \
  #     | awk '{printf "%s %s", $2, $3}' | base64
  #
  # NOT salvaged and NOT escrow-planted: torrey generated this itself at first
  # boot, because it was provisioned by switching a booted installer in place
  # rather than from a pre-baked image. It lives on torrey's SD card, which is
  # also its boot medium — reflash that card and this literal must be updated
  # (nix-personal escrows the private half as ssh-host-key-torrey).
  torreyPublicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUZMbW5BTmJCMHBjbG4vZmRQUHV6dytTZTJFZDNVODBiZElpRU5KZXp2UzE=";

  torreyKnownHosts = pkgs.runCommand "nix-builder-torrey.known_hosts" {} ''
    printf 'nix-builder-torrey %s\n' "$(printf %s '${torreyPublicHostKey}' | base64 -d)" > "$out"
  '';

  # nas-sct's sshd host key. Same derivation as the two above — note the
  # `grep -v '^#'`, which the older recipes omit: modern ssh-keyscan writes a
  # banner comment to stdout, and without the filter the base64 silently
  # captures "nas-sct.netbird.cloud:22 SSH-2.0-OpenSSH_10.4ssh-ed25519 …"
  # instead of the key. That decodes to a plausible-looking string and fails
  # only later, at host-key verification.
  #
  #   ssh-keyscan -t ed25519 nas-sct.netbird.cloud 2>/dev/null \
  #     | grep -v '^#' | grep ssh-ed25519 | head -1 \
  #     | awk '{printf "%s %s", $2, $3}' | base64 -w0
  #
  # sct generated this itself at bring-up (2026-07-05, the TrueNAS→NixOS
  # migration). It is NOT escrowed — see nix-personal task #21. Reinstalling
  # the host regenerates it and this literal must be updated.
  sctPublicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUZLaGs1RG84cG1LaWVjZmZNNmxDWlFxeHFMZ0k1WkRZM0JxV0pIc0ZrR2E=";

  sctKnownHosts = pkgs.runCommand "nix-builder-nas-sct.known_hosts" {} ''
    printf 'nix-builder-nas-sct %s\n' "$(printf %s '${sctPublicHostKey}' | base64 -d)" > "$out"
  '';

  # tourmaline's sshd host key. Same derivation as the others, including the
  # `grep -v '^#'` that modern ssh-keyscan needs (its banner otherwise lands in
  # the base64 and decodes to something plausible that fails at verification):
  #
  #   ssh-keyscan -t ed25519 tourmaline.netbird.cloud 2>/dev/null \
  #     | grep -v '^#' | grep ssh-ed25519 | head -1 \
  #     | awk '{printf "%s %s", $2, $3}' | base64 -w0
  tourmalinePublicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSU1wQmFqcndFYzRSL1hFNUNsamsxWGxqYTQvQVJwSklxUGRJdytySWZ0aWM=";

  tourmalineKnownHosts = pkgs.runCommand "nix-builder-tourmaline.known_hosts" {} ''
    printf 'nix-builder-tourmaline %s\n' "$(printf %s '${tourmalinePublicHostKey}' | base64 -d)" > "$out"
  '';

  # This host's own builder alias, or null if it cannot be determined.
  #
  # MUST tolerate null: this module is imported on nix-darwin too, where
  # `networking.hostName` is `nullOr str` and defaults to NULL — the darwin
  # consumers do not set it. Interpolating that straight into a string throws
  # at EVALUATION time ("cannot coerce null to a string"), so an unguarded
  # `"nix-builder-${config.networking.hostName}"` breaks every darwin host
  # that imports this module, which is exactly the set of clients the nas-sct
  # entry below is most meant to help.
  #
  # Null is harmless for the filter's purpose: no darwin host is a builder,
  # so there is nothing to exclude.
  selfBuilderAlias =
    if (config.networking.hostName or null) == null || config.networking.hostName == ""
    then null
    else "nix-builder-${config.networking.hostName}";
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
      # A host must never appear in its OWN buildMachines. Before this filter
      # the list happened to contain no host that also imports this module, so
      # the hazard was latent rather than absent; adding nas-sct — which DOES
      # import it (nix-personal flake.nix, nasSctModules) — makes it live.
      #
      # Self-offload is not a hard error, it is a silent one: nix would ssh to
      # localhost-by-another-name, hand the derivation to the same daemon, and
      # pay a network round trip plus a store copy to build exactly where it
      # started. Slow instead of broken.
      #
      # nas-sdg avoids this by not importing the module at all (its flake
      # comment: "pointing it at its own harmonia would be circular"); torrey
      # avoids it with `nix.distributedBuilds = lib.mkForce false`. This filter
      # is the general form, so a future builder that also imports nas-cache
      # gets it for free.
      buildMachines =
        builtins.filter
        (m: selfBuilderAlias == null || m.hostName != selfBuilderAlias)
        [
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
            #
            # armv7l-linux is a DIFFERENT proposition and the paragraph above
            # does NOT extend to it. It exists for windowpi, a Raspberry Pi 2
            # (32-bit only, no aarch64 path) that serves the house's stratum-1
            # GPS time — see nix-personal#340. There is no armv7l binary cache
            # AT ALL: cache.nixos.org 404s on armv7l `hello`, not merely on
            # exotic packages. So every derivation in that closure, including
            # stdenv, GCC and the RPi vendor kernel, compiles under qemu. Expect
            # the first build to run for hours. It is a one-time cost only
            # because nas-sdg's Harmonia serves its own store, so the fleet
            # substitutes the results afterwards.
            systems = ["x86_64-linux" "aarch64-linux" "armv7l-linux"];
            protocol = "ssh-ng";
            sshUser = "nix-remote-builder";
            sshKey = "/etc/nix/builder_ed25519";
            maxJobs = 4;

            # RAISED FROM 1 to 2 when nas-sct joined as a second x86_64 builder.
            #
            # nix prefers the HIGHEST speedFactor with a free slot, and
            # speedFactor has no value below 1 — so making sct strictly
            # lower-preference than sdg requires raising sdg rather than
            # lowering sct. sdg is an i5-1235U (12 threads, P-cores); sct is an
            # N100 (4 E-cores) that will sit at the far end of a WAN link. sdg
            # should win every time both are free.
            #
            # CHECK BEFORE CHANGING AGAIN: torrey is 3, and the comment on its
            # entry below explains why it MUST outrank this one — both advertise
            # aarch64-linux and armv7l-linux, and torrey's are native while
            # these are qemu. 3 > 2 still holds. Raising this above 3 would
            # silently route native ARM work to the emulator.
            speedFactor = 2;
            # gccarch-armv7-a is REQUIRED and listing armv7l-linux above is not
            # sufficient on its own — this bit is easy to miss twice.
            #
            # nixpkgs tags the armv7l stdenv with
            # `requiredSystemFeatures = ["gccarch-armv7-a"]`, derived from the
            # armv7l-hf-multiplatform platform's gcc.arch. Nix only dispatches a
            # derivation to a builder whose supportedFeatures COVER its
            # requiredSystemFeatures, so without this entry a client would match
            # on `systems`, then refuse to offload, and fall over with
            # "a 'armv7l-linux' is required, but I am a 'x86_64-linux'".
            #
            # The same trap exists one layer down on the builder itself:
            # boot.binfmt.emulatedSystems grants the PLATFORM but not the
            # microarchitecture feature, so nas-sdg also sets
            # nix.settings.system-features = ["gccarch-armv7-a"]. Both halves are
            # needed; either alone produces a host that advertises armv7l and
            # then refuses to build it.
            supportedFeatures = ["big-parallel" "gccarch-armv7-a"];
            publicHostKey = builderPublicHostKey;
          }
          {
            # torrey — the NATIVE ARM builder (nix-personal#351). A Raspberry
            # Pi 5 whose Cortex-A76 implements AArch32 at EL0, verified on the
            # hardware:
            #
            #   [    0.154620] CPU features: detected: 32-bit EL0 Support
            #
            # so armv7l runs on the CPU rather than through qemu. This is the
            # entry the nas-sdg comment above anticipates when it says "the fix
            # is a NATIVE aarch64 builder as an additional buildMachines entry,
            # not a redesign".
            hostName = "nix-builder-torrey";

            # No x86_64-linux: torrey cannot build it, natively or otherwise.
            # nas-sdg remains the only x86 builder and keeps that traffic.
            systems = ["aarch64-linux" "armv7l-linux"];
            protocol = "ssh-ng";
            sshUser = "nix-remote-builder";
            sshKey = "/etc/nix/builder_ed25519";

            # 4 cores, 8 GB. Modest against nas-sdg's 12 threads, but these are
            # real ARM cores rather than emulated ones.
            maxJobs = 2;

            # HIGHER THAN NAS-SDG (1), and that is the whole point of this
            # entry. Both machines advertise aarch64-linux and armv7l-linux, so
            # without a speed preference nix could hand native ARM work to the
            # emulator — silently, and hours slower. speedFactor is what makes
            # the native path win.
            # RAISED 3 -> 4 when nas-sct joined and nas-sdg went 1 -> 2.
            #
            # The tiers are now, top to bottom:
            #   4  torrey           native ARM, dedicated builder
            #   3  talos k8s nodes  native ARM, but with a day job (nix-personal)
            #   2  nas-sdg          EMULATED ARM / native x86_64
            #   1  nas-sct          native x86_64, overflow, possibly over a WAN
            #
            # Raising nas-sdg to 2 without also lifting this and the talos entries
            # would have collapsed native ARM and emulated ARM into ONE tier,
            # letting qemu win aarch64 work on a tie-break. That costs hours,
            # silently — the exact inversion these comments exist to prevent.
            speedFactor = 4;

            # gccarch-armv7-a for the reason spelled out at length above: the
            # platform alone is not enough, nix matches requiredSystemFeatures.
            # torrey supplies the other half itself via
            # nix.settings.system-features (nix-personal hosts/torrey/builder.nix).
            #
            # gccarch-armv8-a because this really is armv8 hardware — nas-sdg
            # cannot honestly claim that, since its aarch64 is qemu.
            supportedFeatures = ["big-parallel" "gccarch-armv7-a" "gccarch-armv8-a"];
            publicHostKey = torreyPublicHostKey;
          }
          {
            # nas-sct — a SECOND native x86_64-linux builder.
            #
            # The capacity argument is the weaker one: an N100's 4 E-cores will
            # not rival nas-sdg's 12 threads, and this entry is deliberately
            # ranked below it.
            #
            # The AVAILABILITY argument is the real one. Until now nas-sdg was
            # the fleet's ONLY x86_64-linux builder, and the darwin hosts have
            # no local x86_64-linux path at all — when sdg is down or saturated
            # they simply cannot build x86_64-linux, which surfaces as
            # "Failed to find a machine for remote build!". A second endpoint
            # removes that single point of failure.
            #
            # It also lands where the work is going: if the windowpi image moves
            # to a cross build (nix-personal, evaluated 2026-08-09 — 668
            # derivations, 100% x86_64-linux, versus 938 native armv7l), the
            # fleet's largest build becomes an x86_64 workload and x86_64
            # capacity stops being spare and starts being the bottleneck.
            hostName = "nix-builder-nas-sct";

            # x86_64-linux ONLY, and deliberately so. sct could run
            # boot.binfmt.emulatedSystems like sdg does, but a SECOND emulated
            # aarch64/armv7l endpoint is worse than none: it would advertise
            # platforms it can only emulate, and at speedFactor 1 it would be
            # picked up as overflow precisely when the native builders are busy
            # — sending ARM work over a WAN to a qemu that is slower than
            # waiting. Native x86_64 is the only thing this host is genuinely
            # good at, so it advertises only that.
            systems = ["x86_64-linux"];
            protocol = "ssh-ng";
            sshUser = "nix-remote-builder";
            sshKey = "/etc/nix/builder_ed25519";

            # 4 cores / 15 GB, but this is an appliance with a day job: a
            # FreeIPA replica VM, five gh-runners, a ZFS replication target and
            # the fleet observability agents. 2 leaves headroom so a build storm
            # cannot starve a syncoid pull or stall the replica.
            maxJobs = 2;

            # LOWEST of the three, which is the entire scheduling intent: this
            # is OVERFLOW, not a peer of nas-sdg. See the note on sdg's
            # speedFactor above for why sdg was raised to 2 rather than this
            # lowered — 1 is the floor.
            #
            # This also bounds the WAN exposure once sct ships to its remote
            # site: work only crosses the link when the local builder is
            # already full.
            speedFactor = 1;

            # No gccarch-armv7-a: that feature exists for the emulated armv7l
            # path, which this host does not offer. big-parallel alone matches
            # what an x86_64-only builder can honestly claim.
            supportedFeatures = ["big-parallel"];
            publicHostKey = sctPublicHostKey;
          }
          {
            # tourmaline — a SECOND native armv7l builder, deliberately ranked as
            # OVERFLOW behind torrey rather than as a peer.
            #
            # Its Cortex-A72 implements AArch32 at EL0, same as torrey's A76, and
            # it advertises gccarch-armv7-a — so armv7l runs on the CPU, not
            # through qemu. Verified on the host, not assumed.
            hostName = "nix-builder-tourmaline";

            # armv7l-linux ONLY, and NOT aarch64-linux. It is capable of aarch64
            # natively, but aarch64 has better homes — torrey and the cluster
            # nodes — and advertising it here would let this box take work those
            # should do first. armv7l is the scarce capability: only two machines
            # in the fleet execute it natively; everything else is qemu.
            systems = ["armv7l-linux"];
            protocol = "ssh-ng";
            sshUser = "nix-remote-builder";
            sshKey = "/etc/nix/builder_ed25519";

            # 3, from cores and memory — not from thermals or the appliance
            # role, both of which appear in older comments and neither of which
            # is currently binding.
            #
            # The host sets `cores = 3`, so maxJobs 3 means up to 9 compiler
            # processes across 4 cores. Oversubscribed, but that is ordinary for
            # make-style parallelism and keeps cores busy through I/O waits.
            #
            # Memory is the real ceiling: 3.7 GiB RAM with 3.7 GiB of zstd zram
            # and NO disk swap — correct on a Pi, where spilling to SD or the
            # intermittent USB-SATA path costs more than compression does.
            #
            # zram is RAM-backed, so it buys COMPRESSION (2-3x on build
            # artefacts), not headroom. It cannot rescue one job with a 3 GiB
            # resident set; what it does is make several MODEST parallel jobs
            # viable where they would otherwise thrash. So the failure mode to
            # design against is not OOM, it is unresponsiveness under swap
            # pressure — and a wedged box is worse for the print queue and UPS
            # monitoring than a slow one.
            #
            # 3 rather than 4 reserves headroom for exactly that: one heavy
            # translation unit (an armv7l LLVM build has several) can spike
            # without the box becoming unresponsive. The marginal throughput of
            # a 4th job on 4 already-oversubscribed cores is small; the
            # additional swap pressure is not.
            maxJobs = 3;

            # BELOW torrey's 4, which is the entire point: torrey is the box built
            # for armv7l and fills first, this absorbs the spill. ABOVE nas-sdg's
            # 2 because that machine's armv7l is EMULATED, and native must outrank
            # qemu — the same invariant torrey's entry protects.
            #
            #   4 torrey       native armv7l + aarch64, dedicated builder
            #   3 tourmaline   native armv7l, also a print/UPS appliance
            #   2 nas-sdg      EMULATED armv7l/aarch64, native x86_64
            #   1 nas-sct      native x86_64 overflow
            speedFactor = 3;

            # gccarch-armv7-a is required, not decorative: nixpkgs tags the armv7l
            # stdenv with it as a requiredSystemFeature, so a builder advertising
            # the platform without the feature is matched and then refuses every
            # build. gccarch-armv8-a because this really is armv8 hardware.
            supportedFeatures = ["big-parallel" "gccarch-armv7-a" "gccarch-armv8-a"];
            publicHostKey = tourmalinePublicHostKey;
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

      Host nix-builder-torrey
        HostName torrey.netbird.cloud
        Port 22
        User nix-remote-builder
        IdentityFile /etc/nix/builder_ed25519
        IdentitiesOnly yes
        # Same fast-fail rationale as nas-sdg above, and it matters more
        # here: torrey is an appliance on a home VLAN reached over the
        # overlay, so an off-VPN laptop must give up quickly rather than
        # stall every build waiting on a builder it cannot see.
        ConnectTimeout 4
        HostKeyAlias nix-builder-torrey
        UserKnownHostsFile ${torreyKnownHosts}

      Host nix-builder-nas-sct
        HostName nas-sct.netbird.cloud
        Port 22
        User nix-remote-builder
        IdentityFile /etc/nix/builder_ed25519
        IdentitiesOnly yes
        # Same fast-fail rationale as the two above, and it is load-bearing
        # here rather than merely tidy: sct is the one builder that will sit
        # at the far end of a WAN link once it ships to its remote site. A
        # client that cannot reach it must give up in seconds and use the
        # local builder, not stall every dispatch waiting on a link that is
        # down or saturated.
        ConnectTimeout 4
        HostKeyAlias nix-builder-nas-sct
        UserKnownHostsFile ${sctKnownHosts}

      Host nix-builder-tourmaline
        HostName tourmaline.netbird.cloud
        Port 22
        User nix-remote-builder
        IdentityFile /etc/nix/builder_ed25519
        IdentitiesOnly yes
        ConnectTimeout 4
        HostKeyAlias nix-builder-tourmaline
        UserKnownHostsFile ${tourmalineKnownHosts}

      Host nix-cache-push-nas-sdg
        HostName nas-sdg.netbird.cloud
        Port 22
        # A DIFFERENT user than nix-builder-nas-sdg above, deliberately:
        # nix-remote-builder is trusted for remote builds, but cache-push
        # (modules/cache-push.nix) only ever needs to drop NARs into the
        # file cache. nix-cache-push is scoped to exactly that via a
        # forced command in its authorized_keys on nas-sdg (server side,
        # nix-personal#353) — this alias carries no destination path, the
        # server pins it.
        User nix-cache-push
        IdentityFile /etc/nix/builder_ed25519
        IdentitiesOnly yes
        ConnectTimeout 4
        # Same physical host as nix-builder-nas-sdg above, so its pinned
        # HostKeyAlias/known_hosts verify here too — reusing them means one
        # less literal that could drift out of sync.
        HostKeyAlias nix-builder-nas-sdg
        UserKnownHostsFile ${builderKnownHosts}

      # ── liveness for connections that are ALREADY UP ──────────────────
      #
      # ConnectTimeout above only bounds the HANDSHAKE. It does nothing once
      # a session is established, and that is the case that actually bit us.
      #
      # 2026-08-08, nix-personal#351: torrey went silent ~2h45m into an
      # armv7l image build. The box was gone -- no network, silent serial
      # console, recovered only by cycling its PoE port. The BUILD, however,
      # sat there for 48 minutes with its log frozen at the exact second of
      # the stall, `nix` still alive and blocked on a TCP socket whose peer
      # no longer existed. It never errored, never retried, never gave up;
      # it simply looked healthy while doing nothing. It had to be killed by
      # hand, and until it was, monitoring reported the build as running.
      #
      # A hung build is worse than a failed one: a failure is visible and
      # retryable, and nix would have rescheduled the derivation.
      #
      # ServerAliveInterval sends an encrypted channel request on an idle
      # connection and requires a reply. Three unanswered probes at 15s
      # tears the session down in ~45s, so a dead builder surfaces as an
      # error while the build can still do something about it. TCP's own
      # keepalive is not a substitute -- its default idle timer is two
      # hours, which is the same as "never" for this purpose.
      #
      # This matters MORE as builders multiply. The RPi5 hardware this fleet
      # builds on suffers a silent macb/RP1 stall, mitigated elsewhere by a
      # watchdog that toggles the link and recovers in 30-40s, so a
      # builder briefly vanishing is an expected event, not a rare one. A
      # builder that recovers in 40 seconds is worth nothing if the client
      # never notices it left.
      #
      # Applied by wildcard so it covers every builder and cache-push alias
      # above, and any added later -- the failure mode is a property of
      # "long-lived ssh to a fleet host", not of any one machine. Placed
      # last: ssh_config takes the FIRST value seen for a keyword, so the
      # specific stanzas above keep precedence for anything they set.
      Host nix-builder-* nix-cache-push-*
        ServerAliveInterval 15
        ServerAliveCountMax 3
    '';
  };
}

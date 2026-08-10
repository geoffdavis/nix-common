# modules/darwin/netbird-ssh-config.nix — stop the NetBird app generating an
# ssh_config block, and remove the one it already generated. Darwin only.
#
# WHAT IT GENERATES. The app writes /etc/ssh/ssh_config.d/99-netbird.conf
# containing, on one line, every overlay peer:
#
#   Match host "…,<peer>.netbird.cloud,<peer>,…" exec "netbird ssh detect %h %p"
#       PreferredAuthentications password,publickey,keyboard-interactive
#       PasswordAuthentication yes
#       ProxyCommand /…/netbird ssh proxy %h %p
#       StrictHostKeyChecking no
#       UserKnownHostsFile /dev/null
#
# Two independent defects; the second is the reason to remove it rather than
# tolerate it.
#
# 1. THE `exec` RUNS ON EVERY CONNECTION. A `Match … exec` invokes its command
#    to EVALUATE the condition, so `netbird ssh detect` runs whether or not the
#    match ultimately applies — and it opens an ssh connection, completes the
#    version exchange, then disconnects WITHOUT authenticating. Measured
#    against a fleet builder: ~2 such connections per successful dispatch,
#    arriving immediately before it (source ports ascend; the authenticated one
#    always holds the highest port in each group). Reproduced directly:
#
#      $ netbird ssh detect <peer>.netbird.cloud 22
#      server: Connection closed by <addr> port 49282 [preauth]
#
#    OpenSSH ≥9.8 classifies connect-without-authenticating as abuse and
#    penalises the SOURCE ADDRESS, dropping the legitimate connections with it.
#    It surfaces as "failed to start SSH connection to <builder>" — an
#    auth-shaped error for something that is not an auth problem.
#
# 2. IT DISABLES HOST-KEY VERIFICATION. `StrictHostKeyChecking no` plus
#    `UserKnownHostsFile /dev/null` sit in ROOT's ssh config on a machine that
#    builds and signs store paths. They are inert only by accident of which
#    Match condition happens to fire; a rename, or a peer list that grows to
#    cover an alias, silently turns host-key checking off.
#
#    THIS IS WHY THE MODULE MUST DELETE THE EXISTING FILE, not merely stop
#    future generation. Suppressing generation on a Mac that already has the
#    file changes nothing at all — the block keeps being loaded on every ssh,
#    indefinitely. An earlier revision of this module only warned about it,
#    which left its own headline argument unaddressed.
#
# WHY DARWIN ONLY. The generated file is identical on both platforms, but
# whether root's ssh LOADS it is not:
#
#   darwin  /etc/ssh/ssh_config:  Include /etc/ssh/ssh_config.d/*   (Apple default)
#   NixOS   /etc/ssh/ssh_config:  includes only systemd's ssh_config.d entry
#
# So on NixOS root never sees the block and nothing goes wrong; on darwin the
# nix-daemon's ssh reads it on every remote build. Do not assume the platforms
# behave alike here — that assumption is what hid this.
#
# NOT THE SAME AS THE CONSOLE'S "allow SSH" SETTING. Turning that off in the
# NetBird console does NOT remove or rewrite this file — verified on a live
# host, unchanged afterwards. The console governs the peer's ssh SERVER;
# NB_DISABLE_SSH_CONFIG governs client-side config generation. Only the two
# together, plus deleting what is already on disk, actually clear it.
#
# NOTHING IS LOST. The ProxyCommand is redundant when the overlay already
# provides direct addressing: NixOS fleet hosts have never loaded this block
# and reach every peer by name regardless. Per-host ssh settings for overlay
# peers are declared explicitly by consumers (see nas-cache), which is also
# the only place host keys are pinned.
{
  config,
  lib,
  ...
}: let
  cfg = config.my.netbirdSshConfig;
  generated = "/etc/ssh/ssh_config.d/99-netbird.conf";
in {
  options.my.netbirdSshConfig.enable = lib.mkEnableOption ''
    suppression of the NetBird app's ssh_config generation.

    Sets `NB_DISABLE_SSH_CONFIG=true` on the NetBird service so it stops
    writing ${generated}, and removes that file if it is already present —
    stopping generation alone would leave an existing block loaded forever.

    ONE-WAY. Setting this back to false stops MANAGING the setting; it does
    not un-persist the service env or restore the file, because
    `service reconfigure` writes into the service definition and this module
    keeps no record of the prior value. To reverse deliberately:

      netbird service reconfigure --service-env NB_DISABLE_SSH_CONFIG=false

    and restart the service to regenerate the file. That asymmetry is
    intentional — reconciling a `false` state would mean re-enabling a
    host-key bypass, which is not something a module should do implicitly.
  '';

  config = lib.mkIf cfg.enable {
    system.activationScripts.postActivation.text = lib.mkAfter ''
      # NetBird ssh_config suppression. Guarded on the binary existing so a
      # Mac without the app activates cleanly.
      nbBin=/Applications/NetBird.app/Contents/MacOS/netbird
      if [ -x "$nbBin" ]; then
        # Only reconfigure when the setting is not already applied: the call
        # restarts the service, so doing it unconditionally would bounce the
        # overlay on every switch.
        if "$nbBin" service config 2>/dev/null | grep -q 'NB_DISABLE_SSH_CONFIG=true'; then
          nbSuppressed=1
        else
          echo "netbird: disabling ssh_config generation (NB_DISABLE_SSH_CONFIG=true)"
          if "$nbBin" service reconfigure --service-env NB_DISABLE_SSH_CONFIG=true; then
            nbSuppressed=1
          else
            nbSuppressed=0
            echo "netbird: reconfigure FAILED — leaving ${generated} in place" >&2
          fi
        fi

        # Remove the already-generated block, but ONLY once generation is
        # confirmed off. Deleting it while the service would still rewrite it
        # turns every activation into a fight for ownership — the file would
        # reappear, and the deletion would look effective while changing
        # nothing. Idempotent: absent file is the success case.
        if [ "$nbSuppressed" = 1 ] && [ -e ${generated} ]; then
          echo "netbird: removing generated ${generated} (Match exec + host-key bypass)"
          rm -f ${generated}
        fi
      fi
    '';
  };
}

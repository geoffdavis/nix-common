# modules/darwin/netbird-ssh-config.nix — stop the NetBird app generating an
# ssh_config block, on darwin only.
#
# WHAT IT GENERATES, and why it is a problem here. The app writes
# /etc/ssh/ssh_config.d/99-netbird.conf containing, on one line, every overlay
# peer:
#
#   Match host "…,<peer>.netbird.cloud,<peer>,…" exec "netbird ssh detect %h %p"
#       PreferredAuthentications password,publickey,keyboard-interactive
#       PasswordAuthentication yes
#       ProxyCommand /…/netbird ssh proxy %h %p
#       StrictHostKeyChecking no
#       UserKnownHostsFile /dev/null
#
# Two independent defects, and the second is the reason to remove it rather
# than tolerate it.
#
# 1. THE `exec` RUNS ON EVERY CONNECTION. A `Match … exec` invokes its command
#    to EVALUATE the condition, so `netbird ssh detect` runs whether or not the
#    match ultimately applies — and it opens an ssh connection, completes the
#    version exchange, and disconnects WITHOUT authenticating. Measured against
#    a fleet builder: roughly two such connections per successful dispatch,
#    arriving immediately before it (source ports ascend; the authenticated one
#    always holds the highest port in each group). Reproduced directly:
#
#      $ netbird ssh detect <peer>.netbird.cloud 22
#      server: Connection closed by <addr> port 49282 [preauth]
#
#    OpenSSH ≥9.8 classifies connect-without-authenticating as abuse and
#    penalises the SOURCE ADDRESS, which then drops the legitimate connections
#    too. It surfaces as "failed to start SSH connection to <builder>" — an
#    auth-shaped error for something that is not an auth problem, which is what
#    made it expensive to diagnose.
#
# 2. IT DISABLES HOST-KEY VERIFICATION. `StrictHostKeyChecking no` plus
#    `UserKnownHostsFile /dev/null` sit in ROOT's ssh config. They are inert
#    today — verified: the builder aliases resolve with their pinned
#    known_hosts intact — but they are inert by accident of which Match
#    condition happens to fire. A future rename, or a peer list that grows to
#    cover an alias, silently turns off host-key checking for a machine that
#    builds and signs store paths. That is the real argument; the wasted
#    connections are merely the symptom that exposed it.
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
# NOTHING IS LOST. The ProxyCommand is redundant when the overlay already
# provides direct addressing: NixOS fleet hosts have never loaded this block
# and reach every peer by name over the overlay regardless. Consumers that
# need per-host ssh settings for overlay peers already declare them
# explicitly (see nas-cache), which is also the only place host keys are
# pinned.
#
# WHY AN ACTIVATION SCRIPT. The app is not managed by nix — there is no
# option to set. `netbird service reconfigure` persists the setting into the
# service definition, so a one-off run would work until someone reinstalls or
# reconfigures the app and it silently comes back. Running it on every
# activation is the smallest mechanism that cannot drift: it is expressed in
# nix, re-asserted on every switch, and idempotent.
{
  config,
  lib,
  ...
}: let
  cfg = config.my.netbirdSshConfig;
in {
  options.my.netbirdSshConfig.disable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Set `NB_DISABLE_SSH_CONFIG=true` on the NetBird service so it stops
      writing `/etc/ssh/ssh_config.d/99-netbird.conf`.

      Default true: on darwin that file is loaded by root's ssh, and it both
      probes every peer on each connection and carries
      `StrictHostKeyChecking no`. A host that genuinely wants NetBird's ssh
      integration can set this false.

      Turning it off does NOT remove an already-generated file — the service
      rewrites it when reconfigured. Delete it once by hand if it lingers;
      the script reports when it is still present.
    '';
  };

  config = lib.mkIf cfg.disable {
    system.activationScripts.postActivation.text = lib.mkAfter ''
      # NetBird ssh_config suppression. Guarded on the binary existing so a
      # machine without the app activates cleanly, and on the setting not
      # already being applied so a switch is not slowed by a service
      # reconfigure every time.
      nbBin=/Applications/NetBird.app/Contents/MacOS/netbird
      if [ -x "$nbBin" ]; then
        if ! "$nbBin" service config 2>/dev/null | grep -q 'NB_DISABLE_SSH_CONFIG=true'; then
          echo "netbird: disabling ssh_config generation (NB_DISABLE_SSH_CONFIG=true)"
          "$nbBin" service reconfigure --service-env NB_DISABLE_SSH_CONFIG=true \
            || echo "netbird: reconfigure failed — 99-netbird.conf may still be generated" >&2
        fi
        # Report rather than delete: removing a file the service owns invites a
        # fight with it, and the stale copy is harmless once generation stops.
        if [ -e /etc/ssh/ssh_config.d/99-netbird.conf ]; then
          echo "netbird: /etc/ssh/ssh_config.d/99-netbird.conf still present; remove it once to clear the stale Match block" >&2
        fi
      fi
    '';
  };
}

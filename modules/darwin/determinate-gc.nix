# Scheduled nix GC + store optimisation for Determinate-managed darwin hosts.
#
# On hosts where the Determinate installer owns /etc/nix/nix.conf, nix-darwin's
# nix module is disabled (nix.enable = false), so darwinModules.common's
# nix.gc / nix.optimise / nix.settings are inert — nix-darwin never writes the
# launchd jobs or nix.conf. This module restores the same guardrails through
# channels that don't depend on nix.enable:
#
#   * /etc/nix/nix.custom.conf — the file Determinate reads for user overrides —
#     gets the disk-pressure GC (min-free/max-free) and store dedup
#     (auto-optimise-store) the daemon honours.
#   * a root launchd daemon runs the weekly time-based GC that nix.gc would
#     normally schedule.
#
# Determinate Nix proper (installed with --determinate) ships determinate-nixd,
# which already schedules GC; this module targets the plainer installer case
# (upstream nix daemon, no nixd) used on the personal Macs.
{
  config,
  lib,
  ...
}: let
  cfg = config.determinate-gc;
in {
  options.determinate-gc.enable =
    lib.mkEnableOption "scheduled nix GC + store optimisation on Determinate-managed darwin hosts (where nix-darwin's nix.gc is unavailable because nix.enable = false)";

  config = lib.mkIf cfg.enable {
    # Determinate includes /etc/nix/nix.custom.conf from its generated nix.conf,
    # so this is the sanctioned place to add daemon settings without fighting it.
    environment.etc."nix/nix.custom.conf".text = ''
      # Managed by nix-common darwinModules.determinate-gc. Disk-pressure GC +
      # store optimisation; the time-based sweep is the launchd daemon below.
      min-free = ${toString (1024 * 1024 * 1024)}
      max-free = ${toString (5 * 1024 * 1024 * 1024)}
      auto-optimise-store = true
    '';

    # Weekly time-based GC (the nix.gc.automatic equivalent). Runs as root so it
    # prunes every profile's old generations, not just one user's.
    launchd.daemons.nix-gc = {
      serviceConfig = {
        ProgramArguments = [
          "/bin/sh"
          "-c"
          "exec /nix/var/nix/profiles/default/bin/nix-collect-garbage --delete-older-than 30d"
        ];
        StartCalendarInterval = [
          {
            Weekday = 0;
            Hour = 3;
            Minute = 15;
          }
        ];
        RunAtLoad = false;
        StandardOutPath = "/var/log/nix-gc.log";
        StandardErrorPath = "/var/log/nix-gc.log";
      };
    };
  };
}

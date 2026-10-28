# modules/nixos/rpi-firmware-prune.nix — delete GPU firmware a previous
# generation left on a Raspberry Pi's FAT firmware partition.
#
# PROMOTED from nix-personal (modules/rpi-firmware-prune.nix), unchanged, when
# the Pi 5 board module (rpi5.nix, which turns this on) moved here so the
# pi-talos-home-ops cluster could share torrey's board config. Still exported
# on its own because the Pi 2/3/4 hosts in nix-personal use it without rpi5.nix.
#
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.rpiFirmwarePrune;
  fwBoot = "${config.hardware.raspberry-pi.firmware.package}/share/raspberrypi/boot";
in {
  options.my.rpiFirmwarePrune = {
    enable = lib.mkEnableOption ''
      removal of GPU firmware left on the Pi firmware partition by an earlier
      generation. Pair it with a pruned `hardware.raspberry-pi.firmware.package`
    '';

    target = lib.mkOption {
      type = lib.types.str;
      default = "/boot/firmware";
      description = ''
        The firmware partition. Must match what the `raspberry-pi-firmware`
        activation snippet installs into, since this prunes that same directory.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # nixos-hardware's installer prunes ONLY device trees and overlays:
    #
    #   for fn in "$target"/*.dtb "$target"/overlays/*; do
    #     if [ "${kept[$fn]:-}" != 1 ]; then rm -v -- "$fn"; fi
    #   done
    #
    # GPU firmware is copied but never pruned, so `bootcode.bin start*.elf
    # fixup*.dat` from a previous generation stay on the partition forever.
    # Dropping a model's firmware from the package therefore frees nothing:
    # the package stops shipping the file and the installer stops copying it,
    # but the copy already on the FAT partition is simply never revisited.
    #
    # Observed on tourmaline 2026-09-14: the package was correctly pruned to
    # start4*.elf only, and /boot/firmware still held all four Pi 0-3 files
    # (start.elf, start_x.elf, start_cd.elf, start_db.elf) plus their fixups
    # -- 11.9 MB of a 30 MB partition that was 83% full.
    #
    # That headroom is load-bearing rather than cosmetic. The installer stages
    # each file as `<name>.tmp` before renaming over the original, so it needs
    # the LARGEST file's size free on top of everything already present.
    # torrey hit the wall on 2026-09-14 and every deploy to it failed with
    #
    #   cp: error writing '/boot/firmware/start_db.elf.tmp': No space left on device
    #   Activation script snippet 'raspberry-pi-firmware' failed (1)
    #
    # This runs after that snippet and deletes any start*.elf / fixup*.dat the
    # package does not ship, which makes a package-side prune actually reclaim
    # the space. It is driven off the package contents rather than a hardcoded
    # model list, so each host drops exactly what its own firmware omits and
    # this needs no per-model logic.
    #
    # Deliberately narrow: only start*.elf and fixup*.dat are considered.
    # bootcode.bin, config.txt, u-boot.bin, *.dtb and overlays/ are never
    # touched -- the dtbs and overlays because the installer already prunes
    # them correctly, and bootcode.bin because the installer's copy loop lists
    # it as a LITERAL under `shopt -s nullglob`. nullglob only drops words
    # containing glob metacharacters, so a missing bootcode.bin survives
    # expansion with nothing behind it and `cp` then fails the activation.
    # Learned on torrey by removing it and watching the deploy roll back.
    system.activationScripts.rpi-firmware-prune = {
      deps = ["raspberry-pi-firmware"];
      text = ''
        if ${pkgs.util-linux}/bin/mountpoint -q ${lib.escapeShellArg cfg.target}; then
          for f in ${lib.escapeShellArg cfg.target}/start*.elf \
                   ${lib.escapeShellArg cfg.target}/fixup*.dat; do
            # A glob that matched nothing expands to itself; skip it.
            [ -e "$f" ] || continue
            b="$(${pkgs.coreutils}/bin/basename "$f")"
            if [ ! -e ${lib.escapeShellArg fwBoot}/"$b" ]; then
              echo "rpi-firmware-prune: removing stale $b (not in the firmware package)"
              ${pkgs.coreutils}/bin/rm -f -- "$f"
            fi
          done
        fi
      '';
    };
  };
}

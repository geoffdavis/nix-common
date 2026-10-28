# modules/nixos/rpi5.nix — Raspberry Pi 5 board config for the vendor kernel
# (linux-rpi) booted through U-Boot + generic-extlinux-compatible.
#
# PROMOTED from nix-personal (hosts/torrey/hardware.nix + the SD half of
# hosts/torrey/disk.nix) so the pi-talos-home-ops cluster's three Pi 5s can
# run the same board config torrey proved, instead of re-learning it. Every
# setting here was established on torrey's hardware, 2026-08-08..09-14; the
# comments are the measured evidence and are the reason this module exists.
# Treat them as load-bearing -- several lines look like tidy-up candidates
# and each one has a bricked boot behind it.
#
# CONSUMER CONTRACT
#
#   * Import nixos-hardware.nixosModules.raspberry-pi-5 yourself. It supplies
#     linux-rpi and the `hardware.raspberry-pi.*` options this module sets.
#     It is deliberately NOT an input of nix-common: adding it would put
#     nixos-hardware in the lock of every consumer, darwin-only ones included.
#   * Declare root yourself. This module mounts only the SD boot chain
#     (FIRMWARE vfat on /boot/firmware, NIXOS_SD ext4 on /boot) -- the one
#     part every Pi 5 here shares, because U-Boot can see nothing but the SD
#     (see "the SD boot chain" below). torrey puts / on NVMe via disko.
#   * Swap/zram policy is the host's.
#
# Imports rpi-firmware-prune.nix and turns it on: the firmware package below
# is pruned, and pruning the package alone frees nothing on the partition.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.rpi5;
in {
  imports = [./rpi-firmware-prune.nix];

  options.my.rpi5 = {
    enable = lib.mkEnableOption ''
      Raspberry Pi 5 board config for linux-rpi via U-Boot: firmware-supplied
      device tree, pinned + pruned GPU firmware, CMA via the vc4 overlay,
      NVMe-capable U-Boot, debug-UART console, and the SD boot-chain mounts.
      Requires nixos-hardware.nixosModules.raspberry-pi-5 to be imported
    '';
  };

  config = lib.mkIf cfg.enable {
    # ── the device tree comes from the FIRMWARE, never FDTDIR ──────────────
    #
    # A dtb out of FDTDIR is the kernel's RAW build artifact, and a Pi 5 does
    # not boot on one. The GPU firmware rewrites the tree before handing it
    # over -- clocks, pinctrl groups, RTC, linux,cma -- and linux-rpi is built
    # assuming that has happened. With FDTDIR torrey hung at ~0.8s, every
    # time, with no network and no getty:
    #
    #   raspberrypi-clk ...:firmware:clocks: probe with driver raspberrypi-clk
    #                                        failed with error -22
    #   pinctrl-bcm2712 107d504100.pinctrl: invalid group "gpio24" for function
    #                                       "uart0"
    #
    # Bisected on the serial console holding the kernel constant and varying
    # ONLY the tree:
    #
    #   linux-rpi + FDTDIR bcm2712-rpi-5-b.dtb    -> hang at 0.767s
    #   linux-rpi + FDTDIR bcm2712-d-rpi-5-b.dtb  -> hang at 0.961s
    #   linux-rpi + FIRMWARE dtb                  -> BOOTS, thermal_zone0 +
    #                                                pwmfan + cooling_device0
    #
    # "Same package, so kernel and tree cannot skew" is true and irrelevant:
    # the property that matters is FIXED-UP, not same-package.
    #
    # The setting follows the KERNEL LINEAGE: mainline needs FDTDIR (true) --
    # the firmware's vendor tree gives it `rp1_pci ... failed with error -22`,
    # and since RP1 carries ethernet, USB and the GPIO UART that leaves a
    # board with no I/O at all -- and linux-rpi needs the firmware tree
    # (false), which is upstream nixos-hardware's default.
    #
    # ROLLBACK HAZARD: this is a property of extlinux.conf, NOT of a
    # generation. Flipping it rewrites the whole file and changes EVERY boot
    # entry at once, so the boot menu is not a safety net across a lineage
    # change. torrey's recovery needed the serial console:
    #
    #   ext4load mmc 0:2 ${kernel_addr_r} /boot/nixos/<gen>-Image
    #   ext4load mmc 0:2 ${ramdisk_addr_r} /boot/nixos/<gen>-initrd
    #   setenv bootargs "init=/nix/store/<system>/init console=ttyAMA10,115200n8 ..."
    #   booti ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} ${fdt_addr}
    #
    # (${fdt_addr} = the firmware tree, for a vendor kernel. A MAINLINE rescue
    # wants fdt_addr_r with an ext4load'ed bcm2712-d-rpi-5-b.dtb instead --
    # bcm2712-rpi-5-b.dtb panics the board with an SError in
    # brcmstb_pull_config_set.)
    boot.loader.generic-extlinux-compatible.useGenerationDeviceTree = false;

    # ── firmware partition ────────────────────────────────────────────────
    # U-Boot is REQUIRED. It supplies config.txt's `kernel=u-boot.bin` and
    # `arm_64bit=1` and stages the binary; without it the firmware loads and
    # has nothing to hand off to -- a disk that does not boot, with no error
    # to read (bench-bitten on tourmaline 2026-08-03).
    hardware.raspberry-pi.firmware.enable = true;
    hardware.raspberry-pi.firmware.uboot.enable = true;

    # ── GPU firmware: the DTB source, and it MUST match the kernel ────────
    #
    # With the firmware tree in use (above), the DTBs this package installs
    # ARE the kernel's device tree. On a Pi 5 there is no start.elf in the
    # boot path at all, so the DTBs are very nearly all it contributes.
    #
    # nixpkgs' raspberrypifw (1.20250430) is sixteen months older than
    # nixos-hardware's linux-rpi, and measured on torrey 2026-09-13 its tree
    # differs from the kernel's in 335 lines, including root #size-cells 1
    # vs 2 and an extra Pi 2/3 "brcm,bcm2836-l1-intc" node -- both confirmed
    # in the LIVE tree, not just on disk. Every release from 1.20260521 on
    # fixes both. 1.20260824 is the first after linux-rpi's stable_20260724
    # tag, so the tree is newer than the kernel rather than older (the
    # direction that bites: drivers expecting bindings the tree lacks).
    #
    # THE PIN ALONE FIXES NOTHING -- measured. What it does is let the
    # linux,cma node parse ("OF: reserved mem: invalid size property in
    # 'linux,cma' node" disappears), which is the prerequisite for sizing
    # CMA through the overlay below. The two land together or not at all.
    #
    # Benign and expected after all of this: bcm7271-uart still fails
    # -EINVAL. It is the unused debug-UART alias, not a mailbox consumer. Do
    # not chase it as a regression.
    #
    # The installPhase append is a SEPARATE concern -- partition SIZE, not
    # DTB contents. /boot/firmware is a 30 MB FAT partition and
    # nixos-hardware's installer copies every model's `start*.elf fixup*.dat`
    # (22 MB, none of it in a Pi 5's boot path). It stages each copy as
    # `<name>.tmp`, so it needs the largest file's size free on top, and on
    # torrey every deploy died with
    #
    #   cp: error writing '/boot/firmware/start_db.elf.tmp': No space left on device
    #
    # until they were dropped from the package (#670, 2026-09-14). The
    # installer iterates the globs under `shopt -s nullglob`, so a pattern
    # that matches nothing just vanishes. bootcode.bin STAYS: it is a literal
    # in that loop, survives nullglob, and `cp` fails activation without it
    # (tried, 2026-09-14). Pi <= 4 boards DO need start*.elf -- which is why
    # this lives in the Pi 5 module only.
    #
    # Append to installPhase, not postInstall/postFixup: raspberrypifw's
    # installPhase never calls `runHook postInstall` and it sets dontFixup,
    # so both silently no-op (tried; all 8 start*.elf survived).
    my.rpiFirmwarePrune.enable = true;

    hardware.raspberry-pi.firmware.package = pkgs.raspberrypifw.overrideAttrs (old: {
      version = "1.20260824";
      src = pkgs.fetchFromGitHub {
        owner = "raspberrypi";
        repo = "firmware";
        rev = "1.20260824";
        hash = "sha256-pKb/LIBJnTx1PHdRmQanfnBaerX/nbDMEySmjGLn8Ro=";
      };
      installPhase =
        old.installPhase
        + ''
          # Pi <=4 VideoCore boot firmware; unused on bcm2712 (see above).
          # Globbed patterns only -- bootcode.bin is a literal in the
          # installer's loop and must remain present.
          rm -f "$out"/share/raspberrypi/boot/start*.elf \
                "$out"/share/raspberrypi/boot/fixup*.dat
        '';
    });

    # ── CMA SIZE VIA THE OVERLAY, NEVER `cma=` ON THE COMMAND LINE ────────
    #
    # `cma=` on the cmdline does not size the DT linux,cma node, it BYPASSES
    # it -- and with it `alloc-ranges = <0 0 0 0x40000000>`, which keeps the
    # pool in the low 1 GB. The kernel says so on every boot ("Skipping dt
    # linux,cma-default for 'cma=' kernel param"), the pool lands high (torrey:
    # 0xfc000000), and the Pi 5 firmware mailbox -- which can only reach the
    # low 1 GB -- stops answering. raspberrypi-clk, rpi-rtc and vc4_hvs then
    # fail -EINVAL and retry forever, and the firmware writes its 0x80000001
    # ERROR word into buffers the kernel has already freed: a metronomic
    # 1 Hz memory corruption that quarantined torrey (2026-09-13). Same bug as
    # raspberrypi/linux#7230, closed for lack of response rather than fixed.
    #
    # Sized through the overlay, the DT node stays authoritative and the
    # pool lands at 0x2e000000: raspberrypi-clk probes clean, rpi-rtc
    # registers rtc0, vcgencmd answers, and the clobber is gone.
    #
    # `deviceTreeOverlays`, NOT `configtxt.settings.all.dtoverlay`:
    #   1. nixos-hardware defaults `deviceTreeOverlays.all` to a bare
    #      vc4-kms-v3d with mkDefault; setting the same option REPLACES it.
    #      settings.all.dtoverlay only APPENDS, leaving a later parameterless
    #      `dtoverlay=vc4-kms-v3d` that would put the CMA size back.
    #   2. a dtoverlay written through `settings` gets no terminator, so it
    #      captures every following dtparam (audio=on is a default here).
    #
    # Renders as, and was booted and measured as:
    #
    #   dtoverlay=vc4-kms-v3d
    #   dtparam=cma-256=on
    #   dtoverlay=
    #
    # Dropping vc4 entirely would free the pool, but costs the HDMI console --
    # a recovery path -- so it is not a trade to make in a shared module.
    hardware.raspberry-pi.configtxt.deviceTreeOverlays.all = [{vc4-kms-v3d.cma-256 = true;}];

    # ── U-Boot 2026.07 + NVMe ─────────────────────────────────────────────
    #
    # NOTE: on a Pi 5 U-Boot still CANNOT read an NVMe (see "the SD boot
    # chain" below) -- this is why /boot lives on the SD. The override is
    # kept because it is the U-Boot torrey runs and was proven with; dropping
    # it is a separate, measured change.
    #
    # Why it exists: stock rpi_arm64_defconfig never enables NVMe, and
    # nixpkgs' U-Boot 2026.04 pcie_brcmstb matches only brcm,bcm2711-pcie,
    # so on a Pi 5 no PCI device enumerates at all. bcm2712 PCIe support
    # first shipped in v2026.07 (with RESET_BRCMSTB{,_RESCAL}). With it the
    # bus comes up and the Kingston enumerates; then `nvme scan` timed out
    # (err=-110), which upstream 09b1c0f98 ("nvme: Fix missing address
    # translation for PCIe inbound access") addresses -- bcm2712's inbound
    # window is non-zero. Merged hours after the 2026.07 tag, absent from
    # v2026.10-rc1, hence carried as a single patch.
    #
    # Drop the version override once nixpkgs' defaultVersion reaches
    # 2026.07+; drop the patch once a release's drivers/nvme/nvme.c applies
    # the bridge's inbound offset.
    hardware.raspberry-pi.firmware.uboot.package = pkgs.ubootRaspberryPiAarch64.override {
      version = "2026.07";
      src = pkgs.fetchurl {
        url = "https://ftp.denx.de/pub/u-boot/u-boot-2026.07.tar.bz2";
        hash = "sha256-eOi/w4L+OI+bVaodr4xWNSKgN3ebXUw0nRQV44HxJD4=";
      };
      extraConfig = ''
        CONFIG_NVME=y
        CONFIG_NVME_PCI=y
        CONFIG_CMD_NVME=y
      '';
      extraPatches = [
        (pkgs.fetchurl {
          url = "https://github.com/u-boot/u-boot/commit/09b1c0f98.patch";
          hash = "sha256-ibgZHXtsRLyDjO4EYyuHMCtoiQBK+IU0lwAXG1pigpY=";
        })
      ];
    };

    # Load-bearing with the firmware tree: config.txt is merged into the DT
    # the kernel receives, so enable_uart is part of how ttyAMA10 comes to
    # exist -- i.e. part of how the break-glass serial console keeps working.
    #
    # HDMI audio is UNTESTED here: nothing sets `,noaudio`. On other vendor
    # boards an unbound "audio-rx" DMA made vc4 retry its whole component
    # bind ~15x/s forever (tourmaline: 28,847 retries in 2h, systemd at 83%
    # CPU). If `dmesg | grep -c vc4-drm` climbs on a Pi 5, `,noaudio` is the
    # fix -- not added pre-emptively because it is unmeasured on this board.
    hardware.raspberry-pi.configtxt.settings.pi5.enable_uart = true;

    boot.kernelParams = [
      # ttyAMA10, NOT ttyAMA0: the BCM2712's own PL011 on the 3-pin debug
      # connector -- the break-glass path for a box whose NIC is the thing
      # most likely to fail. ttyAMA0 is RP1's GPIO-header UART under
      # linux-rpi. 115200 to match firmware/BL31/U-Boot; without it the port
      # sits at 9600 and shows noise from the kernel onward.
      "console=ttyAMA10,115200n8"
      "console=tty0"

      # ── Pi 5 NUMA emulation, from the firmware's injected bootargs ──────
      #
      # The firmware puts a set of Pi 5 parameters in /chosen/bootargs, and
      # extlinux's APPEND REPLACES bootargs wholesale, so a U-Boot-booted Pi 5
      # gets none of them. These three were copied back on 2026-08-15 against
      # a memtester corruption signature (two addresses exactly 0x7FFFE008
      # apart, upper 32 bits replaced by 0x80000001).
      #
      # CORRECTED 2026-09-13: they were NOT the fix. That corruption was the
      # CMA/mailbox bug above; with `cma=` removed it is gone. These are now
      # of UNPROVEN value and are kept only because nothing shows them
      # harmful and that was not the moment to retune memory. Retire them on
      # a fresh measurement, not on this comment.
      #
      # Deliberately NOT copied from the firmware's set: cgroup_disable=memory
      # (breaks systemd and nix memory accounting), pci=pcie_bus_safe and
      # coherent_pool=1M (measured no-ops), vc_mem.* / smsc95xx.macaddr.
      "numa=fake=8"
      "numa_policy=interleave"
      "iommu_dma_numa_policy=interleave"
    ];

    # systemd-getty-generator only instantiates serial-getty@ for
    # /dev/console, which is tty0 here, so the debug UART needs the unit named
    # explicitly or it stays write-only.
    systemd.services."serial-getty@ttyAMA10" = {
      enable = true;
      wantedBy = ["multi-user.target"];
    };

    # nixos-hardware's raspberry-pi-5 module already contributes these;
    # listed again because a board that cannot reach its NVMe root in stage 1
    # is unrecoverable remotely, and the duplication costs nothing.
    boot.initrd.availableKernelModules = ["nvme" "pcie_brcmstb" "clk_rp1"];

    # THERE IS NO TPM ON A RASPBERRY PI, and without this linux-rpi cannot
    # produce an initrd at all:
    #
    #   > root module: tpm-crb
    #   > modprobe: FATAL: Module tpm-crb not found in directory .../6.18.34
    #
    # systemd-initrd's tpm2 support (default on) requests tpm-crb on every
    # platform except riscv64 and armv7; the vendor kernel does not build it.
    # Mainline arm64 does, which is why a mainline-first bring-up never sees
    # this. Turned off rather than filtered: the honest statement is "this
    # machine has no TPM".
    boot.initrd.systemd.tpm2.enable = false;

    # ── the SD boot chain ─────────────────────────────────────────────────
    #
    # Three readers, each able to read less than the next, and the layout is
    # dictated by the WEAKEST:
    #
    #   1. The SoC mask ROM / EEPROM reads FAT only -> config.txt and
    #      u-boot.bin on a FAT partition.
    #   2. U-Boot reads FAT and ext4 but on a Pi 5 sees ONLY the SD card ->
    #      the kernels it loads must be on the SD.
    #   3. The kernel reads everything -> root can live on NVMe.
    #
    # Why U-Boot sees only the SD: on a Pi 5 ethernet, USB and the PCIe path
    # all hang off RP1, and U-Boot has NO RP1 driver (the EPAM series is
    # unmerged, blocked on Linux DT bindings). One gap explains the NVMe
    # err=-110 above, an attached USB mass-storage device U-Boot cannot see
    # ("No USB controllers found" -- the firmware issues XHCI-STOP before the
    # hand-off), and "No ethernet found". Identical on 2026.07 and
    # 2026.10-rc2. So a Pi 5 installer can also only come from the SD: kexec
    # into a RAM installer comes up with RP1 failing (`rp1_pci ... Missing
    # of_node`, no network), and nixos-anywhere's own kexec leaves the box on
    # 1 of 4 cores.
    #
    # The card is therefore written externally (an installer sd-image) and
    # merely MOUNTED here; disko cannot repartition the disk it boots from.
    # The labels are the sd-image's own.
    #
    # NEVER leave installer media attached to a running Pi 5: it carries the
    # SAME labels, and on torrey /dev/disk/by-label/FIRMWARE resolved to the
    # read-only USB copy, fsck failed, and /boot/firmware did not mount. Had
    # it been writable, a rebuild would have written config.txt and
    # u-boot.bin into the installer image instead of the card.
    #
    # Nothing else may land on the SD: /var, /home, /tmp etc. are directories
    # on /, not mounts. A new fileSystems entry pointing at the card is the
    # only way to undo that, and there should never be one.
    fileSystems."/boot/firmware" = {
      device = "/dev/disk/by-label/FIRMWARE";
      fsType = "vfat";
      # nofail, never noauto: unmounted, the raspberry-pi firmware activation
      # script writes into the mountpoint DIRECTORY on / instead, the real FAT
      # partition keeps its old config.txt and u-boot.bin, and every firmware
      # change silently does nothing (bench-proven on tourmaline).
      options = ["nofail"];
    };
    # extlinux plus every generation's kernel and initrd. noatime: reads of
    # the boot directory must not write to the card.
    fileSystems."/boot" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      options = ["noatime"];
    };
  };
}

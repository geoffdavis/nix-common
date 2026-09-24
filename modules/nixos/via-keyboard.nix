# modules/nixos/via-keyboard.nix — hidraw uaccess udev rules for VIA/Vial
# keyboard configurator (usevia.app / vial-gui) access to programmable
# keyboards.
#
# VIA/Vial talk directly to the keyboard's raw HID interface
# (/dev/hidraw*), which is root-only by default. VIA's own docs suggest a
# blanket `KERNEL=="hidraw*"` rule granting every hidraw device to the
# logged-in user — simple, but it hands out every HID device on the box
# (other keyboards, mice, etc.), which is broader than this module wants.
# Instead this declares one rule per known device (idVendor/idProduct),
# TAG+="uaccess" so systemd-logind ACLs the node to the active seat user —
# the same mechanism used for /dev/dri and /dev/input.
#
# This is shipped via services.udev.packages (a rules file sorted as
# 70-via-keyboard.rules), NOT services.udev.extraRules: extraRules lands in
# /etc/udev/rules.d/99-local.rules, which udev processes *after*
# systemd's 73-seat-late.rules — the rule that runs the uaccess builtin
# only for tags already present at that point. A rule filed at 99-* is too
# late: uaccess never fires for it, and a keyboard plugged into an active
# session gets no ACL until a later session transition or manual retrigger.
# 70-via-keyboard.rules sorts before 73-seat-late.rules, so our TAG+="uaccess"
# is visible in time.
#
# Each VIA-compatible keyboard uses its maker's own USB vendor/product ID
# (there is no single shared "VIA" VID), so the built-in `devices` list only
# covers devices actually in use. `devices` fully replaces the built-in list
# if a host sets it; use `extraDevices` (mergeable, always additive) to add a
# keyboard alongside the built-in default instead. Find a device's IDs with
# `lsusb`.
#
# A mirror of this rule for non-NixOS Ansible-managed hosts (kept in sync by
# hand, since ansible isn't a nix-common concern) lives in the consumer
# repo's ansible layer.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.via-keyboard;

  deviceSubmodule = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Human-readable label for this device (comment only).";
      };
      vendorId = lib.mkOption {
        type = lib.types.strMatching "[0-9a-f]{4}";
        description = "Lowercase 4-hex-digit USB idVendor, e.g. from `lsusb`.";
      };
      productId = lib.mkOption {
        type = lib.types.strMatching "[0-9a-f]{4}";
        description = "Lowercase 4-hex-digit USB idProduct, e.g. from `lsusb`.";
      };
    };
  };

  mkRule = device: ''
    # ${device.name}
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="${device.vendorId}", ATTRS{idProduct}=="${device.productId}", TAG+="uaccess"
  '';
in {
  options.my.via-keyboard = {
    enable = lib.mkEnableOption "hidraw uaccess udev rules for VIA/Vial-compatible keyboards";

    devices = lib.mkOption {
      type = lib.types.listOf deviceSubmodule;
      default = [
        {
          name = "Keebio Iris LM-K Rev. 1";
          vendorId = "cb10";
          productId = "1756";
        }
      ];
      description = ''
        VIA/Vial-compatible keyboards to grant hidraw uaccess to. Setting
        this option replaces the built-in default entirely (it's a plain
        option default, not a mergeable definition) — use
        `my.via-keyboard.extraDevices` to add a keyboard alongside the
        default instead of replacing it.
      '';
    };

    extraDevices = lib.mkOption {
      type = lib.types.listOf deviceSubmodule;
      default = [];
      description = ''
        Additional VIA/Vial-compatible keyboards, merged with (not
        replacing) `devices`. Prefer this over overriding `devices` when a
        host just needs to add a keyboard alongside the built-in default.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.udev.packages = [
      (pkgs.writeTextFile {
        name = "via-keyboard-udev-rules";
        destination = "/lib/udev/rules.d/70-via-keyboard.rules";
        text = lib.concatMapStringsSep "\n" mkRule (cfg.devices ++ cfg.extraDevices);
      })
    ];
  };
}

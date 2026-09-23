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
# Each VIA-compatible keyboard uses its maker's own USB vendor/product ID
# (there is no single shared "VIA" VID), so the default list only covers
# devices actually in use; add more via `my.via-keyboard.devices` as new
# keyboards show up. Find a device's IDs with `lsusb`.
#
# A mirror of this rule for non-NixOS Ansible-managed hosts (kept in sync by
# hand, since ansible isn't a nix-common concern) lives in the consumer
# repo's ansible layer.
{
  config,
  lib,
  ...
}: let
  cfg = config.my.via-keyboard;

  mkRule = device: ''
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="${device.vendorId}", ATTRS{idProduct}=="${device.productId}", TAG+="uaccess"
  '';
in {
  options.my.via-keyboard = {
    enable = lib.mkEnableOption "hidraw uaccess udev rules for VIA/Vial-compatible keyboards";

    devices = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
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
      });
      default = [
        {
          name = "Keebio Iris LM-K Rev. 1";
          vendorId = "cb10";
          productId = "1756";
        }
      ];
      description = ''
        VIA/Vial-compatible keyboards to grant hidraw uaccess to. Extend
        (don't replace) this list on a host that needs another keyboard,
        e.g. `my.via-keyboard.devices = lib.mkAfter [ { name = "..."; vendorId = "..."; productId = "..."; } ];`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.udev.extraRules = lib.concatMapStringsSep "\n" mkRule cfg.devices;
  };
}

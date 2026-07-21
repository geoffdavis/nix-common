# modules/nixos/steam.nix — opt-in Steam client for NixOS desktop hosts.
#
# Off by default; flip `my.steam.enable` per consumer. `programs.steam.enable`
# on its own only wires the FHS-sandboxed client — this module adds the
# system-level prerequisites that are easy to forget and that Steam/games
# actually need:
#   - hardware.graphics.enable32Bit — Steam itself and nearly every game need
#     the 32-bit GL/Vulkan userspace. (hardware.graphics.enable stays the
#     host's job — it comes from the GPU/desktop config.)
#   - hardware.steam-hardware — udev rules + firmware for Steam Controller,
#     Steam Deck, Valve Index, etc.
#   - the "steam"/"steam-unwrapped" unfree allowances, contributed to
#     my.unfreePackageNames ONLY when Steam is enabled — so they stay out of
#     the shared baseline allowlist that work/darwin hosts consume.
#
# Deliberately NOT bundled: Feral gamemode. It asks for the "performance" CPU
# governor while a game runs, which on a thermally-tight host (e.g. birdrock's
# T2 MacBook Air, whose config documents hard power-offs under that envelope)
# is a footgun. A host that wants it sets programs.gamemode.enable itself.
{
  config,
  lib,
  ...
}: let
  cfg = config.my.steam;
in {
  options.my.steam = {
    enable = lib.mkEnableOption "the Steam client (FHS-sandboxed) and its NixOS prerequisites";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open the firewall for Steam Remote Play and Local Network Game
        Transfers. Harmless on a trusted LAN; set false on hosts with a
        strict firewall policy.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = cfg.openFirewall;
      localNetworkGameTransfers.openFirewall = cfg.openFirewall;
    };

    hardware.graphics.enable32Bit = true;
    hardware.steam-hardware.enable = true;

    # Permit Steam's unfree derivations only where Steam is actually on.
    my.unfreePackageNames = ["steam" "steam-unwrapped"];
  };
}

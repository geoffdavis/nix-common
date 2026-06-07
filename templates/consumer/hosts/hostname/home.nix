# Per-host home-manager config. Keep host-specific settings here; pull shared
# behaviour from nix-common modules in flake.nix rather than copying it in.
{...}: {
  # CHANGEME: match the actual login user and home directory.
  home.username = "user";
  home.homeDirectory = "/home/user";

  # Set to the home-manager release you track (matches nix-common's pin).
  home.stateVersion = "25.11";
}

# nix-common

Shared nix modules and pinned flake inputs for my personal multi-host nix
configs — macOS (nix-darwin), NixOS, and standalone home-manager on Linux.
Downstream host repos are kept separate; this repo stays context-neutral and
names no specific hosts.

## Exports

System modules — per platform; system config + home-manager wiring:

- `darwinModules.common` — nix-darwin hosts (macOS)
- `nixosModules.common` — NixOS hosts

Home modules — imported into a host's home-manager user (cross-platform unless noted):

- `homeModules.cli-tools` — shared CLI packages (Mac + Linux)
- `homeModules.neovim` — LazyVim editor + global `EDITOR=nvim`
- `homeModules.profile` — shared Linux `.profile` snippet management
- `homeModules.git` — git config + 1Password SSH commit signing
- `homeModules.ssh` — 1Password SSH agent / `IdentityAgent` config
- `homeModules.graphics` — GUI / diagramming tools
- `homeModules.desktop-base` — cli-tools + git + graphics + ssh, plus GUI/fonts on an interactive desktop
- `homeModules.gnome-dconf` — GNOME dconf settings (extensions, scaling)
- `homeModules.gnome-desktop-base` — desktop-base + gnome-dconf + unfree-desktop (a GNOME Linux desktop)
- `homeModules.linux-headless-base` — cli-tools + git (headless Linux)
- `homeModules.unfree-desktop` — home-level `allowUnfree` predicate

## Shared profile management

Linux profile hooks are centralized via `homeModules.profile`.

Modules can append login/session snippets with:

```nix
sharedProfile.snippets = [
  ''
    # Example: source Home Manager session variables at login
    if [ -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
      . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
    fi
  ''
];
```

Notes:

- Snippets are concatenated into `~/.profile` only on Linux.
- If no snippets are defined, `~/.profile` is not managed by this module.
- Desktop-specific snippets should usually be gated, for example with `config.targets.genericLinux.enable`, to avoid conflicting with NixOS-managed session behavior.

`neovim` is imported by both `*Modules.common`, so every host gets the editor;
consumers pass `lazyvim` via `extraSpecialArgs`.

## Consuming this flake

In a downstream `flake.nix`, follow the pin set that matches your platform.

Darwin hosts:

    nixpkgs.follows = "nix-common/nixpkgs-darwin";
    home-manager.follows = "nix-common/home-manager-darwin";
    darwin.follows = "nix-common/darwin";
    lazyvim.follows = "nix-common/lazyvim";

NixOS hosts / Linux home configs:

    nixpkgs-nixos.follows = "nix-common/nixpkgs-nixos";
    home-manager-nixos.follows = "nix-common/home-manager-nixos";

Example for a darwin host:

```nix
{
  inputs = {
    nix-common.url = "github:geoffdavis/nix-common";

    # follow nix-common's pins so all hosts use the same versions
    nixpkgs.follows = "nix-common/nixpkgs-darwin";
    home-manager.follows = "nix-common/home-manager-darwin";
    darwin.follows = "nix-common/darwin";
    lazyvim.follows = "nix-common/lazyvim";
  };

  outputs = { nix-common, darwin, home-manager, lazyvim, ... }: {
    darwinConfigurations.<host> = darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = { inherit lazyvim darwin; };
      modules = [
        home-manager.darwinModules.home-manager
        nix-common.darwinModules.common
        ./hosts/<host>/default.nix
      ];
    };
  };
}
```

## Updating consumers

When you push a change to this repo, downstream consumers pick it up
explicitly with:

```sh
nix flake update nix-common
sudo darwin-rebuild switch --flake .   # or home-manager switch
```

That two-step is the cost of separating contexts — work-laptop repos
don't leak into each other, but cross-cutting updates require a bump.

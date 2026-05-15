# nix-common

Shared nix modules and pinned flake inputs for my personal multi-host
configs (windansea, viasat-laptop, oceaneering-laptop, ...).

## Exports

| output                       | what it is                                   |
| ---------------------------- | -------------------------------------------- |
| `darwinModules.common`       | shared nix-darwin config for every Mac       |
| `homeModules.cli-tools`      | shared home-manager CLI packages (Mac + Linux) |

## Consuming this flake

In a downstream `flake.nix`:

```nix
{
  inputs = {
    nix-common.url = "github:geoffdavis/nix-common";

    # follow nix-common's pins so all hosts use the same versions
    nixpkgs.follows = "nix-common/nixpkgs";
    home-manager.follows = "nix-common/home-manager";
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

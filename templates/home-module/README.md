# home-module template

Skeleton for a new shared **home-manager** module in `nix-common`, following
the module contract documented in [`AGENTS.md`](../../AGENTS.md) and
[`docs/module-contract.md`](../../docs/module-contract.md).

## Use it

From inside a `nix-common` checkout:

```sh
task new:module -- mymodule      # scaffolds modules/home/mymodule.nix
```

Then wire the export into `flake.nix`:

```nix
homeModules.mymodule = ./modules/home/mymodule.nix;
```

…and verify:

```sh
task contract     # modules/ <-> flake.nix exports are consistent
task fmt          # alejandra
task lint         # full pre-commit chain
```

Or, to drop the raw skeleton into an empty directory:

```sh
nix flake init -t github:geoffdavis/nix-common#home-module
```

## The contract in one line

One `enable` option, all config behind `lib.mkIf cfg.enable`, `lib.mkDefault`
for anything a host might override, no unused lambda args, no hardcoded
secrets (use `homeModules.op-json-secrets` / `homeModules.ssh`).

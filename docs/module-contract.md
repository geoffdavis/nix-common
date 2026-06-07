# The nix-common module contract

This is the checklist every shared module must satisfy. It exists so that
automated agents (and humans in a hurry) add modules that compose cleanly and
can't silently break downstream consumers. The structural half is enforced by
`scripts/check-module-contract.sh` (run as `task contract`, a pre-commit hook,
and the `module-contract` CI job); the stylistic half is enforced by alejandra
/ deadnix / statix.

## Where a module goes

| Kind | Path | Flake export |
| --- | --- | --- |
| Cross-platform home-manager | `modules/home/<name>.nix` | `homeModules.<name>` |
| NixOS-only | `modules/nixos/<name>.nix` | `nixosModules.<name>` |
| nix-darwin-only | `modules/darwin/<name>.nix` | `darwinModules.<name>` |
| Internal helper (imported by other modules, **not** a flake output) | `modules/shared/<name>.nix` | none |

Anything outside `modules/shared/` **must** be exported from `flake.nix`. The
contract check fails closed on an orphaned module file or a dangling export
path — this is the single most common agent mistake (add a file, forget to
wire it up).

## The shape of a module

```nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myModule;
in {
  options.myModule.enable = lib.mkEnableOption "what it provides";

  config = lib.mkIf cfg.enable {
    # ...
  };
}
```

Rules:

1. **One `enable` option** gates everything via `lib.mkIf cfg.enable`. A
   consumer that doesn't import-and-enable pays nothing.
2. **`lib.mkDefault`** on anything a host might reasonably override. Without
   it, a consumer setting the same option gets a conflict instead of an
   override.
3. **No unused lambda args.** Don't list `pkgs,` / `lib,` you don't reference
   — deadnix fails the build.
4. **No platform-specific absolute paths** (`/Applications/...`, `/opt/...`)
   without a darwin/nixos fork or a `lib.mkDefault` escape hatch.
5. **No hardcoded secrets.** Public SSH keys are fine; everything else goes
   through `homeModules.op-json-secrets` / `homeModules.op-file-secrets` or
   `homeModules.ssh` (`onepassword-ssh.keys`).
6. `inherit (x) y;` over `y = x.y;`.

## Scaffolding

```sh
task new:module -- <name>      # copies the skeleton to modules/home/<name>.nix
# then export it in flake.nix, and:
task contract && task fmt && task lint
```

## Why this is agent-friendly

- The failure modes are **mechanical and named** (orphan module, dangling
  ref, unused arg, missing mkIf) — an agent can self-correct from the error
  text without human review.
- The check needs **no nix toolchain** (pure bash), so it runs in any
  sandbox an agent operates in, and in CI even when a Nix eval error would
  otherwise mask it.
- The blessed shape lives in one copyable place (`templates/home-module`),
  so "add a module" has a single deterministic starting point.

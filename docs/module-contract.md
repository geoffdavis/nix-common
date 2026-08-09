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
| Platform-agnostic **system** module (NixOS + nix-darwin) | `modules/<name>.nix` | `nixosModules.<name>` **and** `darwinModules.<name>` (double-exported; e.g. `nas-cache`, `cache-push`) |
| Library / builder export (not a module) | `modules/shell/<name>.nix` etc. | `lib.<name>` |
| Internal helper (imported by other modules, **not** a flake output) | `modules/shared/<name>.nix` | none |
| Concern file of a split module (imported only by its entry module, **not** a flake output) | `modules/home/hyprland/<name>.nix` | none (the entry `modules/home/hyprland.nix` is the export; the contract check exempts this directory explicitly) |

Some modules additionally require values the consumer must pass via
`specialArgs` / `extraSpecialArgs` — currently `lazyvim`
(`homeModules.neovim`, both `*Modules.common`) and `darwin`
(`darwinModules.common`). A module that adds such an argument must document
it in its header and in the README export list; the flake cannot supply it
for you.

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

## Two module classes

Not every shared module wants an enable gate — about half the tree is
deliberately "importing is the opt-in" (`desktop-base`, `cli-tools`, `git`,
both `common` modules, ...). The contract recognizes both classes
explicitly:

- **Feature module** (the default; the skeleton's shape): declares options,
  gates everything behind `lib.mkIf cfg.enable`. A consumer that doesn't
  import-and-enable pays nothing.
- **Base/profile module**: importing IS the enable — config applies
  unconditionally. Must carry an `IMPORT-IS-OPT-IN` header comment so the
  choice is visible and machine-checkable; `check-module-contract.sh`
  fails closed on a module with neither options nor the header.

New modules default to the feature class; use the base class only when the
module is a bundle whose entire point is "give me the standard set".

Rules:

1. **One `enable` option** gates everything via `lib.mkIf cfg.enable`
   (feature class), or an `IMPORT-IS-OPT-IN` header (base class — see
   above).
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

- The failure modes are **mechanical and named** — an agent can self-correct
  from the error text without human review. Who enforces what:
  `check-module-contract.sh` catches orphan modules, dangling exports, and
  (since #124) the module-class rule — a module with neither options nor an
  `IMPORT-IS-OPT-IN` header fails closed; deadnix (pre-commit + CI) catches
  unused lambda args. The interior of the `mkIf` gate remains
  checklist-only.
- The check needs **no nix toolchain** (pure bash), so it runs in any
  sandbox an agent operates in, and in CI even when a Nix eval error would
  otherwise mask it.
- The blessed shape lives in one copyable place (`templates/home-module`),
  so "add a module" has a single deterministic starting point.

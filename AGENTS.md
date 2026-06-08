# Agent guide

Shared nix modules and pinned flake inputs for personal multi-host configs
(macOS / NixOS / standalone-home-manager Linux). Consumed by
[nix-personal](https://github.com/geoffdavis/nix-personal),
[nix-oceaneering](https://github.com/geoffdavis/nix-oceaneering), and
[nix-viasat](https://github.com/geoffdavis/nix-viasat) as a flake input.

## Build / test

```sh
nix flake check     # evaluates all module outputs
task contract       # asserts modules/ <-> flake.nix exports are consistent
```

## Adding a shared module

Don't hand-roll one — start from the skeleton, which already satisfies the
[module contract](docs/module-contract.md):

```sh
task new:module -- <name>     # writes modules/home/<name>.nix from the skeleton
# then export it in flake.nix:  homeModules.<name> = ./modules/home/<name>.nix;
task contract && task fmt && task lint
```

`task contract` (and the `module-contract` CI job + pre-commit hook) fail
closed on an orphaned module file or a dangling export path. Scaffolding for
a whole new consumer repo lives in `templates/consumer`
(`nix flake new -t github:geoffdavis/nix-common#consumer ./my-config`).

## Lint (must pass before commit)

```sh
pre-commit run --all-files
# individually:
alejandra .
deadnix --fail .
statix check
```

`statix.toml` disables `repeated_keys` (W20) — the flat top-level key style
is intentional. CI runs the same chain via the reusable workflow at
`.github/workflows/lint.yml`; downstream repos call it via
`uses: geoffdavis/nix-common/.github/workflows/lint.yml@main`.

## Conventions

- alejandra format, deadnix-clean, statix-clean
- Conventional commits (`type(scope): subject`), single concern per commit
- `inherit (x) y;` over `y = x.y;`
- Never hardcode secrets. Public SSH keys are fine; everything else goes
  through `homeModules.op-json-secrets` or `homeModules.ssh`
  (`onepassword-ssh.keys`).
- New shared modules go under `modules/home/` (cross-platform unless noted)
  or `modules/{darwin,nixos}/` for OS-specific. Add the export to
  `flake.nix`. Internal helpers that aren't flake outputs go under
  `modules/shared/`. See [docs/module-contract.md](docs/module-contract.md).
- One `enable` option per module, all config behind `lib.mkIf cfg.enable`,
  `lib.mkDefault` on anything a host might override.

## Workflow

- `main` is PR-protected. Don't push directly. CI (`lint / lint`,
  `flake-check`) must pass before merge.
- Bumping in downstream repos: `nix flake update nix-common` then a PR in
  that repo. The cost of separating contexts is one bump per consumer.

## Avoid

- Adding lambda args (`pkgs,`, `lib,`) that the module body doesn't
  reference — deadnix flags them.
- Bypassing pre-commit with `--no-verify`.
- Anything that requires platform-specific paths (`/Applications/...`,
  `/opt/...`) without a darwin/linux fork or `lib.mkDefault` so consumers
  can override.

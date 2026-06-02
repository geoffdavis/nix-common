# Agent guide

Shared nix modules and pinned flake inputs for personal multi-host configs
(macOS / NixOS / standalone-home-manager Linux). Consumed by
[nix-personal](https://github.com/geoffdavis/nix-personal),
[nix-oceaneering](https://github.com/geoffdavis/nix-oceaneering), and
[nix-viasat](https://github.com/geoffdavis/nix-viasat) as a flake input.

## Build / test

```sh
nix flake check     # evaluates all module outputs
```

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
  `flake.nix`.

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

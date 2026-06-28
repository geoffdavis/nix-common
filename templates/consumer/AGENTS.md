# Agent guide

CHANGEME: one-paragraph description of what this repo manages (which
host(s), platform, GUI vs headless, any OS-layer tooling).

Shared modules + pinned inputs come from
[nix-common](https://github.com/geoffdavis/nix-common). Update via
`task update:common` (or `task update:branch` for a full refresh).

## Build / activate

```sh
task check     # build the closure without activating
task switch    # activate (run ON the target host)
```

`task --list` for the full menu.

## Lint (must pass before commit)

```sh
task lint    # pre-commit run --all-files
task fmt     # alejandra .
task fix     # statix fix . + deadnix --edit . (modifies files)
```

## Updating inputs

`nix-common` is referenced in two places that must stay in sync: `flake.lock`
and the `@<sha>` pin on the reusable lint workflow in
`.github/workflows/ci.yml`. Always use the `update:*` tasks, never bare `nix
flake update`:

```sh
task update:common          # update nix-common only (lock + workflow pin)
task update:common:commit   #   ^ + commit (body rolls up the nix-common changelog)
task update:flake           # update every input (also resyncs the workflow pin)
task update:flake:commit    #   ^ + commit
task update:branch          # fresh chore/flake-update-<ts> branch: common + flake, each committed
```

`update:branch` is the one-shot: it cuts a topic branch, commits the
nix-common bump (changelog in the body), then commits the remaining input
updates — ready to push + PR. Old names `bump:common` / `flake:update` remain
as aliases. `verify-pin` in CI fails closed if the lock and pin drift apart.

## Conventions

See [nix-common AGENTS.md](https://github.com/geoffdavis/nix-common/blob/main/AGENTS.md).
Summary: alejandra-format nix, statix/deadnix clean, conventional commits,
single concern per commit, never hardcode secrets (`onepassword-ssh.keys` +
`op-json-secrets` from nix-common).

## Workflow

- `main` is PR-protected; CI must pass before merge.
- PRs opened by `GITHUB_TOKEN` (the weekly `update-flake-lock` cron) don't
  auto-trigger CI. Re-run the `ci` workflow from the Actions tab on each bump
  PR before merging — `verify-pin` fails closed on lock/pin drift.

# CHANGEME: repo name

CHANGEME: short description.

Scaffolded from
[`nix-common#consumer`](https://github.com/geoffdavis/nix-common/tree/main/templates/consumer).

## Setup

```sh
nix flake new -t github:geoffdavis/nix-common#consumer ./my-config
cd my-config
pre-commit install
# edit flake.nix (hostname, user, modules), hosts/hostname/home.nix
task bump:common      # pin nix-common (lock + ci.yml workflow SHA)
task check
```

See [AGENTS.md](./AGENTS.md) for conventions and the bump workflow.

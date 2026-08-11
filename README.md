# nix-common

Shared nix modules and pinned flake inputs for my personal multi-host nix
configs — macOS (nix-darwin), NixOS, and standalone home-manager on Linux.
Downstream host repos are kept separate; this repo stays context-neutral and
names no specific hosts.

## Exports

This list is the public API: every name below is consumed by downstream
repos, so renames/removals are breaking changes that require a coordinated
bump in each consumer.

NixOS modules:

- `nixosModules.common` — base system config + home-manager wiring (requires
  `lazyvim` in `specialArgs`)
- `nixosModules.ansible-user` — dedicated automation user for ansible-managed
  hosts
- `nixosModules.nas-backup` — parameterized restic backup (repository, paths,
  btrfs snapshot staging, notify hooks)
- `nixosModules.nas-cache` — substituter + remote-builder client for the
  maintainer's NAS binary cache
- `nixosModules.cache-push` — post-build-hook push to that same cache
- `nixosModules.onepassword` — 1Password system pieces (polkit, groups)
- `nixosModules.steam` — Steam + gamescope
- `nixosModules.opendeck` — re-export of the opendeck-nix module

Darwin modules:

- `darwinModules.common` — base system config + home-manager wiring (requires
  `lazyvim` and `darwin` in `specialArgs`)
- `darwinModules.determinate-gc` — GC schedule for Determinate installs
- `darwinModules.nas-cache` / `darwinModules.cache-push` — same files as the
  nixos exports (platform-agnostic)

Home modules — imported into a host's home-manager user (cross-platform
unless noted):

- `homeModules.cli-tools` — shared CLI packages. NOTE: transitively imports
  `onepassword` (pinned 1Password CLI + GUI) and `terraform` — importing this
  module pulls both.
- `homeModules.pre-commit-hooks` — installs pre-commit's git hooks for a
  configured list of repos on every activation, and rewrites the `/nix/store`
  paths it bakes in so a GC sweep can't break `git commit`
- `homeModules.neovim` — LazyVim editor + global `EDITOR=nvim` (requires
  `lazyvim` in `extraSpecialArgs`)
- `homeModules.profile` — shared Linux `.profile` snippet management
- `homeModules.git` — git config + 1Password SSH commit signing
- `homeModules.zsh` — zsh + oh-my-zsh + fzf/zoxide baseline
- `homeModules.ssh` — 1Password SSH agent / `IdentityAgent` config
- `homeModules.onepassword` — pinned 1Password CLI (+ GUI on Linux x86_64)
- `homeModules.terraform` — pinned terraform
- `homeModules.graphics` — GUI / diagramming tools
- `homeModules.desktop-base` — cli-tools + git + graphics + ssh, plus
  GUI/fonts on an interactive desktop
- `homeModules.gnome-dconf` — GNOME dconf settings (extensions, scaling)
- `homeModules.gnome-desktop-base` — desktop-base + gnome-dconf +
  unfree-desktop (a GNOME Linux desktop)
- `homeModules.linux-headless-base` — cli-tools + git (headless Linux)
- `homeModules.unfree-desktop` — home-level `allowUnfree` predicate
- `homeModules.hyprland` — full Hyprland desktop session (waybar, walker,
  mako, wlogout, keybinds; options under `hyprland-desktop.*`)
- `homeModules.teams-for-linux` — Teams PWA wrapper + mqtt/OpenDeck wiring
- `homeModules.ai-tools` — pinned AI CLIs (claude-code, copilot-cli, codex;
  per-tool enable options)
- `homeModules.doc-tools` — document tooling (docx2pdf etc.)
- `homeModules.yazi` — yazi file manager (imports opt in; see file header)
- `homeModules.nix-index` — nix-index + comma with prebuilt database
- `homeModules.op-json-secrets` — patch JSON config files with 1Password
  secrets at activation time
- `homeModules.op-file-secrets` — write whole files from 1Password at
  activation time
- `homeModules.nas-cache` — substituter-only cache client for standalone
  home-manager hosts

Lib:

- `lib.zshInteractiveInit` — shared interactive-zsh init snippet builder
- `apps.<system>.sync-pin` — resync a consumer's CI workflow pin to its
  `flake.lock` (used by the consumer template's Taskfile)

Some inputs exist only to be `follows`-ed by consumers and are referenced
nowhere in this repo's own code: `nixpkgs-unstable`, `home-manager-nixos`,
`home-manager-darwin`. Don't "clean them up" — pin-providing is this flake's
job.

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

## Scaffolding (templates)

Two `nix flake` templates cover the common "new thing" operations:

```sh
# A whole new consumer repo (flake, Taskfile, CI, pre-commit, AGENTS/CLAUDE):
nix flake new -t github:geoffdavis/nix-common#consumer ./my-config

# A new shared home-manager module skeleton (or use `task new:module -- <name>`):
nix flake init -t github:geoffdavis/nix-common#home-module
```

New shared modules must satisfy the [module contract](docs/module-contract.md),
which `task contract` (and the `module-contract` CI job) enforce. See
[docs/refactoring-proposal.md](docs/refactoring-proposal.md) for the broader
guardrails roadmap.

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

## 1Password secret injection

The `homeModules.op-json-secrets` module patches JSON config files with secrets
fetched from 1Password at `home-manager switch` time. It uses `jq` to merge
only the declared keys, leaving all other content (including runtime-written
values) untouched.

### Setup in a consuming repo

1. Add the module to the relevant `homeManagerConfiguration.modules`:

```nix
modules = [
  nix-common.homeModules.op-json-secrets
  # … other modules …
];
```

2. Declare secrets in any module or host config in that configuration:

```nix
op-json-secrets = [
  {
    dest = "${config.home.homeDirectory}/.config/myapp/config.json";
    patches = [
      { path = ".password";    ref = "op://MyVault/MyItem/password"; }
      { path = ".api.token";  ref = "op://MyVault/APIItem/credential"; }
    ];
  }
];
```

3. Run a `home-manager switch` with an active 1Password session.  The CLI is
   resolved from PATH at activation time — no flake input or package override
   needed.  Missing or expired secrets are skipped with a warning; the switch
   does not fail.

### Static (non-secret) patches

For values that are not sensitive but still need to be present (e.g.
`disableGpu: false`), use `home.activation` with `jq` directly rather than
this module.  Keeping secrets and static config separate makes the intent
clear.

### Relationship to `homeModules.ssh`

The `ssh` module sets up the 1Password SSH agent so that `op` authentication
works via biometric unlock.  With both modules active, `home-manager switch`
will automatically populate JSON secrets as long as 1Password is unlocked —
no interactive `op signin` required.

## Updating consumers

When you push a change to this repo, downstream consumers pick it up
explicitly with:

```sh
nix flake update nix-common
sudo darwin-rebuild switch --flake .   # or home-manager switch
```

That two-step is the cost of separating contexts — work-laptop repos
don't leak into each other, but cross-cutting updates require a bump.

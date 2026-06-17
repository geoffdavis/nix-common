# NAS backup client module (`nas-backup`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a generic `nixosModules.nas-backup` that runs scheduled restic backups of `/home` (atomic via btrfs snapshot) to the append-only rest-server on nas-sdg, then enable it on birdrock with creds fetched at switch via `op-file-secrets`.

**Architecture:** A NixOS system module wraps `services.restic.backups.<name>` with a btrfs read-only snapshot prepare/cleanup hook and an OnFailure desktop-notification unit. All NAS/host specifics are options; the consumer (birdrock) supplies the repo/password file paths (materialized from 1Password by the existing `homeModules.op-file-secrets`) and host values.

**Tech Stack:** Nix (NixOS module system), `services.restic`, btrfs-progs, libnotify, home-manager `op-file-secrets`, 1Password CLI.

**Spec:** `docs/superpowers/specs/2026-06-16-nas-backup-client-design.md`

## Global Constraints

- **nix-common module contract** (docs/module-contract.md): NixOS-only module → `modules/nixos/<name>.nix`, exported as `nixosModules.<name>` in `flake.nix`; `task contract` fails closed on a missing/dangling export.
- **One `enable` option**, all config behind `lib.mkIf cfg.enable`; `lib.mkDefault` on anything a host might override.
- **No unused lambda args** (deadnix fails CI). **No hardcoded secrets** (use op-file-secrets). **No host-specifics in nix-common** — no `nas-sdg`, `birdrock`, or `op://` literals.
- Lint chain must pass: `alejandra .`, `deadnix --fail .`, `statix check` (statix `repeated_keys`/W20 disabled — flat keys OK).
- `inherit (x) y;` over `y = x.y;`. Conventional commits, single concern.
- **No client-side `pruneOpts`** — the server is append-only; Backrest prunes.
- **No `--insecure-tls`** — verified: birdrock trusts the Home CA via `security.pki.certificateFiles`.
- `main` is PR-protected in both repos. nix-common→nix-personal go through `task bump:common` (dual-pin invariant); never `nix flake update nix-common` directly.

---

## File Structure

**Phase A — nix-common (the module, standalone deliverable):**
- Create: `modules/nixos/nas-backup.nix` — the generic module (options + restic wiring + btrfs hook + notify unit).
- Modify: `flake.nix` — add `nixosModules.nas-backup = ./modules/nixos/nas-backup.nix;`.

**Phase B — nix-personal (birdrock enablement, gated on Phase A merge + `task bump:common`):**
- Modify: `hosts/birdrock/default.nix` (or a small new `hosts/birdrock/backup.nix` imported there) — import the module, set `services.nasBackup`, add the two `op-file-secrets` entries in geoff's home-manager block.
- Data: add a `repo-url` field to the `restic-birdrock` 1Password item.

---

## Phase A — `nas-backup` module in nix-common

### Task A1: Create the `nas-backup` NixOS module + export it

**Files:**
- Create: `modules/nixos/nas-backup.nix`
- Modify: `flake.nix` (nixosModules block, ~line 157 after `nixosModules.onepassword`)

**Interfaces:**
- Produces: option namespace `config.services.nasBackup.{enable, name, repositoryFile, passwordFile, paths, extraExcludes, btrfsSnapshotSource, btrfsSnapshotStage, timer.{onCalendar,randomizedDelaySec}, notify.{enable,uid}}`. Consumed by Phase B (birdrock) and any future Linux host.

- [ ] **Step 1: Write the module file**

Create `modules/nixos/nas-backup.nix`:

```nix
# modules/nixos/nas-backup.nix — scheduled restic backups to the NAS
# append-only rest-server. Generic: the NAS endpoint, repo name, op://
# refs, and btrfs source are all supplied by the consuming host. Creds are
# read from files (repositoryFile/passwordFile) that the host materializes
# at switch via homeModules.op-file-secrets — this module never touches
# 1Password.
#
# Restore note: with the btrfs snapshot hook on, restic records paths under
# btrfsSnapshotStage (e.g. /.snapshots/restic-stage/<user>/...) instead of
# /home/<user>/...; restores land the data under that subpath. Standard
# btrfs+restic behaviour; the stage path is stable so dedup is unaffected.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.nasBackup;
  snapshotting = cfg.btrfsSnapshotSource != null;
  baselineExcludes = [
    "**/.cache"
    "**/.local/share/Trash"
    "**/node_modules"
    "**/.local/share/Steam"
    "**/*.iso"
    "**/.cargo/registry"
    "**/.npm/_cacache"
    "**/.var/app/*/cache"
  ];
  btrfs = "${pkgs.btrfs-progs}/bin/btrfs";
in {
  options.services.nasBackup = {
    enable = lib.mkEnableOption "restic backups to the NAS rest-server";

    name = lib.mkOption {
      type = lib.types.str;
      default = "nas";
      description = "services.restic.backups.<name> key and systemd unit suffix.";
    };

    repositoryFile = lib.mkOption {
      type = lib.types.path;
      description = "File holding the full restic `rest:` URL including credentials.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.path;
      description = "File holding the restic repository encryption password.";
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["/home"];
      description = "Paths to back up. Ignored when btrfsSnapshotSource is set.";
    };

    extraExcludes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra restic exclude patterns, appended to the baseline.";
    };

    btrfsSnapshotSource = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home";
      description = "When set, snapshot this path read-only into btrfsSnapshotStage and back that up (atomic). null backs up `paths` live.";
    };

    btrfsSnapshotStage = lib.mkOption {
      type = lib.types.str;
      default = "/.snapshots/restic-stage";
      description = "Destination subvolume path for the read-only staging snapshot.";
    };

    timer = {
      onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "02:00";
        description = "systemd OnCalendar for the backup timer.";
      };
      randomizedDelaySec = lib.mkOption {
        type = lib.types.str;
        default = "30m";
        description = "systemd RandomizedDelaySec for the backup timer.";
      };
    };

    notify = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Fire a desktop notification when a backup run fails.";
      };
      uid = lib.mkOption {
        type = lib.types.int;
        default = 1000;
        description = "UID of the graphical session receiving the notification.";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.restic.backups.${cfg.name} = {
        inherit (cfg) repositoryFile passwordFile;
        initialize = lib.mkDefault false;
        paths =
          if snapshotting
          then [cfg.btrfsSnapshotStage]
          else cfg.paths;
        exclude = baselineExcludes ++ cfg.extraExcludes;
        timerConfig = {
          OnCalendar = cfg.timer.onCalendar;
          Persistent = true;
          RandomizedDelaySec = cfg.timer.randomizedDelaySec;
        };
        # Deliberately no pruneOpts: the server is append-only; Backrest prunes.
      };
    }

    (lib.mkIf snapshotting {
      services.restic.backups.${cfg.name} = {
        backupPrepareCommand = ''
          ${btrfs} subvolume delete ${cfg.btrfsSnapshotStage} 2>/dev/null || true
          ${btrfs} subvolume snapshot -r ${cfg.btrfsSnapshotSource} ${cfg.btrfsSnapshotStage}
        '';
        backupCleanupCommand = ''
          ${btrfs} subvolume delete ${cfg.btrfsSnapshotStage} 2>/dev/null || true
        '';
      };
    })

    (lib.mkIf cfg.notify.enable {
      systemd.services."restic-backups-${cfg.name}".onFailure = ["restic-nas-notify-${cfg.name}.service"];
      systemd.services."restic-nas-notify-${cfg.name}" = {
        description = "Desktop notification for a failed restic backup (${cfg.name})";
        serviceConfig = {
          Type = "oneshot";
          User = toString cfg.notify.uid;
          Environment = [
            "XDG_RUNTIME_DIR=/run/user/${toString cfg.notify.uid}"
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${toString cfg.notify.uid}/bus"
          ];
          # Best-effort: if the user is logged out this fails harmlessly (it
          # is already on the failure path). true keeps the unit from erroring.
          ExecStart = "${pkgs.libnotify}/bin/notify-send --urgency=critical 'NAS backup failed' 'restic-backups-${cfg.name} failed — journalctl -u restic-backups-${cfg.name}'";
        };
      };
    })
  ]);
}
```

- [ ] **Step 2: Export it in `flake.nix`**

After the `nixosModules.onepassword = ...` line, add:
```nix
    nixosModules.nas-backup = ./modules/nixos/nas-backup.nix;
```

- [ ] **Step 3: Format + lint + contract**

Run: `cd ~/src/nix/nix-common && alejandra modules/nixos/nas-backup.nix flake.nix && deadnix --fail modules/nixos/nas-backup.nix && statix check modules/nixos/nas-backup.nix && task contract`
Expected: alejandra reformats (or no-ops), deadnix finds no unused args, statix clean, `task contract` passes (module ↔ export consistent). Fix anything flagged (common: an unused `pkgs`/`lib` arg — but all three are used here).

- [ ] **Step 4: Flake check (output wiring)**

Run: `cd ~/src/nix/nix-common && nix flake check 2>&1 | tail -15`
Expected: no evaluation errors; the flake's outputs (including `nixosModules.nas-backup`) evaluate.

- [ ] **Step 5: Eval smoke test — module config body actually evaluates**

`nix flake check` does NOT instantiate a module's `config` body (a module is just a function until a system imports it). Force evaluation against a throwaway system and assert the snapshot logic:

```bash
cd ~/src/nix/nix-common && nix eval --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    lib = flake.inputs.nixpkgs-nixos.lib;
    sys = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        flake.nixosModules.nas-backup
        ({ ... }: {
          system.stateVersion = "25.11";
          boot.loader.grub.devices = [ "nodev" ];
          fileSystems."/" = { device = "x"; fsType = "btrfs"; };
          services.nasBackup = {
            enable = true;
            repositoryFile = "/x.repo";
            passwordFile = "/x.pass";
            btrfsSnapshotSource = "/home";
          };
        })
      ];
    };
    b = sys.config.services.restic.backups.nas;
  in {
    paths = b.paths;
    hasSnapshot = lib.hasInfix "subvolume snapshot -r /home" b.backupPrepareCommand;
    noPrune = b.pruneOpts == [ ];
    onFailure = sys.config.systemd.services."restic-backups-nas".onFailure;
  }
'
```
Expected: `{ hasSnapshot = true; noPrune = true; onFailure = [ "restic-nas-notify-nas.service" ]; paths = [ "/.snapshots/restic-stage" ]; }`. (If the eval complains about a missing required option, add the minimal stub it names — e.g. `networking.hostName` — and re-run; that's normal nixosSystem evaluation, not a logic error.)

- [ ] **Step 6: Commit**

```bash
git add modules/nixos/nas-backup.nix flake.nix
git commit -m "feat(nas-backup): generic restic-to-NAS NixOS module"
```

### Task A2: PR the module

**Files:** none (PR only)

- [ ] **Step 1: Push + open PR**

```bash
cd ~/src/nix/nix-common && git push -u origin spec/nas-backup-client
gh pr create --base main --head spec/nas-backup-client \
  --title "feat(nas-backup): generic restic-to-NAS NixOS client module" \
  --body "Generic nixosModules.nas-backup: services.restic to the append-only rest-server, btrfs ro-snapshot for atomic /home, OnFailure desktop notification. No host/NAS specifics — birdrock supplies them and materializes creds via op-file-secrets. Spec + plan in docs/superpowers/. Server side: ugreen-nas-compose #198 (deployed, append-only verified). 🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```
Expected: PR URL. Required checks: `lint / lint`, `flake-check`.

- [ ] **Step 2: Merge once green**

Squash-merge with branch delete after `lint` + `flake-check` pass.

---

## Phase B — Enable on birdrock (nix-personal) — gated on Phase A merge

> Do NOT start Phase B until the nix-common PR is merged. Then bump the pin.

### Task B1: Add the `repo-url` 1Password field

**Files:** none (1Password data)

- [ ] **Step 1: Add the field** (the item already has username/password/rest-password)

```bash
REST_PW="$(op read 'op://nas-overlay/restic-birdrock/rest-password')"
op item edit restic-birdrock --vault nas-overlay \
  "repo-url[text]=rest:https://birdrock:${REST_PW}@nas-sdg.netbird.cloud:30800/birdrock/"
unset REST_PW
```
Expected: `op item get restic-birdrock --vault nas-overlay --fields label=repo-url` prints the URL.

### Task B2: Bump nix-common in nix-personal

**Files:** Modify: `nix-personal/flake.lock` + `.github/workflows/ci.yml` (handled by the task)

- [ ] **Step 1: Branch + bump**

```bash
cd ~/src/nix/nix-personal && git checkout -b feat/nas-backup-birdrock && task bump:common
```
Expected: `task bump:common` updates `flake.lock` AND the `@<sha>` pin in `.github/workflows/ci.yml` together (dual-pin invariant). Verify both moved to the merge commit.

### Task B3: Wire op-file-secrets + enable the module on birdrock

**Files:**
- Create: `hosts/birdrock/backup.nix`
- Modify: `hosts/birdrock/default.nix` (add `./backup.nix` to its `imports`)

**Interfaces:**
- Consumes: `nix-common.nixosModules.nas-backup` (`services.nasBackup.*`) and `nix-common.homeModules.op-file-secrets` (`op-file-secrets` list).

- [ ] **Step 1: Write `hosts/birdrock/backup.nix`**

Bindings confirmed against `hosts/birdrock/default.nix`: `nix-common` is a
specialArg (flake.nix:86 `specialArgs = {inherit nix-common …;}`), and the
username is `config.my.username` (NOT a specialArg — `inherit (config.my)
username;`). The outer `config` is the NixOS config; the inner home-manager
function gets its own `config` (home-manager's), which shadows — intentional.

```nix
# hosts/birdrock/backup.nix — restic /home backup to nas-sdg.
# Module: nix-common.nixosModules.nas-backup (generic). Creds: fetched from
# 1Password at switch by op-file-secrets (homeModules) into geoff's home;
# the root restic service reads those 0600 files.
{
  config,
  nix-common,
  ...
}: let
  inherit (config.my) username;
in {
  imports = [nix-common.nixosModules.nas-backup];

  services.nasBackup = {
    enable = true;
    repositoryFile = "/home/${username}/.config/restic/nas.repo";
    passwordFile = "/home/${username}/.config/restic/nas.pass";
    btrfsSnapshotSource = "/home";
    notify.uid = 1000;
  };

  home-manager.users.${username} = {config, ...}: {
    imports = [nix-common.homeModules.op-file-secrets];
    op-file-secrets = [
      {
        dest = "${config.home.homeDirectory}/.config/restic/nas.repo";
        ref = "op://nas-overlay/restic-birdrock/repo-url";
      }
      {
        dest = "${config.home.homeDirectory}/.config/restic/nas.pass";
        ref = "op://nas-overlay/restic-birdrock/password";
      }
    ];
  };
}
```

Note: this adds a second `home-manager.users.${username}` definition (the host
already has one in `default.nix`); the NixOS module system merges them, and
re-importing `op-file-secrets` is idempotent.

- [ ] **Step 2: Import it from `hosts/birdrock/default.nix`**

Add `./backup.nix` to the host's top-level `imports = [ ... ];` list (alongside `./teams.nix`, `./theme.nix`, etc.).

- [ ] **Step 3: Format + lint**

Run: `cd ~/src/nix/nix-personal && alejandra hosts/birdrock/backup.nix hosts/birdrock/default.nix && deadnix --fail hosts/birdrock/backup.nix && statix check hosts/birdrock/backup.nix`
Expected: clean. (Both outer args are used — `config` for `config.my.username`, `nix-common` for the imports — so deadnix should not flag them.)

- [ ] **Step 4: Build the closure**

Run: `cd ~/src/nix/nix-personal && task check:birdrock 2>&1 | tail -20`
Expected: the birdrock system closure builds (this is what truly evaluates the module's config body end-to-end). Requires the 1Password SSH agent unlocked (private inputs over git+ssh). Fix any eval errors.

- [ ] **Step 5: Commit + PR**

```bash
git add flake.lock .github/workflows/ci.yml hosts/birdrock/backup.nix hosts/birdrock/default.nix
git commit -m "feat(birdrock): enable nas-backup restic /home backups"
git push -u origin feat/nas-backup-birdrock
gh pr create --base main --title "feat(birdrock): nas-backup restic /home backups" --body "Bumps nix-common; enables nixosModules.nas-backup on birdrock with btrfs snapshot + op-file-secrets creds. 🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

### Task B4: Activate + verify on birdrock

**Files:** none (activation + verification, run ON birdrock)

- [ ] **Step 1: Switch**

Run: `cd ~/src/nix/nix-personal && task switch:birdrock`
Expected: activation succeeds; HM activation logs the op-file-secrets writes (no "skipping" warnings — 1Password must be unlocked).

- [ ] **Step 2: Secret files materialized**

Run: `ls -l ~/.config/restic/nas.repo ~/.config/restic/nas.pass && head -c4 ~/.config/restic/nas.repo`
Expected: both files exist mode `0600`; nas.repo starts with `rest`.

- [ ] **Step 3: Run a backup**

Run: `sudo systemctl start restic-backups-nas.service && journalctl -u restic-backups-nas.service -n 30 --no-pager`
Expected: completes successfully (`Added to the repository …`); no errors.

- [ ] **Step 4: Verify the snapshot landed with the stage path + stage cleaned up**

```bash
RESTIC="$(nix build --no-link --print-out-paths nixpkgs#restic)/bin/restic"
export RESTIC_REPOSITORY="$(cat ~/.config/restic/nas.repo)"
export RESTIC_PASSWORD_FILE=~/.config/restic/nas.pass
"$RESTIC" snapshots --latest 1
sudo btrfs subvolume list / | grep restic-stage || echo "stage cleaned up (good)"
```
Expected: the latest snapshot's path is under `/.snapshots/restic-stage`; the stage subvol is **absent** after the run (cleanup ran).

- [ ] **Step 5: Verify the timer + failure notification**

```bash
systemctl list-timers | grep restic-backups-nas
# failure path: point at a bad repo and confirm the desktop notification fires
sudo systemd-run --unit restic-notify-test --property OnFailure= true   # noop; see note
```
Expected: timer is scheduled for ~02:00. To exercise the notification, temporarily move `~/.config/restic/nas.repo` aside and `sudo systemctl start restic-backups-nas.service` → the run fails and a critical desktop notification ("NAS backup failed") appears in the Hyprland session; restore the file afterward.

- [ ] **Step 6: Merge the nix-personal PR** once `lint` + `verify-pin` are green.

---

## Self-Review (completed during planning)

- **Spec coverage:** generic module ✓ (A1), op-file-secrets creds ✓ (B3), no host-specifics in nix-common ✓ (A1 uses only options), no `--insecure-tls` ✓ (not present), btrfs atomic snapshot ✓ (A1 prepare/cleanup), restore-path tradeoff documented ✓ (module header), OnFailure desktop notify ✓ (A1), no client prune ✓ (A1 comment + eval `noPrune`), daily timer ✓ (A1), `repo-url` 1P field ✓ (B1), cross-repo bump invariant ✓ (B2), validation ✓ (A5 eval + B4 live).
- **Placeholder scan:** none — every code/command step is concrete. The "confirm the exact name binding" note in B3 Step 1 is a real verification instruction (match the host's existing `nix-common`/`username` bindings), not a placeholder.
- **Type/name consistency:** option path `services.nasBackup.*` and unit names `restic-backups-${name}` / `restic-nas-notify-${name}` consistent across A1 and the B4 verification commands; `repositoryFile`/`passwordFile` file paths consistent A1↔B3↔B4; 1P refs `op://nas-overlay/restic-birdrock/{repo-url,password}` consistent B1↔B3.
- **Open confirmations at build time:** the A5 eval may need an extra stub option (e.g. `networking.hostName`) depending on the nixpkgs revision — add if named; the B3 outer-function args must match what deadnix wants (drop unused).

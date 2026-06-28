# NixOS restic backup client module (`nas-backup`) — design

**Status:** Design approved 2026-06-16
**Repos:** `nix-common` (the module) + `nix-personal` (birdrock enablement)
**Server side (already shipped):** `ugreen-nas-compose` PR #198 — append-only
`rest-server` + Backrest on nas-sdg. Append-only verified live. This is the
**client half**: the laptop pushing scheduled `/home` backups to that server.

## Problem

birdrock (NixOS, btrfs) has no backup. The server (append-only restic REST on
`nas-sdg.netbird.cloud:30800`, repo `tank/backups/restic/birdrock`, riding
existing ZFS snapshots + offsite replication) is deployed and reachable. We
need a NixOS module that runs scheduled, encrypted restic backups of `/home`
to it — reusable for future Linux hosts, with zero host-specifics baked into
`nix-common`.

## Scope

**In:** a generic `nixosModules.nas-backup` module + birdrock enablement.
`/home` (+ configurable paths), btrfs-snapshot consistency, secrets via the
existing `op-file-secrets` mechanism, daily timer, failure notification.

**Out (YAGNI / deliberate):**
- Client-side prune/retention — the server is append-only; Backrest prunes.
- Non-NixOS Linux clients — same server, but ansible-delivered
  restic, a separate effort.
- Restore tooling — `restic restore` / Backrest UI already cover it.

## Decisions (locked)

| Decision | Choice | Why |
|----------|--------|-----|
| Tool | `services.restic.backups` (NixOS) | first-class; root for btrfs + reading `/home` |
| TLS | **No `--insecure-tls`** | verified live: restic trusts the cert via birdrock's `security.pki.certificateFiles` (Home CA chain) |
| Secrets | **`op-file-secrets` at switch** | the repo's blessed pattern; NO one-off manual files |
| Repo URL with creds | a `repo-url` **1Password field** | op-file-secrets writes a field verbatim (can't template a URL) |
| Module placement | generic `nixosModules.nas-backup` | host-specifics (NAS endpoint, op refs, repo name, btrfs source) live in the consumer |
| /home consistency | btrfs read-only snapshot hook | atomic, no torn files |
| Monitoring | `OnFailure` → desktop `notify-send` | a silently-stopped backup is the real risk |
| Retention | none on client | append-only server; Backrest curates |

## Architecture

```
task switch:birdrock  (integrated home-manager runs as geoff, 1Password authed)
   │
   ├─ op-file-secrets (homeModules.op-file-secrets) — EXISTING module
   │     op://nas-overlay/restic-birdrock/repo-url  → ~/.config/restic/nas.repo  (0600)
   │     op://nas-overlay/restic-birdrock/password  → ~/.config/restic/nas.pass  (0600)
   │     (graceful: locked/missing → skip file, switch never fails)
   │
   └─ nixosModules.nas-backup (NEW, generic) — system layer
         services.restic.backups.nas:
           repositoryFile = <nas.repo>   passwordFile = <nas.pass>
           backupPrepareCommand:  btrfs ro-snapshot /home → /.snapshots/restic-stage
           paths = [ /.snapshots/restic-stage ]   (frozen, atomic)
           excludes = depth-agnostic **/ patterns
           backupCleanupCommand:  btrfs subvolume delete the stage
           timer = daily 02:00, Persistent, 30m jitter ; NO forget/prune
         systemd onFailure → notify-send into uid 1000's Hyprland session

   restic-backups-nas.service (root, 02:00) → rest:https://birdrock:***@nas-sdg.netbird.cloud:30800/birdrock/
```

Root (system) restic reads the `0600` files geoff's HM activation wrote — root
reads user files; safe. The timer fires at 02:00, never at switch, so the
files always exist by run time.

## Component 1 — `nix-common/modules/nixos/nas-backup.nix`

Exported `nixosModules.nas-backup`. One `enable` gate; everything behind
`lib.mkIf cfg.enable`; `lib.mkDefault` on overridables. **No** `nas-sdg`,
`birdrock`, or `op://` literals anywhere — all via options.

Options under `services.nasBackup`:

| Option | Type | Default | Notes |
|--------|------|---------|-------|
| `enable` | bool | false | |
| `name` | str | `"nas"` | the `services.restic.backups.<name>` key |
| `repositoryFile` | path | — (required) | file holding the full `rest:` URL incl. creds |
| `passwordFile` | path | — (required) | repo encryption key file |
| `paths` | listOf str | `[ "/home" ]` | overridden internally when the snapshot hook is on |
| `extraExcludes` | listOf str | `[]` | appended to the baseline |
| `btrfsSnapshotSource` | nullOr str | `null` | e.g. `/home`; null ⇒ no snapshot, back up `paths` live |
| `btrfsSnapshotStage` | str | `/.snapshots/restic-stage` | ro snapshot dest (same fs) |
| `timer.onCalendar` | str | `"02:00"` | |
| `timer.randomizedDelaySec` | str | `"30m"` | |
| `notify.enable` | bool | true | OnFailure desktop notification |
| `notify.uid` | int | `1000` | target user's `XDG_RUNTIME_DIR=/run/user/<uid>` |

Baseline excludes (depth-agnostic so they work under `/home` **or** the stage
root): `**/.cache`, `**/.local/share/Trash`, `**/node_modules`,
`**/.local/share/Steam`, `**/*.iso`, `**/.cargo/registry`, `**/.npm/_cacache`,
`**/.var/app/*/cache`. (Refine in the plan; keep conservative.)

Config it produces:
- `services.restic.backups.${name}` with `repositoryFile`, `passwordFile`,
  `paths` (= `[btrfsSnapshotStage]` when snapshotting, else `cfg.paths`),
  `exclude`, `timerConfig`, and **no** `pruneOpts`.
- btrfs hook (when `btrfsSnapshotSource != null`):
  - `backupPrepareCommand`: delete a stale stage, then
    `btrfs subvolume snapshot -r ${source} ${stage}`.
  - `backupCleanupCommand`: `btrfs subvolume delete ${stage}` (best-effort).
  - `${pkgs.btrfs-progs}` on the unit path.
- `notify` (when enabled): a oneshot `restic-nas-notify` unit set as the
  restic service's `onFailure`, running `notify-send` as the target uid with
  `XDG_RUNTIME_DIR=/run/user/<uid>` (best-effort; failure to notify must not
  fail the unit). `${pkgs.libnotify}` on the path.

**Restore-path tradeoff (documented in the module header):** with the snapshot
hook, restic records paths under `${btrfsSnapshotStage}/…` rather than
`/home/…`. Standard btrfs+restic behaviour; restore lands the data under that
subpath. Dedup/incrementals are unaffected because the stage path is stable.

## Component 2 — birdrock enablement (`nix-personal`)

In geoff's home-manager block (where other `homeModules` are imported):
```nix
op-file-secrets = [
  { dest = "${config.home.homeDirectory}/.config/restic/nas.repo";
    ref  = "op://nas-overlay/restic-birdrock/repo-url"; }
  { dest = "${config.home.homeDirectory}/.config/restic/nas.pass";
    ref  = "op://nas-overlay/restic-birdrock/password"; }
];
```
(Import `nix-common.homeModules.op-file-secrets` if not already imported.)

In birdrock's system config:
```nix
imports = [ nix-common.nixosModules.nas-backup ];
services.nasBackup = {
  enable = true;
  repositoryFile = "/home/geoff/.config/restic/nas.repo";
  passwordFile   = "/home/geoff/.config/restic/nas.pass";
  btrfsSnapshotSource = "/home";
  notify.uid = 1000;
};
```

One-time data step (operator / I can do it): add a **`repo-url`** field to the
`restic-birdrock` 1Password item =
`rest:https://birdrock:<rest-password>@nas-sdg.netbird.cloud:30800/birdrock/`.

## Cross-repo sequencing

1. **nix-common:** add `modules/nixos/nas-backup.nix`, export in `flake.nix`,
   `task contract && task fmt && task lint`, `nix flake check`. Branch + PR
   (main protected; CI = lint + flake-check).
2. **1Password:** add the `repo-url` field to `restic-birdrock`.
3. **nix-personal:** `task bump:common`, wire op-file-secrets + enable the
   module on birdrock. Branch + PR.
4. **Activate:** `task switch:birdrock`; verify (below).

## Validation

- nix-common: `nix flake check`, `task contract` (module↔export), lint clean.
- birdrock: `task check:birdrock` builds; after switch:
  - `~/.config/restic/nas.{repo,pass}` exist, `0600`.
  - `systemctl start restic-backups-nas.service` → succeeds; a new snapshot
    with a `/.snapshots/restic-stage/geoff/...` path appears in `restic
    snapshots`; the stage subvol is gone afterward (`btrfs subvolume list /`).
  - Force a failure (e.g. break the repo file) → desktop notification fires;
    `restic snapshots` still consistent (`restic check`).
  - Timer scheduled: `systemctl list-timers | grep restic`.

## Open items for the plan

- Final baseline exclude list (validate patterns don't over-exclude real data).
- notify-send env for Hyprland/Wayland (XDG_RUNTIME_DIR is the key; confirm the
  user bus / WAYLAND_DISPLAY needs at run time).
- Whether `services.restic` needs `initialize = true` for first run (repo is
  already initialized server-side from the deploy proof — likely `false`, but
  confirm so a fresh host self-initializes).

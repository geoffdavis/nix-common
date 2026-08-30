---
name: sops-secrets
description: Use when reading, adding, updating, moving, or escrowing any sops-encrypted secret in the nix fleet repos — anything under hosts/<host>/secrets/*.yaml in nix-personal. Triggers on "add a secret", "edit sops", "sops set", "populate secrets.yaml", "add an htpasswd line", "rotate this token", "escrow this password/token", or any task blocked on "no age identity" / "failed to get the data key" / "no master key was able to decrypt". Also read this BEFORE any command containing `sops` in a nix repo.
---

# Editing sops secrets in the nix fleet

Secrets live in **`nix-personal`** at `hosts/<host>/secrets/*.yaml`, sops-encrypted
and keyed per-host on that host's own SSH ed25519 key (so each host decrypts its
own secrets at activation). `.sops.yaml` at the repo root has the recipient list.
`nix-common`, `nix-viasat` and `nix-oceaneering` currently hold no secrets.

**Authoring** (editing from a laptop rather than on a host) needs a separate age
identity, kept in 1Password — see "The authoring key" below.

---

## Rule 1 — key names are PLAINTEXT. Never decrypt to discover a name.

sops encrypts **values only**. Every key sits in the clear:

```yaml
restic-htpasswd: ENC[AES256_GCM,data:...]
```

So to learn what a field is called, what fields exist, or whether a key is
already present, **read the encrypted file directly** — no `sops`, no `op`, no
key material, no risk:

```sh
grep -oE '^[a-zA-Z0-9_.-]+:' hosts/nas-sdg/secrets/secrets.yaml
```

This is the single highest-value line in this skill. Both incidents below began
with decrypting a file merely to find out a field's name.

## Rule 2 — never decrypt a whole file, and never filter decrypted output

Use `--extract` to pull exactly one key:

```sh
op run --no-masking -- sops decrypt --extract '["the-key"]' hosts/<host>/secrets/secrets.yaml
```

**If you find yourself piping a full decrypt through `grep`/`sed`/`awk` to
"filter out the secrets", you have already lost.** A filter that drops
block-scalar (`|`) values still passes every single-line value straight through.
That is exactly how 9 unrelated live secrets landed in a transcript on
2026-08-30. There is no safe filter — there is only not decrypting the file.

## Rule 3 — verify by COUNTING, never by printing

After a write, prove it worked without putting plaintext on screen:

```sh
op run --no-masking -- bash -c '
  v=$(sops decrypt --extract "[\"restic-htpasswd\"]" hosts/nas-sdg/secrets/secrets.yaml)
  echo "lines:      $(printf "%s\n" "$v" | grep -c .)"
  echo "exact match: $(printf "%s\n" "$v" | grep -Fxc "$EXPECTED_LINE")"
'
```

`grep -c`, `grep -Fxc`, `wc -l` — all safe. `cat`, bare `grep`, `echo "$v"` — not.

---

## The authoring key

1Password item **`sops-authoring-key`**, vault **`nas-overlay`**, field
`credential` (holds the whole `age-keygen` file: comment lines **and** the
`AGE-SECRET-KEY-1…` line).

**Never `op read` / `op item get` this to stdout or a file.** That is what leaked
it in 2026-08-09 and forced a full key rotation. `op run` injects it into a
subprocess environment where neither you nor the transcript ever sees it:

```sh
export SOPS_AGE_KEY="op://nas-overlay/sops-authoring-key/credential"
op run --no-masking -- sops <command>
```

- `--no-masking` is **required** — `op run`'s default masking replaces the value
  with asterisks in output, corrupting multi-line key material passed onward.
- `SOPS_AGE_KEY` works here because the field holds the full keygen file. If you
  ever write it to a file instead, use `SOPS_AGE_KEY_FILE` (and `umask 077` in
  the *same subshell*) — but prefer `op run` and no file at all.
- Every `op` call raises an approval dialog, so **plan the whole sequence and
  front-load it**: one `op run` doing read→modify→write beats three. Never
  retry-loop; a second prompt for the same secret reads as a malfunction.
- Inside a sandboxed shell `op` can return **empty output with exit 0**. That
  looks like "no such item" but is not — re-run unsandboxed before concluding
  anything is missing.

---

## Recipes

### Add or replace one key

`sops set` decrypts, patches one path, re-encrypts — never emitting plaintext.
Use `--value-stdin` so the value is **not** visible in `ps`:

```sh
export SOPS_AGE_KEY="op://nas-overlay/sops-authoring-key/credential"
printf '%s' "$VALUE" | jq -Rs . \
  | op run --no-masking -- sops set --value-stdin hosts/<host>/secrets/secrets.yaml '["the-key"]'
```

The index is a JSON path expression; the value must be a JSON-encoded string,
which is what `jq -Rs .` produces.

### Append a line to a multi-line value (e.g. an htpasswd file)

Read-modify-write in **one** `op run`. Pass literal values via the environment so
the shell cannot expand them — a bcrypt hash like `$2y$05$…` **will** be mangled
by `$2y` / `$05` expansion if you interpolate it directly:

```sh
export SOPS_AGE_KEY="op://nas-overlay/sops-authoring-key/credential"
export NEW_LINE='someuser:$2y$05$abcdef...'          # single quotes, always
op run --no-masking -- bash -c '
  set -euo pipefail
  cur=$(sops decrypt --extract "[\"restic-htpasswd\"]" hosts/nas-sdg/secrets/secrets.yaml)
  printf "%s\n%s\n" "$cur" "$NEW_LINE" | jq -Rs . \
    | sops set --value-stdin hosts/nas-sdg/secrets/secrets.yaml "[\"restic-htpasswd\"]"
'
```

`$(...)` strips trailing newlines, so `printf "%s\n%s\n"` normalizes the result
whether or not the stored value ended in one.

### Move a key to another file (splitting by concern)

```sh
op run --no-masking -- bash -c '
  sops decrypt --extract "[\"K\"]" hosts/<host>/secrets/secrets.yaml | jq -Rs . \
    | sops set --value-stdin hosts/<host>/secrets/<concern>.yaml "[\"K\"]"
  sops unset hosts/<host>/secrets/secrets.yaml "[\"K\"]"
'
```

Bootstrap a new file first (recipients come from `.sops.yaml`'s `path_regex`,
which globs the whole `secrets/` directory — **no `.sops.yaml` edit needed**):

```sh
printf 'placeholder: x\n' > hosts/<host>/secrets/<concern>.yaml
op run --no-masking -- sops encrypt --in-place hosts/<host>/secrets/<concern>.yaml
# … move keys in, then:
op run --no-masking -- sops unset hosts/<host>/secrets/<concern>.yaml '["placeholder"]'
```

On the consuming side, sops-nix merges a bare `sopsFile` override with the
secret's real declaration elsewhere (proven in `modules/nas/spoke.nix`), so one
central mapping in `hosts/<host>/secrets.nix` covers a whole split:

```nix
sops.secrets = lib.mapAttrs (_: c: {sopsFile = ./secrets + "/${c}.yaml";}) {
  "restic-htpasswd" = "backup";
};
```

### Generate a new secret

`openssl rand -hex 24` / `head -c` is fine. Keep plaintext in a job-scoped tmp
dir (never `/tmp`), `chmod 600`, and delete it the moment it is in sops. macOS
has no `shred`; `rm -f` is the fallback.

### Escrow into 1Password

Convention: vault **`nas-overlay`**, one item per app, title `"<host> <app>"`.
Do decrypt→extract→`op item create` inside **one** `op run` so the value only
ever exists in that subprocess:

```sh
op run --no-masking -- bash -c '
  val=$(sops decrypt --extract "[\"the-key\"]" hosts/<host>/secrets/secrets.yaml)
  op item create --vault nas-overlay --category "Secure Note" --title "<host> <app>" \
    --tags "nix-personal,<host>,sops-escrow" "the_field[password]=$val"
'
```

**Escrow and verify BEFORE anything irreversible.** A one-way hash written to
sops with the plaintext deleted and never escrowed is unrecoverable — and for a
break-glass credential you find out at the worst possible moment.

---

## Verification after any change

```sh
git diff --numstat hosts/<host>/secrets/<file>.yaml     # expect ~3 lines: your key + mac + lastmodified
grep -cE '^[a-zA-Z0-9_.-]+:' hosts/<host>/secrets/<file>.yaml   # key count unchanged (unless adding)
nix eval '.#nixosConfigurations.<host>.config.sops.secrets' --apply 'builtins.attrNames'
```

Then deploy the host — `sops-install-secrets` runs at activation, and a secret
that fails to decrypt fails the activation loudly.

---

## Why this skill exists — two incidents, same root cause

**2026-08-23** — populating NetBox secrets on nas-sdg: ran `sops -d` on the whole
`secrets.yaml` *just to see key names*, was blocked by the permission classifier,
then hit a second failure — no age identity, because the 1Password **SSH** agent
is not an age key. Fixed by the `sops-authoring-key` item above.

**2026-08-30** — adding one htpasswd line for a new laptop: again decrypted the
whole file to find a field name, then piped the plaintext through a `grep -v`
that only excluded block scalars. Nine unrelated live secrets (a WireGuard
private key, an SSH private key, a ZFS dataset key, tokens, password hashes) were
printed into the session transcript. The field name was available the whole time
via `grep` on the encrypted file (Rule 1).

Both were preventable by Rule 1 alone. The skill existed for the second one and
did not load, because it lived in a single repo's `.claude/skills/` and the
session was rooted elsewhere — which is why it now ships via home-manager to
every machine.

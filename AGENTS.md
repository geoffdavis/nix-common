# Agent guide

Shared nix modules and pinned flake inputs for personal multi-host configs
(macOS / NixOS / standalone-home-manager Linux). Consumed as a flake input by
[nix-personal](https://github.com/geoffdavis/nix-personal) and by several
private downstream consumer repos.

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

## Updating pinned inputs

Two things go stale here: the nvfetcher-pinned upstream sources in
`_sources/generated.{nix,json}` (declared in `nvfetcher.toml`) and the flake
inputs in `flake.lock`. Each has a weekly auto-PR (`update-sources` Tue,
`update-flake-lock` Mon); the tasks below are the manual escape hatch, and the
`:commit` variants refuse to run on `main` or a detached HEAD.

```sh
task update:sources         # nvfetcher: refresh every pinned upstream source
task update:sources:commit  #   ^ + commit (body lists each package's old → new)
task update:flake           # nix flake update
task update:flake:commit    #   ^ + commit
task update:branch          # fresh chore/update-<ts> branch: sources + flake, each committed
```

`update:branch` is the one-shot: from a clean tree it cuts a topic branch,
commits the source bumps (with a per-package version rollup in the commit
body), then commits the flake-input update — ready to push + open a PR.

## Conventions

- alejandra format, deadnix-clean, statix-clean
- Conventional commits (`type(scope): subject`), single concern per commit
- `inherit (x) y;` over `y = x.y;`
- Never hardcode secrets. Public SSH keys are fine; everything else goes
  through `homeModules.op-json-secrets` or `homeModules.ssh`
  (`onepassword-ssh.keys`).
- This repo stays context-neutral. `nix-personal` is the **only** consumer
  repo that may be named here. Every other consumer (and its
  employer/host/internal-tool identifiers, e.g. work laptop hostnames or
  company/team acronyms) is a secret — never name it in code, comments, docs,
  or commit messages. Refer to them generically ("a downstream consumer", "a
  work host", "the standalone-home-manager Linux hosts").
- New shared modules go under `modules/home/` (cross-platform unless noted)
  or `modules/{darwin,nixos}/` for OS-specific. Add the export to
  `flake.nix`. Internal helpers that aren't flake outputs go under
  `modules/shared/`. See [docs/module-contract.md](docs/module-contract.md).
- One `enable` option per module, all config behind `lib.mkIf cfg.enable`,
  `lib.mkDefault` on anything a host might override.

## Renames and removals: sweep the prose, not just the code

Renaming or deleting anything with a name — a kernel module, an option, a
file, a config key — is not done when the code builds. Every place that
*mentions* the old name is now wrong, and nothing will fail to tell you.

Sweep all four, every time:

1. **Implementation** — the code that sets or uses it.
2. **Option descriptions** — `mkEnableOption` / `mkOption` text. This is what
   someone reads when deciding whether to switch the option on, so a stale
   description misleads harder than a stale comment.
3. **Comments** — including ones inside `'' … ''` strings. Those are
   derivation text, so editing them changes the closure; they belong in a
   separate commit from a comments-only change.
4. **Docs, especially runbooks.** A verification step that greps for the old
   name reports failure when things are actually working.

One command, from the repo root:

```sh
git grep -in '<old-name>'
```

No pathspec on purpose. Restricting it to `*.nix '*.md' '*.yml'` looks
thorough and silently skips `.sh`, `.py`, `.yaml`, `.json`, `.toml` and
templates — all of which carry names too. Searching every tracked file is
both shorter and correct; narrow it only when the noise is unmanageable, and
then say so.

The trap is checking only the file you are editing, believing that was a
sweep, and shipping prose that contradicts the code. It has bitten twice:
a LUKS recovery runbook still telling the operator to `lsmod | grep
<removed-module>` at the step where they decide whether to go find a USB
keyboard, and an option description still advertising a setting the program
had dropped. Both were caught in review, not by the build — neither breaks
anything, which is exactly why they survive.

**Verify a comments-only sweep; do not eyeball it.** "The diff contains
nothing but `#` lines" is not evidence. A comment inside a `'' … ''` body is
script text that lands in the store, so editing it changes the closure while
looking exactly like a comment change. Compare parse trees instead:

```sh
for f in $(git diff HEAD --name-only -- '*.nix'); do
  d=$(dirname "$f"); b=$(basename "$f")
  git show "HEAD:$f" > "$d/.orig-$b"
  a=$( (cd "$d" && nix-instantiate --parse ".orig-$b" | shasum) )
  c=$( (cd "$d" && nix-instantiate --parse "$b"        | shasum) )
  rm -f "$d/.orig-$b"
  [ "$a" = "$c" ] && echo "same $f" || echo "DIFFERS $f"
done
```

`git diff HEAD`, not `git diff`. The bare form compares the working tree to
the *index*, so once you have staged the edit — the normal state just before
committing — the loop runs zero times and reports success having checked
nothing.

Parse in the file's own directory — Nix resolves relative path literals at
parse time, so a copy elsewhere reports spurious differences.

AST-identical means comments-only, and the commit can say so. AST-different
while the diff shows only `#` lines means you edited a string: split that
into its own commit and state the closure impact, rather than claiming the
whole change is inert.

Dated records under `docs/superpowers/{plans,specs}/` are the deliberate
exception: they describe what was true when written, and rewriting them makes
them lie about their own moment.

## Workflow

- `main` is PR-protected. Don't push directly. CI (`lint / lint`,
  `flake-check`) must pass before merge.
- Bumping in downstream repos: `nix flake update nix-common` then a PR in
  that repo. The cost of separating contexts is one bump per consumer.

## Avoid

- Adding lambda args (`pkgs,`, `lib,`) that the module body doesn't
  reference — deadnix flags them.
- Bypassing pre-commit with `--no-verify`.
- Naming any consumer repo other than `nix-personal`, or leaking a consumer's
  employer/host/internal identifiers (see the context-neutrality convention
  above).
- Anything that requires platform-specific paths (`/Applications/...`,
  `/opt/...`) without a darwin/linux fork or `lib.mkDefault` so consumers
  can override.

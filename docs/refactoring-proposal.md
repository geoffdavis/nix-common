# Refactoring & guardrails proposal

Survey of the nix-common ecosystem (`nix-common` + consumers `nix-personal`,
`nix-oceaneering`, `nix-viasat`, and the private `nix-apple-firmware`) with an
eye toward **guardrails for automated/agent-authored changes**. Items are
ordered by value-to-risk. Each says whether it's *shipped in this branch* or
*proposed*.

## Shipped in this branch

### 1. Flake templates (`templates/`)

- `nix flake new -t github:geoffdavis/nix-common#consumer ./x` — a whole new
  consumer repo (flake, Taskfile with the pin-sync guardrails, CI, pre-commit,
  AGENTS.md + CLAUDE.md, statix.toml, .gitignore).
- `nix flake init -t github:geoffdavis/nix-common#home-module` /
  `task new:module -- <name>` — a shared-module skeleton that already
  satisfies the contract.

Why it's a guardrail: "add a host" and "add a module" are the two most common
operations, and the two most common places an agent improvises something
slightly wrong. A blessed starting point makes the happy path the default.

### 2. Module contract check (`scripts/check-module-contract.sh`)

Asserts the two-way invariant between `modules/` and `flake.nix` exports.
Pure bash (no nix), wired as `task contract`, a pre-commit hook, and a CI job.
Catches the single most common mechanical mistake: adding a module file and
forgetting to export it (or leaving a dangling export). Documented in
[`module-contract.md`](module-contract.md).

### 3. CLAUDE.md pointers

Every repo gets a `CLAUDE.md` that `@`-imports `AGENTS.md` so any coding agent
picks up conventions regardless of which tool runs it.

## Proposed (not yet implemented — needs your call)

### 4. De-duplicate the consumer Taskfile pin-sync logic — *medium value, medium risk*

`ci:sync-pin`, `bump:common`, `bump:common:commit`, and
`_guard:committable-branch` are ~60 near-identical lines copied across all
three consumer Taskfiles. When the logic needs a fix, it's a four-repo change.

Options:
- **A. Flake app.** Move the sync-pin shell into `nix-common` exposed as
  `apps.<system>.sync-pin`; consumers call
  `nix run github:geoffdavis/nix-common#sync-pin -- .github/workflows/ci.yml`.
  Single source of truth; tradeoff is a (cached) fetch and "latest unless
  pinned" semantics.
- **B. Template-only convergence (low risk).** Keep the duplication but treat
  `templates/consumer/Taskfile.yml` as the canonical copy; a `task contract`-
  style check could diff each consumer's pin-sync block against the template
  and warn on drift.

Recommendation: B now (zero behavioural risk, makes drift visible), A later if
the duplication actually causes a missed fix.

### 5. Reusable Claude workflows — *medium value, low risk*

`claude.yml` and `claude-code-review.yml` are byte-identical across repos,
including the pinned `claude-code-action` SHA. Bumping that SHA today is a
five-repo edit. Extract the body into reusable workflows in nix-common
(`claude-review.yml`, `claude.yml`) and leave a thin `uses:` wrapper in each
repo. (The trigger event handlers must stay per-repo, but the steps don't.)

### 6. Leave `verify-pin` inline — *decision, not a change*

It's tempting to make `verify-pin` a reusable workflow too, but it is
deliberately nix-free and self-contained (jq is preinstalled) so it stays fast
and can't itself drift. Making it reusable would add a meta-pin to keep in
sync — recursion we don't want. Recommend leaving it inline; the consumer
template already carries the canonical copy.

### 7. Converge oceaneering's teams-for-linux module — *low priority*

`nix-oceaneering/modules/teams-for-linux.nix` (+ `teams-mute-plugin.py`)
overlaps `nix-common`'s `homeModules.teams-for-linux`. If the differences are
just MQTT/EPM specifics, they could become module options so the shared module
is the single implementation. Needs a side-by-side diff before committing.

### 8. Secret scanning vs. existing GitGuardian — *informational*

GitGuardian already scans these repos **server-side, after push**. A local
`gitleaks` *pre-commit* hook would add one thing GitGuardian structurally
can't: stopping a secret **before it ever reaches the GitHub remote** (and
working offline / in agent sandboxes with no GitGuardian integration). A
`gitleaks` *CI* step, by contrast, is largely redundant with GitGuardian's PR
checks. So: a pre-commit hook is worth ~the 3 lines of config for
defense-in-depth on agent commits; a CI gitleaks job is not. Left out of this
branch per your call.

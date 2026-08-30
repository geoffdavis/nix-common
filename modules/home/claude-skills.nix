# modules/home/claude-skills.nix — Claude Code skills, shipped declaratively.
#
# WHY THIS EXISTS. Claude Code loads skills from two places: a repo's own
# `.claude/skills/` (only when the session is rooted in that repo) and the
# user's `~/.claude/skills/` (every session, any cwd). `~/.claude` is not a git
# repo, not synced, and was managed by nothing — so a hand-placed user skill
# exists on exactly one machine and silently does not exist anywhere else.
#
# That gap has a cost on record. nix-personal carried a repo-local
# `edit-sops-secrets` skill whose text forbids, verbatim, the mistake that on
# 2026-08-30 printed nine unrelated live secrets into a session transcript. It
# could not help: the session was rooted in a DIFFERENT repo, so the skill never
# loaded. The guidance was right and unreachable.
#
# A guardrail that depends on which directory someone happened to start in is
# not a guardrail. Shipping skills through home-manager makes them
# version-controlled, reviewable, and present on every machine after a switch —
# the same argument modules/builder-client-keys.nix makes in nix-personal about
# hand-maintained per-host copies.
#
# TRADE-OFF, deliberate: `home.file` installs a read-only /nix/store symlink, so
# a skill cannot be tweaked in place on a machine. Edits go through this repo
# and a switch. That is the point — an editable, un-versioned copy is precisely
# what failed — but it does make iterating on skill text slower, so draft new
# skills in a scratch file and move them here once settled.
#
# Imported by modules/home/ai-tools.nix, so any host that installs claude-code
# also gets the skills that make it safe to use. Consumers needing skills
# WITHOUT the AI packages can import this module directly
# (nix-common.homeModules.claude-skills).
{
  config,
  lib,
  ...
}: let
  cfg = config.claudeSkills;

  # Skills shipped by this repo. One directory per skill, each holding a
  # SKILL.md whose YAML frontmatter carries the `name` + `description` Claude
  # Code matches on — keep the directory name and the frontmatter `name` equal.
  builtinSkills = {
    # Safe handling of the fleet's sops-encrypted secrets. Encodes the two
    # rules whose absence caused the 2026-08-23 and 2026-08-30 incidents:
    # key names are plaintext (never decrypt to discover one), and never
    # filter the output of a whole-file decrypt.
    sops-secrets = ./claude-skills/sops-secrets/SKILL.md;
  };

  allSkills = builtinSkills // cfg.extraSkills;
in {
  options.claudeSkills = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install this repo's Claude Code skills into ~/.claude/skills. Default
        true: these are safety guidance, and the failure mode of not having
        them is silent. Set false on a host that should carry none.
      '';
    };

    extraSkills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      example = lib.literalExpression ''{ my-skill = ./my-skill/SKILL.md; }'';
      description = ''
        Additional skills to install, as a map of skill name to its SKILL.md
        path. Merged over the built-in set, so an entry here with a built-in's
        name replaces it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file =
      lib.mapAttrs'
      (name: src: lib.nameValuePair ".claude/skills/${name}/SKILL.md" {source = src;})
      allSkills;
  };
}

# modules/home/claude-skills.nix — Claude Code skills, shipped declaratively.
#
# MECHANISM ONLY. This module installs skill files; it ships none of its own.
# Skill text is inherently context-specific — it names hosts, vaults, secret
# stores and internal tooling — so it belongs in the consumer repo that owns
# that context, not in this context-neutral one (AGENTS.md: "This repo stays
# context-neutral"). Consumers supply their skills via `claudeSkills.skills`.
# Same split as any other topology-vs-mechanism boundary here.
#
# WHY THIS EXISTS. Claude Code loads skills from two places: a repo's own
# `.claude/skills/` (only when the session is rooted in that repo) and the
# user's `~/.claude/skills/` (every session, any cwd). `~/.claude` is not a
# git repo, is not synced, and is managed by nothing — so a hand-placed user
# skill exists on exactly one machine and silently does not exist anywhere
# else.
#
# That gap has a cost on record. A consumer repo carried a repo-local skill
# whose text forbids, verbatim, a mistake that later leaked live secret
# values into a session transcript. It could not help: the session was rooted
# in a DIFFERENT repo, so the skill never loaded. The guidance was correct and
# unreachable. A guardrail that depends on which directory someone happened to
# start in is not a guardrail.
#
# TRADE-OFF, deliberate: `home.file` installs a read-only /nix/store symlink,
# so a skill cannot be tweaked in place on a machine. Edits go through the
# owning repo and a switch. That is the point — an editable, un-versioned copy
# is precisely what failed — but it does make iterating on skill text slower,
# so draft new skills in a scratch file and move them into the repo once
# settled.
#
# Imported by modules/home/ai-tools.nix, so any host that installs claude-code
# also gets whatever skills its consumer repo defines. Consumers wanting the
# skills without the AI packages can import this module directly
# (homeModules.claude-skills).
{
  config,
  lib,
  ...
}: let
  cfg = config.claudeSkills;
in {
  options.claudeSkills = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install the skills listed in `claudeSkills.skills` into
        ~/.claude/skills. Default true: skills are typically safety guidance,
        and the failure mode of not having them is silent. With no skills
        defined this option does nothing, so the default costs a consumer
        that defines none exactly nothing.
      '';
    };

    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      example = lib.literalExpression ''{ my-skill = ./skills/my-skill/SKILL.md; }'';
      description = ''
        Skills to install, as a map of skill name to its SKILL.md path. Each
        becomes ~/.claude/skills/<name>/SKILL.md.

        Keep the attribute name equal to the `name` in the file's YAML
        frontmatter — Claude Code matches on the frontmatter, while the
        directory name is what a human sees.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && cfg.skills != {}) {
    home.file =
      lib.mapAttrs'
      (name: src: lib.nameValuePair ".claude/skills/${name}/SKILL.md" {source = src;})
      cfg.skills;
  };
}

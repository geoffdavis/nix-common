# modules/home/ai-tools.nix — version-pinned AI CLI tools for all hosts.
#
# Provides github-copilot-cli and claude-code, pinned past whatever nixpkgs
# ships, and configured to authenticate via the GitHub Copilot subscription
# (apiKeyHelper = "gh auth token").
#
# Keep versions current by running:
#   task update:ai-tools          (from nix-common checkout)
# or via the weekly update-ai-tools GitHub Actions workflow.
#
# After nix-common is updated, bump each consumer with:
#   task bump:common              (from the consumer repo)
{pkgs, ...}: let
  # ── version pins ─────────────────────────────────────────────────────────
  # Updated by scripts/update-ai-tools.sh via marker comments.
  copilotVersion = "1.0.59"; # update-ai-tools: copilot-version
  copilotHashLinuxX64 = "sha256-dmPk5+sWQVyfrplEudBlZhYKA0j8nzS2rkVUh9FVfZk="; # update-ai-tools: copilot-hash-linux-x64
  copilotHashDarwinArm64 = "sha256-OQTegFmTuTbyXTpiGeJFRsMY5DEz6aPLgBpD+jueV0E="; # update-ai-tools: copilot-hash-darwin-arm64

  claudeVersion = "2.1.161"; # update-ai-tools: claude-version
  claudeHashLinuxX64 = "sha256-H2oi84ejvOSWtthpOJo13/taacl9mDGDPzvW3A5sbCg="; # update-ai-tools: claude-hash-linux-x64
  claudeHashDarwinArm64 = "sha256-W03HnqsF+XVsJSxx3rM576RCnf/Bln3YOSz4f83khn8="; # update-ai-tools: claude-hash-darwin-arm64

  # ── platform selection ────────────────────────────────────────────────────
  sys = pkgs.stdenv.hostPlatform.system;

  copilotPlatform =
    {
      "x86_64-linux" = "linux-x64";
      "aarch64-darwin" = "darwin-arm64";
    }
    .${
      sys
    }
    or (throw "github-copilot-cli: unsupported system ${sys}");

  copilotHash =
    {
      "x86_64-linux" = copilotHashLinuxX64;
      "aarch64-darwin" = copilotHashDarwinArm64;
    }
    .${
      sys
    }
    or (throw "github-copilot-cli: unsupported system ${sys}");

  claudePlatform =
    {
      "x86_64-linux" = "linux-x64";
      "aarch64-darwin" = "darwin-arm64";
    }
    .${
      sys
    }
    or (throw "claude-code: unsupported system ${sys}");

  claudeHash =
    {
      "x86_64-linux" = claudeHashLinuxX64;
      "aarch64-darwin" = claudeHashDarwinArm64;
    }
    .${
      sys
    }
    or (throw "claude-code: unsupported system ${sys}");

  # ── package overrides ─────────────────────────────────────────────────────
  github-copilot-cli = pkgs.github-copilot-cli.overrideAttrs (_: {
    version = copilotVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/github/copilot-cli/releases/download/v${copilotVersion}/github-copilot-${copilotVersion}-${copilotPlatform}.tgz";
      hash = copilotHash;
    };
  });

  claude-code = pkgs.claude-code.overrideAttrs (_: {
    version = claudeVersion;
    src = pkgs.fetchurl {
      url = "https://downloads.claude.ai/claude-code-releases/${claudeVersion}/${claudePlatform}/claude";
      hash = claudeHash;
    };
  });
in {
  home.packages = [
    github-copilot-cli
    claude-code
  ];
}

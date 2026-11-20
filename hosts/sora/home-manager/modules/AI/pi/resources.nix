{pkgs}: let
  inherit (pkgs) lib;
  inherit (builtins) readFile;
  shared = ../shared;
  template = import ../shared/render.nix;
  text = path: readFile (shared + "/${path}");
  local = path: readFile (./. + "/${path}");
  agent = path: name: vars:
    pkgs.writeText "${name}-agent.md" (template {
      body = template vars (text "agents/${name}.md");
    } (local "agents/${path}.md"));
  workflow = name: argument:
    pkgs.writeText "${name}.md" (
      local "prompts/${name}.md" + template {inherit argument;} (text "workflows/${name}.md")
    );
  skillDirs = dir:
    lib.mapAttrsToList (name: _: {
      inherit name;
      path = dir + "/${name}";
    }) (
      lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir)
    );
  skills = pkgs.linkFarm "pi-skills" (
    skillDirs ./skills
    ++ lib.filter (entry: !(builtins.elem entry.name ["politics" "screenshot"])) (skillDirs ../shared/skills)
    ++ [
      {
        name = "politics/SKILL.md";
        path = pkgs.writeText "politics-skill.md" (template {toolWorkflow = readFile ./skills/politics-tool-workflow.md;} (readFile ../shared/skills/politics/SKILL.md));
      }
      {
        name = "screenshot/SKILL.md";
        path = pkgs.writeText "screenshot-skill.md" (template {
          browserTable = "Use `browser` skill";
          browserInstructions = "load the `browser`\nskill and use `agent_browser`";
          delegate = "subagent";
          scratch = "/tmp/pi/";
        } (readFile ../shared/skills/screenshot/SKILL.md));
      }
      {
        name = "politics/references";
        path = ../shared/skills/politics/references;
      }
    ]
  );
in {
  context = pkgs.writeText "context.md" (text "context.md" + readFile ./context.md + text "operator.md");
  inherit skills;
  agents = pkgs.linkFarm "pi-custom-agents" [
    {
      name = "nix-auditor.md";
      path = agent "nix-auditor" "nix-auditor" {shell = "bash";};
    }
    {
      name = "prisma.md";
      path = agent "prisma" "prisma" {browser = readFile ./agents/prisma-browser.md;};
    }
    {
      name = "image-analyzer/image-analyzer.md";
      path = agent "image-analyzer/image-analyzer" "image-analyzer" {reader = "Read tool";};
    }
    {
      name = "audio-analyzer/audio-analyzer.md";
      path = agent "audio-analyzer/audio-analyzer" "audio-analyzer" {temp = "Use `/tmp/pi/` for temporary converted audio.";};
    }
    {
      name = "pdf-reader/pdf-reader.md";
      path = ./agents/pdf-reader/pdf-reader.md;
    }
  ];
  prompts = pkgs.linkFarm "pi-prompts" [
    {
      name = "commit.md";
      path = ../shared/workflows/commit.md;
    }
    {
      name = "nix-audit.md";
      path = ../shared/workflows/nix-audit.md;
    }
    {
      name = "nix-rebuild.md";
      path = workflow "nix-rebuild" "";
    }
    {
      name = "ponder.md";
      path = workflow "ponder" "\${ARGUMENTS:-whole session}";
    }
    {
      name = "archive.md";
      path = workflow "archive" "\${1:-Session_Summary}";
    }
  ];
}

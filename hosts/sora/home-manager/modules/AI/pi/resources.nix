{
  pkgs,
  reaSkill ? null,
}: let
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
  renderedSharedSkill = name: vars: {
    name = "${name}/SKILL.md";
    path = pkgs.writeText "pi-${name}-skill.md" (template vars (text "skills/${name}/SKILL.md"));
  };
  skillDirs = dir:
    lib.mapAttrsToList (name: _: {
      inherit name;
      path = dir + "/${name}";
    }) (
      lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir)
    );
  # Templated shared skills rendered below, plus council-mode which pi-subagents already bundles for Pi.
  excludedRawSharedSkills = [
    "politics"
    "screenshot"
    "browser"
    "web-research"
    "intercom"
    "orchestration"
    "council-mode"
    "review-loop"
    "structured-clarification"
    "reverse-engineer-anything"
  ];
  skills = pkgs.linkFarm "pi-skills" (
    skillDirs ./skills
    ++ lib.filter (entry: !(builtins.elem entry.name excludedRawSharedSkills)) (skillDirs ../shared/skills)
    ++ [
      (renderedSharedSkill "politics" {toolWorkflow = readFile ./skills/politics-tool-workflow.md;})
      {
        name = "politics/references";
        path = ../shared/skills/politics/references;
      }
      (renderedSharedSkill "screenshot" {
        browserTable = "Use `browser` skill";
        browserInstructions = "load the `browser`\nskill and use `agent_browser`";
        delegate = "subagent";
        scratch = "/tmp/pi/";
      })
      (renderedSharedSkill "browser" {
        browserAdapter = ''
          Use the native `agent_browser` tool (`pi-agent-browser-native`). Do not maintain a second Playwright helper.

          - Use Pi `codemode` to orchestrate `tools.agent_browser` calls with branching or aggregation.
          - Discover advanced tools via native `tool_search` (`agent_browser_qa`, `agent_browser_action`, `agent_browser_electron`, `agent_browser_source`, `agent_browser_network_source`).
          - Use native `batch` for fixed multi-step jobs and `sessionMode = "fresh"` for launch-scoped flags.
          - Batch reads and same-page actions when safe; split before navigation or form submission because refs go stale.
        '';
      })
      (renderedSharedSkill "web-research" {
        webTools = ''
          Use Pi's `pi-web-access` tools: `web_search`, `fetch_content`, `get_search_content`, and `source_check` (enable with `web_enable` if deferred).
        '';
      })
      (renderedSharedSkill "intercom" {
        intercomAdapter = ''
          Use the native `intercom` tool (`action: "list" | "send" | "ask" | "reply" | "pending"`). Use `reply` when answering an inbound `ask`. For scripted/external calls, `pi-intercom list|send|ask` is also available on `PATH`.
        '';
      })
      (renderedSharedSkill "orchestration" {
        dispatchAdapter = ''
          In Pi, delegate through `pi-subagents`: enable with `subagents_enable` if needed, dispatch with `subagent`, and block with `bg_wait` only when results are needed before continuing.
        '';
      })
      (renderedSharedSkill "review-loop" {
        reviewDispatch = ''
          Use Pi's `subagent` tool (`worker` for implementation passes, parallel fresh-context `reviewer` agents for each round, or a `workflow` script with `async: true`).
        '';
      })
      (renderedSharedSkill "structured-clarification" {
        clarificationAdapter = ''
          Use Pi's native `ask_user_question` tool (`@juicesharp/rpiv-ask-user-question`) when asking typed multi-choice questions.
        '';
      })
    ]
    ++ lib.optionals (reaSkill != null) [
      (renderedSharedSkill "reverse-engineer-anything" {
        reaAdapter = ''
          In Pi, discover REA's 263 `mcp__rea` tools lazily through Pi `codemode` (backed by Nix-managed `.pi/agent/mcp.json` with `REA_MCP_OUTPUT_SCHEMA_PROFILE=off`), or invoke the `rea` CLI directly via `bash`.
        '';
      })
      {
        name = "reverse-engineer-anything/references";
        path = "${reaSkill}/references";
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

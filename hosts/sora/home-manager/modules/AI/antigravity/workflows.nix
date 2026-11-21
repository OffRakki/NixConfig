{
  lib,
  pkgs,
  reaSkill,
  piIntercomInboxHook,
}: let
  render = import ../shared/render.nix;
  shared = path: builtins.readFile (../shared + "/${path}");
  markdownBody = text:
    lib.concatStringsSep "\n---\n" (lib.drop 1 (lib.splitString "\n---\n" text));
  skill = name: description: body: {
    name = "skills/${name}/SKILL.md";
    path = pkgs.writeText "${name}-skill.md" ''
      ---
      name: ${name}
      description: ${builtins.toJSON description}
      ---

      ${body}
    '';
  };
  renderedSharedSkill = name: vars: {
    name = "skills/${name}/SKILL.md";
    path = pkgs.writeText "agy-${name}-skill.md" (render vars (shared "skills/${name}/SKILL.md"));
  };
  agent = name: description: tools: body: {
    name = "agents/${name}.md";
    path = pkgs.writeText "${name}-agent.md" ''
      ---
      name: ${name}
      description: ${builtins.toJSON description}
      tools: ${builtins.toJSON tools}
      subagent: true
      mainAgent: false
      commandExecutionPolicy: off
      ---

      ${body}
    '';
  };
  sharedSkills = {
    ciel-brain = ../pi/skills/ciel-brain;
    context-compression = ../shared/skills/context-compression;
    context-curation = ../pi/skills/context-curation;
    i-have-adhd = ../pi/skills/i-have-adhd;
    jujutsu = ../shared/skills/jujutsu;
    linux = ../shared/skills/linux;
    modeling = ../shared/skills/modeling;
    nix = ../pi/skills/nix;
    nix-refactor = ../shared/skills/nix-refactor;
    ollama = ../shared/skills/ollama;
    quickshell = ../shared/skills/quickshell;
    real-product-showcase = ../shared/skills/real-product-showcase;
    rust = ../shared/skills/rust;
    security-sweep = ../pi/skills/security-sweep;
    seo = ../shared/skills/seo;
  };
  manifest = pkgs.writeText "plugin.json" (builtins.toJSON {
    name = "personal-workflows";
    version = "1.0.0";
    description = "Nix-managed skills, workflows, and specialist agents.";
  });
  hooks = pkgs.writeText "hooks.json" (builtins.toJSON {
    pi-intercom-inbox = {
      PreInvocation = [
        {
          type = "command";
          command = "${piIntercomInboxHook}/bin/pi-intercom-inbox-hook";
          timeout = 5;
        }
      ];
    };
  });
in
  pkgs.linkFarm "antigravity-personal-workflows" ([
      {
        name = "plugin.json";
        path = manifest;
      }
      {
        name = "hooks.json";
        path = hooks;
      }
      (renderedSharedSkill "politics" {toolWorkflow = builtins.readFile ./politics-tool-workflow.md;})
      {
        name = "skills/politics/references";
        path = ../shared/skills/politics/references;
      }
      (renderedSharedSkill "browser" {
        browserAdapter = ''
          Use Antigravity's native browser agent (Lucky can invoke it with `/browser`) as the primary browser path. On CLI, Chrome must already be running with remote debugging enabled; ask Lucky to approve the connection prompt.

          When native browser control is unavailable or an isolated headless CLI run is cleaner, use `agent-browser` from `run_command` with an explicit session and Chromium path:
          - `agent-browser --session agy-<task> --executable-path "$(command -v chromium)" open <url>`
          - `agent-browser --session agy-<task> snapshot -i`
          - Close only sessions created for the task once finished.
        '';
      })
      (renderedSharedSkill "web-research" {
        webTools = ''
          Use Antigravity's native `search_web` for fast search, and the configured `pi-web-access` MCP tools (`web_search`, `fetch_content`, `get_search_content`, `source_check`) for zero-config Exa search, local GitHub repo/PR/issue extraction, PDF extraction, and source verification.
        '';
      })
      (renderedSharedSkill "intercom" {
        intercomAdapter = ''
          Use the `pi-intercom` MCP server's `intercom` tool (auto-registers this Antigravity session in the shared local broker and spawns the broker automatically if needed):
          - `action: "list"` — inspect all connected Pi and Antigravity sessions.
          - `action: "rename", name: "<alias>"` — set a human-friendly session alias (default is `agy-<folder>-<4char>`).
          - `action: "send", to: "<target>", message: "<text>"` — fire-and-forget handoff.
          - `action: "ask", to: "<target>", message: "<question>", timeoutMs: 60000` — synchronous request waiting for a reply.
          - `action: "inbox"` — read unread inbound messages and pending asks sent to this session.
          - `action: "reply", message: "<answer>"` — reply to a pending ask (optional `to` or `replyTo`).

          A `PreInvocation` hook also surfaces unread inbound messages automatically during active turns. The `pi-intercom` CLI (`pi-intercom list|send|ask`) remains available on `PATH` as a fallback.
        '';
      })
      (renderedSharedSkill "orchestration" {
        dispatchAdapter = ''
          In Antigravity, use native orchestration primitives:
          - `invoke_subagent` (with `define_subagent` for custom roles) for focused delegated work.
          - `swarm` for coordinated multi-worker tasks sharing a board (`workspace: "share"` or `"branch"` when parallel writers need isolation).
          - `run_workflow` for Python-scripted fanout/pipeline orchestration across many independent targets.
          - `schedule` for timers and recurring jobs.
        '';
      })
      (renderedSharedSkill "council-mode" {
        councilDispatch = ''
          In Antigravity, launch Pass 1 advisors in parallel via `invoke_subagent` (using read-only roles such as `research` or custom `define_subagent` advisors with `EnableWriteTools: false`) or `run_workflow`. Pass 2 resumes the same subagent conversation IDs via `send_message` with each advisor's curated challenge packet.
        '';
      })
      {
        name = "skills/council-mode/references";
        path = ../shared/skills/council-mode/references;
      }
      (renderedSharedSkill "review-loop" {
        reviewDispatch = ''
          In Antigravity, launch fresh-context read-only reviewers in parallel via `invoke_subagent` (`TypeName: "research"` or a custom read-only reviewer via `define_subagent`) and apply approved fixes directly or via one focused worker subagent per round.
        '';
      })
      (renderedSharedSkill "structured-clarification" {
        clarificationAdapter = ''
          Use Antigravity's native `ask_question` tool for structured multiple-choice decisions (or `/grill-me` for full interactive planning interviews).
        '';
      })
      (renderedSharedSkill "reverse-engineer-anything" {
        reaAdapter = ''
          In Antigravity, use the `rea` CLI directly via `run_command` (for example `rea analyze-javascript-application /abs/path --json` or `rea --help`). `rea mcp` is intentionally omitted from Antigravity's MCP config so its 263 tool schemas do not bloat every conversation prompt.
        '';
      })
      {
        name = "skills/reverse-engineer-anything/references";
        path = "${reaSkill}/references";
      }
      (skill "nix-auditor" "Audit NixOS and Home Manager configuration without edits." (builtins.replaceStrings ["`read`" "`bash`"] ["`view_file`" "`run_command`"] (markdownBody (builtins.readFile ../pi/skills/nix-auditor/SKILL.md))))
      (skill "screenshot" "Capture desktop or browser screenshots and optionally analyze them." (markdownBody (render {
        browserTable = "Use `browser` skill (native `/browser` or `agent-browser`)";
        browserInstructions = "load the `browser` skill and use native Antigravity browser controls or `agent-browser`";
        delegate = "invoke_subagent";
        scratch = "/tmp/";
      } (shared "skills/screenshot/SKILL.md"))))
      (skill "commit" "Review and describe the current Jujutsu change, then open a fresh working copy." (shared "workflows/commit.md"))
      (skill "nix-audit" "Delegate a read-only NixConfig audit to nix-auditor." (''
          Load the nix-auditor skill and invoke the nix-auditor subagent in the NixConfig workspace. Report findings inline with priorities and file references.
        ''
        + shared "workflows/nix-audit.md"))
      (skill "nix-rebuild" "Build NixOS first, then switch in an interactive terminal if authorized." (''
          Load the nix skill. Build the current host with `nixos-rebuild build --flake path:/home/rakki/Projects/NixConfig`. Do not move a bookmark just to build.

          Only after a successful build and explicit approval to switch, start kitty with `kitty --directory /home/rakki/Projects/NixConfig -e sh -c 'nh os switch path:/home/rakki/Projects/NixConfig || exec bash'`.
        ''
        + shared "workflows/nix-rebuild.md"))
      (skill "ponder" "Reflect on the session and identify durable decisions and lessons." (render {argument = "any focus supplied by Lucky, otherwise the whole session";} (shared "workflows/ponder.md") + "\nRequest access before writing outside the workspace; if unavailable, propose changes inline.\n"))
      (skill "archive" "Save a session summary to the Ciel vault when explicitly requested." (render {argument = "the requested title or Session_Summary";} (shared "workflows/archive.md") + "\nLoad ciel-brain. Request access before writing outside the workspace and return the draft inline if unavailable.\n"))
      (agent "nix-auditor" "Read-only NixOS and Home Manager audit." ["view_file" "grep_search" "run_command"] (render {shell = "run_command";} (shared "agents/nix-auditor.md")))
      (agent "prisma" "Read-only, evidence-first political research for Lucky." ["view_file" "search_web" "read_url_content"] (render {
        browser = "Use native Antigravity research tools. If exact source inspection is unavailable, ask the parent for the public primary-source material and report the gap.";
      } (shared "agents/prisma.md")))
      (agent "image-analyzer" "Describe image layout, visible text, and UI elements." ["view_file"] (render {reader = "view_file tool";} (shared "agents/image-analyzer.md")))
      (agent "audio-analyzer" "Inspect and transcribe English or Brazilian Portuguese audio." ["run_command"] (render {temp = "Use a fresh mktemp directory for temporary converted audio.";} (shared "agents/audio-analyzer.md")))
      (agent "pdf-reader" "Extract text and layout from a local PDF." ["view_file" "run_command" "invoke_subagent"] ''
        Use Poppler (`pdftotext -layout`, `pdftoppm`) via `nix shell nixpkgs#poppler-utils` if needed. Create a fresh temporary directory for text and page images; never modify the input. Read extracted text and use image-analyzer via invoke_subagent for pages where layout or OCR matters, if those tools are available. Return structured JSON for forms or faithful cleaned text for prose. Report unreadable sections and tool failures explicitly.
      '')
    ]
    ++ lib.mapAttrsToList (name: path: {
      name = "skills/${name}";
      inherit path;
    })
    sharedSkills)

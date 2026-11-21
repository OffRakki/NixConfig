{
  inputs,
  pkgs,
  ...
}: let
  render = import ../AI/shared/render.nix;
  sharedTools = import ../AI/shared/tools.nix {inherit pkgs inputs;};
  sharedSkill = path: builtins.readFile (../AI/shared/skills + "/${path}");
  renderedSkillDir = name: vars:
    pkgs.linkFarm "hax-skill-${name}" [
      {
        name = "SKILL.md";
        path = pkgs.writeText "hax-${name}-skill.md" (render vars (sharedSkill "${name}/SKILL.md"));
      }
    ];
  councilSkillDir = pkgs.linkFarm "hax-skill-council-mode" [
    {
      name = "SKILL.md";
      path = pkgs.writeText "hax-council-mode-skill.md" (render {
        councilDispatch = ''
          In HAX, run independent Pass 1 advisors as bounded subprocesses (`hax -p --json --bare` or explicit cwd/model flags) only when Lucky explicitly authorizes multi-agent delegation, passing the JSON contract and evidence inline. Never rely on unverified prose alone for read-only enforcement.
        '';
      } (sharedSkill "council-mode/SKILL.md"));
    }
    {
      name = "references";
      path = ../AI/shared/skills/council-mode/references;
    }
  ];
  reaSkillDir = pkgs.linkFarm "hax-skill-reverse-engineer-anything" [
    {
      name = "SKILL.md";
      path = pkgs.writeText "hax-rea-skill.md" (render {
        reaAdapter = ''
          In HAX, invoke the `rea` CLI directly from native `bash` (e.g., `rea --help`, `rea analyze-javascript-application /abs/path --json`). HAX has no MCP client wired.
        '';
      } (sharedSkill "reverse-engineer-anything/SKILL.md"));
    }
    {
      name = "references";
      path = "${sharedTools.reaSkill}/references";
    }
  ];
  settings = import ./settings.nix;
  configFile = pkgs.writeText "hax-config.json" (builtins.toJSON settings);
  contextFile = pkgs.writeText "hax-context.md" (
    builtins.readFile ../AI/shared/context.md
    + "\n"
    + builtins.readFile ./context.md
    + "\n"
    + builtins.readFile ../AI/shared/operator.md
  );
  skills = {
    hax-tools = ./skills/hax-tools;
    nix = ./skills/nix;
    jujutsu = ../AI/shared/skills/jujutsu;
    context-compression = ../AI/shared/skills/context-compression;
    ollama = ../AI/shared/skills/ollama;
    real-product-showcase = ../AI/shared/skills/real-product-showcase;
    reverse-engineer-anything = reaSkillDir;
    council-mode = councilSkillDir;
    browser = renderedSkillDir "browser" {
      browserAdapter = ''
        Use `agent-browser` from native bash, not Pi's `agent_browser` tool or a parallel Playwright implementation. Inspect `agent-browser --help` before unfamiliar operations.

        - Assign a unique explicit session name per task (e.g. `hax-<task>-<suffix>`) and pass `--session <name>` on every command.
        - Open with explicit Chromium: `agent-browser --session <name> --executable-path "$(command -v chromium)" open <url>`.
        - Snapshot with `agent-browser --session <name> snapshot -i`, re-snapshot after navigation/rerenders, and close only owned sessions when done.
        - Inspect saved screenshots through HAX's image-capable read flow with a vision-capable model rather than assuming a saved path succeeded.
      '';
    };
    web-research = renderedSkillDir "web-research" {
      webTools = ''
        HAX has no MCP client wired yet. Use `curl` for exact raw public HTTP/API/doc endpoints, `gh` for GitHub repositories/PRs/issues when authenticated, and report missing web-search/MCP tooling honestly rather than silently calling another harness.
      '';
    };
    intercom = renderedSkillDir "intercom" {
      intercomAdapter = ''
        Use the `pi-intercom` CLI from native bash:
        - `pi-intercom list --json` — inspect active sessions on the local broker.
        - `pi-intercom send --to <target> --text "<message>" --name hax` — fire-and-forget handoff.
        - `pi-intercom ask --to <target> --text "<question>" --timeout-ms 60000 --name hax --json` — wait for a reply.
      '';
    };
    orchestration = renderedSkillDir "orchestration" {
      dispatchAdapter = ''
        In HAX, only launch subprocess agents when explicitly authorized. Use native background tasks for cancellation/result delivery and explicit `hax -p --json` / `--resume=ID` (never "latest") with bounded context and explicit cwd/provider/model. Background tasks stop on conversation exit.
      '';
    };
    review-loop = renderedSkillDir "review-loop" {
      reviewDispatch = ''
        In HAX, run independent review passes via authorized subprocess `hax -p --json` runs (one angle per reviewer) or sequentially in fresh contexts, keeping the parent session as loop controller and applying approved fixes in a single writer pass.
      '';
    };
    structured-clarification = renderedSkillDir "structured-clarification" {
      clarificationAdapter = ''
        HAX has no interactive questionnaire dialog; present typed choices as a crisp numbered Markdown list with `(Recommended)` first and a short prompt inviting Lucky's selection (e.g. `1, 2, 1`).
      '';
    };
  };
  hax = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.hax;
  smokeCheck = pkgs.runCommand "hax-smoke-check" {} ''
    ${pkgs.python3}/bin/python3 ${./tests/smoke.py} \
      "${hax}/bin/hax" ${configFile} ${contextFile} \
      ${pkgs.linkFarm "hax-skills" (pkgs.lib.mapAttrsToList (name: path: {inherit name path;}) skills)}
    touch "$out"
  '';
in {
  home = {
    # Required at build time without retaining the check in the runtime closure.
    checks = [smokeCheck];
    packages = [hax pkgs.jujutsu pkgs.agent-browser pkgs.chromium];
    persistence."/persist".directories = [".local/state/hax"];
    file =
      {
        ".config/hax/config.json".source = configFile;
        ".config/hax/AGENTS.md".source = contextFile;
        ".config/hax/docs".source = "${hax.src}/docs";
      }
      // pkgs.lib.mapAttrs' (name: source:
        pkgs.lib.nameValuePair ".config/hax/skills/${name}" {inherit source;})
      skills;
  };
  xdg.desktopEntries.hax = {
    name = "HAX";
    genericName = "AI Coding Assistant";
    comment = "CLI-first coding assistant (side-by-side pilot)";
    exec = "kitty --directory /home/rakki/Projects/NixConfig -e hax";
    icon = "utilities-terminal";
    terminal = false;
    categories = ["Development" "ConsoleOnly"];
  };
}

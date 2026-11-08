{
  pkgs,
  lib,
  nixConfigRoot,
  ...
}: let
  llmSuggestLsp = pkgs.callPackage ./pi/llm-suggest-lsp.nix {};
  flake = ''(builtins.getFlake "path:${nixConfigRoot}")'';
  # Helix has no global-language-servers setting; attach Pi's quickfix server explicitly.
  language = name: servers: {
    inherit name;
    auto-format = true;
    language-servers = servers ++ ["llm-suggest"];
  };
  prettierFormatter = {
    command = lib.getExe pkgs.prettier;
    args = ["--stdin-filepath" "%{buffer_name}"];
  };
in {
  programs.helix = {
    enable = true;
    defaultEditor = true;
    extraPackages = with pkgs; [
      alejandra
      nixd
      marksman
      basedpyright
      ruff
      lua-language-server
      luau-lsp
      stylua
      typescript-language-server
      vscode-langservers-extracted
      prettier
      qt6.qtdeclarative
      rust-analyzer
      rustfmt
      cargo
      rustc
      clang-tools
      csharp-ls
      netcoredbg
      bash-language-server
      shellcheck
      shfmt
      fish-lsp
      yaml-language-server
      taplo
      lldb
    ];
    settings = {
      theme = "kaolin-valley-transparent";
      editor = {
        cursorline = true;
        soft-wrap.enable = true;
        color-modes = true;
        gutters = ["diagnostics" "line-numbers" "spacer" "diff"]; # Add/remove "line-numbers" to toggle
        line-number = "relative";
        bufferline = "multiple";
        indent-guides.render = true;
        completion-timeout = 150;
        completion-replace = true;
        popup-border = "all";
        file-picker.hidden = false;
        end-of-line-diagnostics = "hint";
        inline-diagnostics.cursor-line = "info";
        statusline.right = ["diagnostics" "workspace-diagnostics" "selections" "register" "position" "file-type"];
        lsp = {
          enable = true;
          display-messages = true;
          display-inlay-hints = true;
        };
        cursor-shape = {
          normal = "block";
          insert = "bar";
          select = "underline";
        };
      };
    };
    languages = {
      language =
        [
          ((language "nix" ["nixd" "colors"]) // {formatter.command = lib.getExe pkgs.alejandra;})
          ((language "markdown" ["marksman"]) // {auto-format = false;})
          ((language "python" [
              "basedpyright"
              {
                name = "ruff";
                only-features = ["diagnostics" "code-action" "format"];
              }
            ])
            // {
              formatter = {
                command = lib.getExe pkgs.ruff;
                args = ["format" "--stdin-filename" "%{buffer_name}" "-"];
              };
            })
          ((language "lua" ["lua-language-server"])
            // {
              formatter = {
                command = lib.getExe pkgs.stylua;
                args = ["--stdin-filepath" "%{buffer_name}" "-"];
              };
            })
          ((language "luau" ["luau"])
            // {
              formatter = {
                command = lib.getExe pkgs.stylua;
                args = ["--syntax" "Luau" "--stdin-filepath" "%{buffer_name}" "-"];
              };
            })
          (language "qml" ["qmlls"])
          (language "rust" ["rust-analyzer"])
          (language "c" ["clangd"])
          (language "cpp" ["clangd"])
          (language "c-sharp" ["csharp-ls"])
          ((language "bash" ["bash-language-server"])
            // {
              formatter = {
                command = lib.getExe pkgs.shfmt;
                args = ["-filename" "%{buffer_name}"];
              };
            })
          (language "fish" ["fish-lsp"])
          (language "yaml" ["yaml-language-server"])
          (language "toml" ["taplo"])
        ]
        ++ map (name: (language name ["typescript-language-server"]) // {formatter = prettierFormatter;}) [
          "javascript"
          "jsx"
          "typescript"
          "tsx"
        ]
        ++ map (name: (language name ["vscode-json-language-server"]) // {formatter = prettierFormatter;}) ["json" "jsonc"]
        ++ map (name: (language name ["vscode-css-language-server"]) // {formatter = prettierFormatter;}) ["css" "scss"]
        ++ [(language "html" ["vscode-html-language-server"])];
      language-server = {
        nixd.config.nixd = {
          nixpkgs.expr = "${flake}.nixosConfigurations.sora.pkgs";
          options = {
            nixos.expr = "${flake}.nixosConfigurations.sora.options";
            home-manager.expr = "${flake}.nixosConfigurations.sora.options.home-manager.users.type.getSubOptions []";
          };
        };
        basedpyright.config.basedpyright.analysis = {
          diagnosticMode = "openFilesOnly";
          typeCheckingMode = "standard";
        };
        qmlls.command = lib.getExe' pkgs.qt6.qtdeclarative "qmlls";
        clangd.args = ["--background-index" "--clang-tidy" "--completion-style=detailed"];
        colors.command = lib.getExe pkgs.uwu-colors;
        llm-suggest.command = lib.getExe llmSuggestLsp;
      };
    };
    themes = {
      kaolin-valley-transparent = {
        "inherits" = "kaolin-valley-dark";
        "ui.background" = {};
      };
    };
  };
}

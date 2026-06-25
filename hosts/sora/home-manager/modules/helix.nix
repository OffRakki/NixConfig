{
  pkgs,
  lib,
  ...
}: let
  llmSuggestLsp = pkgs.callPackage ./pi/llm-suggest-lsp.nix {};
in {
  programs.helix = {
    enable = true;
    defaultEditor = true;
    extraPackages = [
      pkgs.alejandra
      pkgs.nixfmt
      pkgs.marksman
    ];
    settings = {
      theme = "kaolin-valley-dark";
      editor = {
        cursorline = true;
        soft-wrap.enable = true;
        color-modes = true;
        gutters = ["diagnostics" "line-numbers" "spacer" "diff"]; # Add/remove "line-numbers" to toggle
        line-number = "relative";
        bufferline = "multiple";
        indent-guides.render = true;
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
      language = [
        {
          name = "nix";
          auto-format = true;
          formatter.command = "alejandra";
          language-servers = [
            "nixd"
            "nil"
            "colors"
            "llm-suggest"
          ];
        }
        {
          name = "markdown";
          language-servers = [
            "marksman"
            "llm-suggest"
          ];
        }
        {
          name = "json";
          language-servers = ["llm-suggest"];
        }
        {
          name = "css";
          language-servers = ["llm-suggest"];
        }
        {
          name = "qml";
          language-servers = ["llm-suggest"];
        }
        {
          name = "python";
          language-servers = ["llm-suggest"];
        }
        {
          name = "lua";
          language-servers = ["llm-suggest"];
        }
      ];
      global-language-servers = ["llm-suggest"];
      language-server = {
        nixd = {
          command = "nixd";
        };
        colors.command = lib.getExe pkgs.uwu-colors;
        llm-suggest.command = lib.getExe llmSuggestLsp;
      };
    };
    themes = {
      catppuccin_mocha = {
        "inherits" = "kaolin-valley-dark";
        "ui.background" = {};
      };
    };
  };
}

{config, ...}: {
  programs = {
    bat.enable = true;
    eza = {
      enable = true;
      enableZshIntegration = true;
      colors = "always";
      git = true;
      icons = "always";
      extraOptions = [
        "--group-directories-first"
        "--header"
      ];
    };
    git = {
      enable = true;
      settings = {
        core.editor = "hx";
        init.defaultBranch = "master";
        user.name = "Fernando Marques";
        user.email = "offrakki@gmail.com";
        commit.verbose = true;
        column.ui = "auto";
      };
    };
    jujutsu = {
      enable = true;
      settings = {
        snapshot.max-new-file-size = "50MiB";
        user = {
          name = config.programs.git.settings.user.name;
          email = config.programs.git.settings.user.email;
        };
        ui = {
          pager = "less -FRX";
          default-command = "log";
          graph.style = "curved";
        };
        templates.draft_commit_description = ''
          concat(
            description,
            "\n\n\n",
            indent("JJ: ", concat(
              "Change summary:\n",
              indent("     ", diff.summary()),
              "Full change:\n",
              "ignore-rest\n",
            )),
            diff.git(),
          )
        '';
      };
    };
  };
}

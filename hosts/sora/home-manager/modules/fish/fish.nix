{pkgs, ...}: {
  programs = {
    fish = {
      enable = true;
      plugins = [
        {
          name = "tide";
          src = pkgs.fetchFromGitHub {
            owner = "IlanCosman";
            repo = "tide";
            rev = "v6.2.0";
            hash = "sha256-1ApDjBUZ1o5UyfQijv9a3uQJ/ZuQFfpNmHiDWzoHyuw=";
          };
        }
      ];
      interactiveShellInit = ''
        # ── Tide prompt: rainbow style, 2-line, powerline ──────

        # Tide's fisher init never fires under Nix — fire it manually
        source (functions --details _tide_sub_configure)
        _load_config rainbow
        _tide_finish

        # Override with custom settings (set -U to beat tide configure universals)

        set -U tide_prompt_add_newline_before true
        set -U tide_prompt_color_frame_and_connection brblack
        set -U tide_prompt_color_separator_same_color brblack
        set -U tide_prompt_icon_connection " "
        set -U tide_prompt_min_cols 34
        set -U tide_prompt_transient_enabled true

        # Left prompt: pwd jj newline character
        set -U tide_left_prompt_frame_enabled false
        set -U tide_left_prompt_items "pwd jj newline character"
        set -U tide_left_prompt_prefix ""
        set -U tide_left_prompt_separator_diff_color " "
        set -U tide_left_prompt_separator_same_color " "
        set -U tide_left_prompt_suffix " "

        # Right prompt: status cmd_duration context jobs time nix_shell
        set -U tide_right_prompt_frame_enabled false
        set -U tide_right_prompt_items "status cmd_duration context jobs time nix_shell"
        set -U tide_right_prompt_prefix " "
        set -U tide_right_prompt_separator_diff_color " "
        set -U tide_right_prompt_separator_same_color " "
        set -U tide_right_prompt_suffix ""

        # Character (prompt symbol)
        set -U tide_character_color brgreen
        set -U tide_character_color_failure brred
        set -U tide_character_icon ">"
        set -U tide_character_vi_icon_default "<"
        set -U tide_character_vi_icon_replace "|"
        set -U tide_character_vi_icon_visual V

        # Status (exit code)
        set -U tide_status_bg_color normal
        set -U tide_status_bg_color_failure normal
        set -U tide_status_color green
        set -U tide_status_color_failure red
        set -U tide_status_icon "✔"
        set -U tide_status_icon_failure "✘"

        # PWD (current directory)
        set -U tide_pwd_bg_color normal
        set -U tide_pwd_color_anchors brcyan
        set -U tide_pwd_color_dirs cyan
        set -U tide_pwd_color_truncated_dirs magenta
        set -U tide_pwd_icon ""
        set -U tide_pwd_icon_home ""
        set -U tide_pwd_icon_unwritable ""
        set -U tide_pwd_markers .bzr .citc .git .hg .node-version .python-version \
                       .ruby-version .shorten_folder_marker .svn .terraform \
                       bun.lockb Cargo.toml composer.json CVS go.mod \
                       package.json build.zig

        # Git
        set -U tide_git_bg_color normal
        set -U tide_git_bg_color_unstable normal
        set -U tide_git_bg_color_urgent normal
        set -U tide_git_color_branch brgreen
        set -U tide_git_color_conflicted brred
        set -U tide_git_color_dirty bryellow
        set -U tide_git_color_operation brred
        set -U tide_git_color_staged bryellow
        set -U tide_git_color_stash brgreen
        set -U tide_git_color_untracked brblue
        set -U tide_git_color_upstream brgreen
        set -U tide_git_icon ""
        set -U tide_git_truncation_length 24
        set -U tide_git_truncation_strategy ""

        # Cmd duration
        set -U tide_cmd_duration_bg_color normal
        set -U tide_cmd_duration_color brblack
        set -U tide_cmd_duration_decimals 0
        set -U tide_cmd_duration_icon ""
        set -U tide_cmd_duration_threshold 3000

        # Context (user@host)
        set -U tide_context_always_display false
        set -U tide_context_bg_color normal
        set -U tide_context_color_default yellow
        set -U tide_context_color_root bryellow
        set -U tide_context_color_ssh yellow
        set -U tide_context_hostname_parts 1

        # Jobs (background tasks)
        set -U tide_jobs_bg_color normal
        set -U tide_jobs_color green
        set -U tide_jobs_icon ""
        set -U tide_jobs_number_threshold 1

        # Nix shell
        set -U tide_nix_shell_bg_color normal
        set -U tide_nix_shell_color brblue
        set -U tide_nix_shell_icon ""

        # Time
        set -U tide_time_bg_color normal
        set -U tide_time_color brblack
        set -U tide_time_format "%T"

        # Custom: jj (jujutsu)
        set -U tide_jj_bg_color normal
        set -U tide_jj_color brgreen
        set -U tide_jj_icon ""

        # Apply
        tide reload

        # ── Fish greeting / tools ──────────────────────────────
        set fish_greeting
        direnv hook fish | source
        zoxide init fish --cmd cd | source
        fastfetch

        set fish_cursor_default     block      blink
        set fish_cursor_insert      line       blink
        set fish_cursor_replace_one underscore blink
        set fish_cursor_visual      block

        # Use terminal colors
        set -x fish_color_autosuggestion      BE9F6E
        set -x fish_color_cancel              -r
        set -x fish_color_command             brgreen
        set -x fish_color_comment             brmagenta
        set -x fish_color_cwd                 green
        set -x fish_color_cwd_root            red
        set -x fish_color_end                 brmagenta
        set -x fish_color_error               brred
        set -x fish_color_escape              brcyan
        set -x fish_color_history_current     --bold
        set -x fish_color_host                normal
        set -x fish_color_host_remote         yellow
        set -x fish_color_match               --background=brblue
        set -x fish_color_normal              normal
        set -x fish_color_operator            cyan
        set -x fish_color_param               brblue
        set -x fish_color_quote               yellow
        set -x fish_color_redirection         bryellow
        set -x fish_color_search_match        'bryellow' '--background=brblack'
        set -x fish_color_selection           'white' '--bold' '--background=brblack'
        set -x fish_color_status              red
        set -x fish_color_user                brgreen
        set -x fish_color_valid_path          --underline
        set -x fish_pager_color_completion    BE9F6E
        set -x fish_pager_color_description   yellow
        set -x fish_pager_color_prefix        'white' '--bold' '--underline'
        set -x fish_pager_color_progress      'brwhite' '--background=cyan'
      '';
      # plugins = lib.optional useHelix {
      #   name = "fish-helix";
      #   src = pkgs.fetchFromGitHub {
      #     owner = "sshilovsky";
      #     repo = "fish-helix";
      #     rev = "8a5c7999ec67ae6d70de11334aa888734b3af8d7";
      #     hash = "sha256-04cL9/m5v0/5dkqz0tEqurOY+5sDjCB5mMKvqgpV4vM=";
      #   };
      # };
      shellAliases = {
        # file management
        cp = "cp --archive --recursive --verbose --interactive --progress";
        rsync = "rsync --archive --verbose --progress --inplace";

        mv = "mv -i";
        rm = "rm -i";
        df = "duf";
        du = "du -hc --time";
        tree = "tree --du -h";

        fzf = "fzf --color=16";

        grep = "grep --color=always";
        egrep = "egrep --color=always";
        fgrep = "fgrep --color=always";
      };
      shellAbbrs = {
        # jujutsu
        jjs = "jj split -r";
        jjm = "jj b m master --to";
        jjd = "jj describe -r";
        jjsq = "jj squash -r";
        jjgp = "jj git push";
        jjl = "jj -r 'all()'";
        jjdn = "jj describe && jj new";

        # nix
        ncg = "nix-collect-garbage";
        nrd = "sudo nixos-rebuild switch --flake $NH_FLAKE#sora";
        nrdtmpst = "nixos-rebuild switch --flake $NH_FLAKE#tempest --target-host root@192.168.15.12 --sudo --no-reexec";
        nixdev = "nix develop -c $SHELL";
        nix-shell = "nix-shell --command $SHELL";

        ff = "fastfetch";
        myip = "curl ifconfig.me -4";
        todo = "todo list --sort due";

        # fish
        src = "source ~/.config/fish/config.fish";

        # opencode
        opencode = "opencode attach http://localhost:4096";

        # text editor
        v = "hx";
        silicon = "silicon --to-clipboard --theme Dracula --no-line-number --no-window-controls --font 'JetBrainsMono Nerd Font Mono' --background '#24242C' --window-title";

        # cd
        ".." = "cd ..";

        # youtube-dl
        ytd = "youtube-dl -o '~/yt-downloads/%(title)s.%(ext)s' ";
        yta-best = "youtube-dl --extract-audio --audio-format best -o '~/yt-downloads/%(title)s.%(ext)s' ";
        yta-mp3 = "youtube-dl --extract-audio --audio-format mp3 -o '~/yt-downloads/%(title)s.%(ext)s' ";
        ytd-best = "youtube-dl -f mp4+bestaudio -o '~/yt-downloads/%(title)s.%(ext)s' ";

        # git
        gitall = "git add -A && git commit -a && git push";

        # misc
        pipes = "pipes.sh -t 3 -f 100 -R -r 0";
        htop = "btop";
        cat = "bat";
      };
      functions = {
        # Disable greeting (redundant with fastfetch)
        fish_greeting = "";

        # Extract Nix package names from PATH additions
        nix-inspect = ''
          set -s PATH | grep "PATH\[.*/nix/store" | cut -d '|' -f2 | \
            grep -v -e "-man" -e "-terminfo" | \
            perl -pe 's:^/nix/store/\w{32}-([^/]*)/bin$:$1:' | sort | uniq
        '';

        # Custom tide item: jujutsu VCS status
        _tide_item_jj = ''
          if not command -sq jj; or not jj root --quiet &>/dev/null
              return 1
          end

          set jj_status (jj log -r@ -n1 --ignore-working-copy --no-graph --color always -T '
            separate(" ",
              bookmarks.map(|x| if(
                x.name().substr(0, 10).starts_with(x.name()),
                x.name().substr(0, 10),
                x.name().substr(0, 9) ++ "…")
              ).join(" "),
              surround("\"","\"",
                if(
                  description.first_line().substr(0, 24).starts_with(description.first_line()),
                  description.first_line().substr(0, 24),
                  description.first_line().substr(0, 23) ++ "…"
                )
              ),
              change_id.shortest(),
              if(empty, "(empty)"),
              if(conflict, "(conflict)"),
              if(divergent, "(divergent)"),
              if(hidden, "(hidden)"),
            )
          ' | string trim)
          _tide_print_item jj $tide_jj_icon' ' (
              set_color black; echo -ns '('
              set_color normal; echo -ns "$(string join ', ' $jj_status)"
              set_color black; echo -ns ')'
          )
        '';

        # Custom tide item: enhanced nix-shell indicator
        _tide_item_nix3_shell = ''
          set packages (nix-inspect)
          if test -n "$IN_NIX_SHELL"
            set -q name; or set name nix-shell
            set -p packages $name
          end
          if set -q packages[1] &>/dev/null
            _tide_print_item nix3_shell $tide_nix3_shell_icon' ' " $(string shorten -m 40 "$packages")"
          end
        '';
      };
    };
  };
}

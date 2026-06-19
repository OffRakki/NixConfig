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
        # ── Tide prompt ────────────────────────────────────────

        source (functions --details _tide_sub_configure)
        _load_config rainbow
        _tide_finish

        set -U tide_prompt_transient_enabled true

        set -U tide_left_prompt_items pwd jj newline character
        set -U tide_right_prompt_items status cmd_duration context jobs time nix_shell

        set -U tide_character_color brgreen
        set -U tide_character_color_failure brred
        set -U tide_character_icon ">"

        set -U tide_jj_bg_color normal
        set -U tide_jj_color brgreen
        set -U tide_jj_icon ""

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
        set -x fish_color_autosuggestion      brblack
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
        set -x fish_pager_color_completion    normal
        set -x fish_pager_color_description   yellow
        set -x fish_pager_color_prefix        'white' '--bold' '--underline'
        set -x fish_pager_color_progress      'brwhite' '--background=cyan'
      '';
      shellAliases = {
        cp = "cp --archive --recursive --verbose --interactive";
        rsync = "rsync --archive --verbose --progress --inplace";
        ls = "eza";
        la = "eza -a";
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
        jjs = "jj split -r";
        jjm = "jj b m master --to";
        jjd = "jj describe -r";
        jjsq = "jj squash -r";
        jjgp = "jj git push";
        jjl = "jj -r 'all()'";
        ncg = "nix-collect-garbage";
        nrd = "sudo nixos-rebuild switch --flake $NH_FLAKE#tempest";
        nixdev = "nix develop -c $SHELL";
        nix-shell = "nix-shell --command $SHELL";
        ff = "fastfetch";
        src = "source ~/.config/fish/config.fish";
        v = "hx";
        silicon = "silicon --to-clipboard --theme Dracula --no-line-number --no-window-controls --font 'JetBrainsMono Nerd Font Mono' --background '#24242C' --window-title";
        ".." = "cd ..";
        ytd = "youtube-dl -o '~/yt-downloads/%(title)s.%(ext)s' ";
        yta-best = "youtube-dl --extract-audio --audio-format best -o '~/yt-downloads/%(title)s.%(ext)s' ";
        yta-mp3 = "youtube-dl --extract-audio --audio-format mp3 -o '~/yt-downloads/%(title)s.%(ext)s' ";
        ytd-best = "youtube-dl -f mp4+bestaudio -o '~/yt-downloads/%(title)s.%(ext)s' ";
        gitall = "git add -A && git commit -a && git push";
        pipes = "pipes.sh -t 3 -f 100 -R -r 0";
        htop = "btop";
        cat = "bat";
      };
      functions = {
        fish_greeting = "";
        nix-inspect = ''
          set -s PATH | grep "PATH\[.*/nix/store" | cut -d '|' -f2 | \
            grep -v -e "-man" -e "-terminfo" | \
            perl -pe 's:^/nix/store/\w{32}-([^/]*)/bin$:$1:' | sort | uniq
        '';
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

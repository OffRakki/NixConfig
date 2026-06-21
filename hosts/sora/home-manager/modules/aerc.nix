{
  config,
  pkgs,
  lib,
  ...
}: let
  tokenDir = "${config.xdg.configHome}/aerc/tokens";
  mailRoot = "${config.home.homeDirectory}/Mail";

  sasl2Plugins = pkgs.symlinkJoin {
    name = "sasl2";
    paths = [
      "${pkgs.cyrus_sasl.out}/lib/sasl2"
      "${pkgs.cyrus-sasl-xoauth2}/lib/sasl2"
    ];
  };

  aercTokenRefresh = pkgs.writeScriptBin "aerc-token-refresh" ''
    #!${pkgs.python3}/bin/python3
    import json, urllib.request, urllib.parse, sys

    token_file = sys.argv[1]
    with open(token_file) as f:
        data = json.load(f)

    payload = urllib.parse.urlencode({
        "client_id": data["client_id"],
        "client_secret": data["client_secret"],
        "refresh_token": data["refresh_token"],
        "grant_type": "refresh_token",
    }).encode()

    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    resp = urllib.request.urlopen(req)
    print(json.loads(resp.read())["access_token"])
  '';

  accounts = [
    {
      name = "Main";
      email = "offrakki@gmail.com";
      patterns = ["INBOX" "Linkedin" "LumisCards" "Nota Fiscal" "NuBank" "Riot" "Spotify" "Steam" "Twitch" "[Notion]" "[Gmail]/Drafts" "[Gmail]/Important" "[Gmail]/Sent Mail" "[Gmail]/Starred"];
    }
    {
      name = "Personal";
      email = "fernandomarques1505@gmail.com";
      patterns = ["INBOX" "Archive" "Mailspring/Snoozed" "Notes" "Personal" "Receipts" "Work" "[Gmail]/Drafts" "[Gmail]/Important" "[Gmail]/Sent Mail" "[Gmail]/Starred"];
    }
    {
      name = "Work";
      email = "fernando12.contato@gmail.com";
      patterns = ["INBOX" "[Gmail]/Drafts" "[Gmail]/Important" "[Gmail]/Sent Mail" "[Gmail]/Starred"];
    }
  ];

  encode = email: builtins.replaceStrings ["@"] ["%40"] email;
  safe = email: builtins.replaceStrings ["@"] ["-at-"] email;
  maildir = email: "${mailRoot}/${safe email}";

  # Generate aerc accounts.conf
  mkAccount = a: ''
    [${a.name}]
    source = maildir://${maildir a.email}
    outgoing = smtps+xoauth2://${encode a.email}@smtp.gmail.com:465
    outgoing-cred-cmd = ${aercTokenRefresh}/bin/aerc-token-refresh ${tokenDir}/${a.email}
    from = ${a.email}
    copy-to = true
    default = INBOX
  '';

  accountsConf = lib.concatStringsSep "\n\n" (map mkAccount accounts);

  # Generate mbsyncrc
  mkMbsyncAccount = a: ''
    IMAPAccount ${a.name}
    Host imap.gmail.com
    Port 993
    User ${a.email}
    PassCmd "${aercTokenRefresh}/bin/aerc-token-refresh ${tokenDir}/${a.email}"
    AuthMechs XOAUTH2
    TLSType IMAPS

    IMAPStore ${a.name}-remote
    Account ${a.name}

    MaildirStore ${a.name}-local
    Path ${maildir a.email}/
    Inbox ${maildir a.email}/INBOX
    SubFolders Verbatim

    Channel ${a.name}
    Far :${a.name}-remote:
    Near :${a.name}-local:
    Patterns ${lib.concatStringsSep " " (map (p: "\"${p}\"") a.patterns)}
    ExpireUnread no
    Create Both
    Sync Pull New
    Expunge None
    MaxMessages 1000
  '';

  mbsyncConf = lib.concatStringsSep "\n\n" (map mkMbsyncAccount accounts);

  mbsyncSerial = pkgs.writeShellScriptBin "mbsync-serial" ''
    set -euo pipefail

    state_dir="$HOME/.local/state/isync"
    backup_dir="$state_dir/backups"
    lock_file="$state_dir/mbsync-serial.lock"

    mkdir -p "$state_dir" "$backup_dir"
    exec 9>"$lock_file"
    ${pkgs.util-linux}/bin/flock -n 9 || {
      echo "mbsync already running; skipping this timer tick" >&2
      exit 0
    }

    cleanup_old_quarantines() {
      ${pkgs.findutils}/bin/find "$backup_dir" -mindepth 1 -maxdepth 1 -mtime +30 -exec ${pkgs.coreutils}/bin/rm -rf -- {} +
      ${pkgs.findutils}/bin/find "$state_dir" -maxdepth 1 -type f -name "*.corrupt-*" -mtime +30 -delete
    }

    quarantine_state_artifacts() {
      local state_file="$1"
      local stamp backup
      stamp="$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)"
      backup="$backup_dir/$(${pkgs.coreutils}/bin/basename "$state_file").$stamp"
      mkdir -p "$backup"

      for suffix in "" .journal .new .lock; do
        if [ -e "$state_file$suffix" ]; then
          ${pkgs.coreutils}/bin/cp -a "$state_file$suffix" "$backup/"
        fi
      done

      if [ -e "$state_file.journal" ]; then
        ${pkgs.coreutils}/bin/mv "$state_file.journal" "$state_file.journal.corrupt-$stamp"
      fi
      ${pkgs.coreutils}/bin/rm -f "$state_file.new" "$state_file.lock"
      echo "Quarantined isync state artifacts for $state_file; backup: $backup" >&2
    }

    preflight_channel() {
      local channel="$1"
      local state_file journal_size state_size

      while IFS= read -r -d "" state_file; do
        journal_size="$(${pkgs.coreutils}/bin/stat -c %s "$state_file.journal")"
        state_size=0
        [ -e "$state_file" ] && state_size="$(${pkgs.coreutils}/bin/stat -c %s "$state_file")"

        # A journal larger than 1 MiB or 10x the committed state is not normal
        # for these short timer syncs. Quarantine it before isync replays junk
        # into an assertion crash loop.
        if [ "$journal_size" -gt 1048576 ] || { [ "$state_size" -gt 0 ] && [ "$journal_size" -gt $((state_size * 10)) ]; }; then
          quarantine_state_artifacts "$state_file"
        fi
      done < <(${pkgs.findutils}/bin/find "$state_dir" -maxdepth 1 -type f -name ":''${channel}-remote:*_:''${channel}-local:*.journal" -print0)
    }

    run_channel() {
      local channel="$1"
      local log status
      log="$(${pkgs.coreutils}/bin/mktemp -t "mbsync-$channel.XXXXXX.log")"

      preflight_channel "$channel"

      set +e
      ${pkgs.isync}/bin/mbsync -c "${config.home.homeDirectory}/.mbsyncrc" "$channel" > >(tee "$log") 2> >(tee -a "$log" >&2)
      status=$?
      set -e

      if [ "$status" -eq 134 ] || ${pkgs.gnugrep}/bin/grep -q "cmp_srec_far\|Assertion.*au != bu" "$log"; then
        echo "mbsync crashed on $channel; quarantining channel journals and retrying once" >&2
        while IFS= read -r -d "" state_file; do
          quarantine_state_artifacts "$state_file"
        done < <(${pkgs.findutils}/bin/find "$state_dir" -maxdepth 1 -type f -name ":''${channel}-remote:*_:''${channel}-local:*" ! -name "*.journal" ! -name "*.new" ! -name "*.lock" ! -name "*.corrupt-*" -print0)

        ${pkgs.isync}/bin/mbsync -c "${config.home.homeDirectory}/.mbsyncrc" "$channel"
        return
      fi

      return "$status"
    }

    cleanup_old_quarantines

    for channel in Main Personal Work; do
      run_channel "$channel"
    done
  '';
in {
  home.persistence."/persist".directories = [
    ".config/aerc"
    "Mail"
  ];

  home.packages = with pkgs; [aerc isync cyrus-sasl-xoauth2 w3m urlscan imv];

  home.sessionVariables.SASL_PATH = "${sasl2Plugins}";

  xdg.desktopEntries.aerc = {
    name = "Aerc";
    genericName = "Email Client";
    comment = "Read and send emails";
    exec = "aerc %U";
    icon = "mail";
    terminal = true;
    categories = ["Network" "Email" "ConsoleOnly"];
    type = "Application";
    mimeType = ["x-scheme-handler/mailto"];
  };

  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/mailto" = "aerc.desktop";
  };

  home.activation.setupMailDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "${config.home.homeDirectory}/Mail"
        ${lib.concatStringsSep "\n" (map (a: "mkdir -p ${maildir a.email}") accounts)}
        mkdir -p "${config.xdg.configHome}/aerc"
        (umask 077; cat > "${config.xdg.configHome}/aerc/accounts.conf") << 'AERCCONF'
    ${accountsConf}
    AERCCONF
  '';

  home.file.".mbsyncrc".text = mbsyncConf;

  systemd.user = {
    services.mbsync = {
      Unit = {
        Description = "mbsync mail sync";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
      };
      Service = {
        Type = "oneshot";
        TimeoutStartSec = "15min";
        Environment = "SASL_PATH=${sasl2Plugins}";
        ExecStart = "${mbsyncSerial}/bin/mbsync-serial";
      };
    };
    timers.mbsync = {
      Install = {
        WantedBy = ["timers.target"];
      };
      Timer = {
        OnBootSec = "2m";
        OnCalendar = "*:0/5";
        Persistent = true;
      };
    };
  };

  xdg.configFile."aerc/aerc.conf".text = ''
    [general]
    default-save-path = ${config.home.homeDirectory}/Downloads
    log-file = ${config.xdg.configHome}/aerc/aerc.log

    [ui]
    index-format = %D %-18.18n %-20.20r %s
    sidebar-width = 20
    sort = -r date
    next-message-on-delete = true
    styleset-dirs = ${config.xdg.configHome}/aerc/stylesets/
    styleset-name = dark

    [compose]
    editor = hx
    header-placeholders = To:Cc:Subject:

    [viewer]
    pager-msgs = 10
    header-layout=From,To,Cc,Subject,Date

    [filters]
    text/plain = colorize
    text/html = ${pkgs.w3m}/bin/w3m -I UTF-8 -T text/html -cols 80 -o display_image=false -dump
    text/calendar = ${pkgs.w3m}/bin/w3m -I UTF-8 -T text/html -cols 80 -o display_image=false -dump

    [openers]
    image/* = ${pkgs.imv}/bin/imv %s
    application/* = xdg-open %s
  '';

  xdg.configFile."aerc/stylesets/dark".text = ''
    *.selected.bg = #2d5c8a
    *.selected.fg = #ffffff
    *.selected.bold = true

    *error.fg = #f44747
    *warning.fg = #cca700
    *success.fg = #6a9955

    title.fg = #ffffff
    title.bold = true
    header.fg = #4fc1ff
    header.bold = true

    msglist_unread.fg = #ffffff
    msglist_unread.bold = true
    msglist_flagged.fg = #ffcc00
    msglist_flagged.bold = true
    msglist_deleted.fg = #808080
    msglist_marked.fg = #6a9955
    msglist_marked.bold = true
    msglist_result.fg = #4fc1ff

    dirlist_unread.bold = true

    completion_pill.bg = #2d5c8a
    completion_pill.fg = #ffffff
    completion_default.fg = #d4d4d4

    statusline_default.bg = #2d5c8a
    statusline_default.fg = #ffffff

    tab.selected.fg = #4fc1ff
    tab.selected.bold = true

    border.fg = #555555
  '';

  xdg.configFile."urlscan/config.json".text = builtins.toJSON {
    palettes = {
      dark = [
        ["header" "white" "dark blue" "standout" "#ffffff" "#2d5c8a"]
        ["footer" "white" "dark blue" "standout" "#ffffff" "#2d5c8a"]
        ["search" "white" "dark green" "standout" "#ffffff" "#6a9955"]
        ["msgtext" "" "" "" "#d4d4d4" "#1c1c1c"]
        ["msgtext:ellipses" "light gray" "black" "" "#aaaaaa" "#1c1c1c"]
        ["urlref:number:braces" "light gray" "black" "" "#aaaaaa" "#1c1c1c"]
        ["urlref:number" "yellow" "black" "standout" "#ffcc00" "#1c1c1c"]
        ["urlref:url" "white" "black" "standout" "#4fc1ff" "#1c1c1c"]
        ["url:sel" "white" "dark blue" "bold" "#ffffff" "#2d5c8a"]
      ];
      default = [
        ["header" "white" "dark blue" "standout" "#ffffff" "#0000aa"]
        ["footer" "white" "dark red" "standout" "#ffffff" "#aa0000"]
        ["search" "white" "dark green" "standout" "#ffffff" "#00aa00"]
        ["msgtext" "" "" "" "" ""]
        ["msgtext:ellipses" "light gray" "black" "" "#aaaaaa" "#000000"]
        ["urlref:number:braces" "light gray" "black" "" "#aaaaaa" "#000000"]
        ["urlref:number" "yellow" "black" "standout" "#ffff00" "#000000"]
        ["urlref:url" "white" "black" "standout" "#ffffff" "#000000"]
        ["url:sel" "white" "dark blue" "bold" "#ffffff" "#0000aa"]
      ];
      bw = [
        ["header" "black" "light gray" "standout" "#000000" "#aaaaaa"]
        ["footer" "black" "light gray" "standout" "#000000" "#aaaaaa"]
        ["search" "black" "light gray" "standout" "#000000" "#aaaaaa"]
        ["msgtext" "" "" "" "" ""]
        ["msgtext:ellipses" "white" "black" "" "#ffffff" "#000000"]
        ["urlref:number:braces" "white" "black" "" "#ffffff" "#000000"]
        ["urlref:number" "white" "black" "standout" "#ffffff" "#000000"]
        ["urlref:url" "white" "black" "standout" "#ffffff" "#000000"]
        ["url:sel" "black" "light gray" "bold" "#000000" "#aaaaaa"]
      ];
      catppuccin = [
        ["header" "white" "dark blue" "standout" "#CDD6F4" "#89B4FA"]
        ["footer" "white" "dark red" "standout" "#CDD6F4" "#F38BA8"]
        ["search" "white" "dark green" "standout" "#CDD6F4" "#A6E3A1"]
        ["msgtext" "" "" "" "#CDD6F4" "#1E1E2E"]
        ["msgtext:ellipses" "light gray" "black" "" "#B4BEFE" "#1E1E2E"]
        ["urlref:number:braces" "light gray" "black" "" "#B4BEFE" "#1E1E2E"]
        ["urlref:number" "yellow" "black" "standout" "#F9E2AF" "#1E1E2E"]
        ["urlref:url" "white" "black" "standout" "#CBA6F7" "#1E1E2E"]
        ["url:sel" "white" "dark blue" "bold" "#F5E0DC" "#313244"]
      ];
    };
  };

  xdg.configFile."aerc/binds.conf".text = ''
    <C-p> = :prev-tab<Enter>
    <C-PgUp> = :prev-tab<Enter>
    <C-n> = :next-tab<Enter>
    <C-PgDn> = :next-tab<Enter>
    \[t = :prev-tab<Enter>
    \]t = :next-tab<Enter>
    <C-t> = :term<Enter>
    ? = :help keys<Enter>
    <C-c> = :prompt 'Quit?' quit<Enter>
    <C-q> = :prompt 'Quit?' quit<Enter>
    <C-z> = :suspend<Enter>

    [messages]
    q = :quit<Enter>
    Q = :quit<Enter>
    . = :repeat

    j = :next<Enter>
    <Down> = :next<Enter>
    <C-d> = :next 50%<Enter>
    <C-f> = :next 100%<Enter>
    <PgDn> = :next 100%<Enter>

    k = :prev<Enter>
    <Up> = :prev<Enter>
    <C-u> = :prev 50%<Enter>
    <C-b> = :prev 100%<Enter>
    <PgUp> = :prev 100%<Enter>
    g = :select 0<Enter>
    G = :select -1<Enter>

    J = :next-folder<Enter>
    <C-j> = :next-folder<Enter>
    <C-Down> = :next-folder<Enter>
    K = :prev-folder<Enter>
    <C-k> = :prev-folder<Enter>
    <C-Up> = :prev-folder<Enter>
    H = :collapse-folder<Enter>
    <C-Left> = :collapse-folder<Enter>
    L = :expand-folder<Enter>
    <C-Right> = :expand-folder<Enter>
    tf = :toggle-folder<Enter>

    v = :mark -t<Enter>
    <Space> = :mark -t<Enter>:next<Enter>
    V = :mark -v<Enter>

    T = :toggle-threads<Enter>
    zc = :fold<Enter>
    zo = :unfold<Enter>
    za = :fold -t<Enter>
    zM = :fold -a<Enter>
    zR = :unfold -a<Enter>
    <tab> = :fold -t<Enter>

    zz = :align center<Enter>
    zt = :align top<Enter>
    zb = :align bottom<Enter>

    <Enter> = :view<Enter>
    d = :choose -o y 'Really delete this message' delete-message<Enter>
    D = :delete<Enter>
    a = :archive flat<Enter>
    A = :unmark -a<Enter>:mark -T<Enter>:archive flat<Enter>

    C = :compose<Enter>
    m = :compose<Enter>

    b = :bounce<space>

    rr = :reply -a<Enter>
    rq = :reply -aq<Enter>
    Rr = :reply<Enter>
    Rq = :reply -q<Enter>

    c = :cf<space>
    $ = :term<space>
    ! = :term<space>
    | = :pipe<space>

    / = :search<space>
    \ = :filter<space>
    n = :next-result<Enter>
    N = :prev-result<Enter>
    <Esc> = :clear<Enter>

    s = :split<Enter>
    S = :vsplit<Enter>

    pl = :patch list<Enter>
    pa = :patch apply <Tab>
    pd = :patch drop <Tab>
    pb = :patch rebase<Enter>
    pt = :patch term<Enter>
    ps = :patch switch <Tab>

    [messages:folder=Drafts]
    <Enter> = :recall<Enter>

    [view]
    / = :toggle-key-passthrough<Enter>/
    q = :close<Enter>
    O = :open<Enter>
    o = :open<Enter>
    S = :save<space>
    | = :pipe<space>
    D = :delete<Enter>
    A = :archive flat<Enter>

    <C-y> = :copy-link <space>
    <C-l> = :open-link <space>
    u = :pipe -m urlscan<Enter>

    f = :forward<Enter>
    rr = :reply -a<Enter>
    rq = :reply -aq<Enter>
    Rr = :reply<Enter>
    Rq = :reply -q<Enter>

    H = :toggle-headers<Enter>
    <C-k> = :prev-part<Enter>
    <C-Up> = :prev-part<Enter>
    <C-j> = :next-part<Enter>
    <C-Down> = :next-part<Enter>
    J = :next<Enter>
    <C-Right> = :next<Enter>
    K = :prev<Enter>
    <C-Left> = :prev<Enter>

    [view::passthrough]
    $noinherit = true
    $ex = <C-x>
    <Esc> = :toggle-key-passthrough<Enter>

    [compose]
    $noinherit = true
    $ex = <C-x>
    $complete = <C-o>
    <C-k> = :prev-field<Enter>
    <C-Up> = :prev-field<Enter>
    <C-j> = :next-field<Enter>
    <C-Down> = :next-field<Enter>
    <A-p> = :switch-account -p<Enter>
    <A-n> = :switch-account -n<Enter>
    <tab> = :next-field<Enter>
    <backtab> = :prev-field<Enter>
    <C-p> = :prev-tab<Enter>
    <C-PgUp> = :prev-tab<Enter>
    <C-n> = :next-tab<Enter>
    <C-PgDn> = :next-tab<Enter>

    [compose::editor]
    $noinherit = true
    $ex = <C-x>
    <C-k> = :prev-field<Enter>
    <C-Up> = :prev-field<Enter>
    <C-j> = :next-field<Enter>
    <C-Down> = :next-field<Enter>
    <C-p> = :prev-tab<Enter>
    <C-PgUp> = :prev-tab<Enter>
    <C-n> = :next-tab<Enter>
    <C-PgDn> = :next-tab<Enter>

    [compose::review]
    y = :send<Enter>
    n = :abort<Enter>
    s = :sign<Enter>
    x = :encrypt<Enter>
    v = :preview<Enter>
    p = :postpone<Enter>
    q = :choose -o d discard abort -o p postpone postpone<Enter>
    e = :edit<Enter>
    a = :attach<space>
    d = :detach<space>

    [terminal]
    $noinherit = true
    $ex = <C-x>

    <C-p> = :prev-tab<Enter>
    <C-n> = :next-tab<Enter>
    <C-PgUp> = :prev-tab<Enter>
    <C-PgDn> = :next-tab<Enter>
  '';
}

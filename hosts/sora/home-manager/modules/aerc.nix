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
    }
    {
      name = "Personal";
      email = "fernandomarques1505@gmail.com";
    }
    {
      name = "Work";
      email = "fernando12.contato@gmail.com";
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
    Patterns * ! "[Gmail]/All Mail"
    Create Both
    Sync All
    Expunge Both
  '';

  mbsyncConf = lib.concatStringsSep "\n\n" (map mkMbsyncAccount accounts);
in {
  home.persistence."/persist".directories = [
    ".config/aerc"
    "Mail"
  ];

  home.packages = with pkgs; [aerc isync cyrus-sasl-xoauth2 w3m];

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
        Environment = "SASL_PATH=${sasl2Plugins}";
        ExecStart = "${pkgs.isync}/bin/mbsync -a";
      };
    };
    timers.mbsync = {
      Install = {
        WantedBy = ["timers.target"];
      };
      Timer = {
        OnBootSec = "5m";
        OnUnitActiveSec = "15m";
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
    text/html = ${pkgs.w3m}/bin/w3m -I UTF-8 -T text/html -cols 80 -o display_image=false -dump
    text/calendar = ${pkgs.w3m}/bin/w3m -I UTF-8 -T text/html -cols 80 -o display_image=false -dump
  '';

  xdg.configFile."aerc/stylesets/dark".text = ''
    *.selected.fg = #ffffff
    *.selected.bg = #383838
    *.selected.bold = true

    *error.fg = #e06c75
    *warning.fg = #e5c07b
    *success.fg = #98c379

    title.reverse = true

    msglist_unread.bold = true
    msglist_flagged.fg = #e06c75
    msglist_deleted.fg = #5c6370
    msglist_marked.fg = #98c379
    msglist_result.fg = #61afef

    dirlist_default.fg = #abb2bf
    dirlist_unread.bold = true

    completion_pill.bg = #383838
    completion_selected.bg = #264f78

    statusline_default.reverse = true

    tab.reverse = true
    tab.selected.fg = #61afef
    tab.selected.bold = true

    border.reverse = true
  '';

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
    <C-Down> = :next-folder<Enter>
    K = :prev-folder<Enter>
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

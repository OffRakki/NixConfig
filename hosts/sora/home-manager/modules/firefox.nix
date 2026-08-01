{...}: {
  home.persistence."/persist".directories = [".config/mozilla"];

  programs.firefox = {
    enable = true;
    configPath = ".config/mozilla/firefox";
    profiles = {
      Rakki = {
        settings = {
          "browser.aboutConfig.showWarning" = false;
          "browser.ai.control.sidebarChatbot" = "blocked";
          "browser.bookmarks.editDialog.showForNewBookmarks" = false;
          "browser.formfill.enable" = false;
          "browser.ml.chat.enabled" = false;
          "browser.ml.chat.page" = false;
          "browser.ml.chat.sidebar" = false;
          "browser.newtabpage.activity-stream.showSponsoredCheckboxes" = false;
          "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
          "browser.newtabpage.pinned" = [{url = "https://www.youtube.com/";}];
          "browser.shell.checkDefaultBrowser" = false;
          "browser.startup.homepage" = "http://localhost:1201/";
          "browser.startup.page" = 3;
          "browser.tabs.groups.smart.userEnabled" = false;
          "browser.toolbars.bookmarks.visibility" = "never";
          "browser.translations.automaticallyPopup" = false;
          "datareporting.healthreport.uploadEnabled" = false;
          "datareporting.usage.uploadEnabled" = false;
          "extensions.formautofill.addresses.enabled" = false;
          "extensions.formautofill.creditCards.enabled" = false;
          "findbar.highlightAll" = true;
          "font.default.x-western" = "sans-serif";
          "font.name.monospace.x-western" = "JetBrainsMono Nerd Font";
          "font.name.sans-serif.x-western" = "JetBrainsMono Nerd Font";
          "font.name.serif.x-western" = "JetBrainsMono Nerd Font";
          "font.size.monospace.x-western" = 14;
          "full-screen-api.warning.delay" = 0;
          "full-screen-api.warning.timeout" = 0;
          "general.autoScroll" = true;
          "layout.css.prefers-color-scheme.content" = 2;
          "media.peerconnection.ice.default_address_only" = true;
          "media.peerconnection.ice.no_host" = true;
          "media.peerconnection.ice.proxy_only_if_behind_proxy" = true;
          "media.videocontrols.picture-in-picture.video-toggle.enabled" = false;
          "network.dns.disablePrefetch" = true;
          "network.http.speculative-parallel-limit" = 0;
          "network.prefetch-next" = false;
          "nimbus.rollouts.enabled" = false;
          "privacy.clearOnShutdown_v2.formdata" = true;
          "privacy.globalprivacycontrol.enabled" = true;
          "privacy.userContext.enabled" = true;
          "privacy.userContext.ui.enabled" = true;
          "sidebar.visibility" = "hide-sidebar";
          "signon.autofillForms" = false;
          "signon.generation.enabled" = false;
          "signon.management.page.breach-alerts.enabled" = false;
          "signon.rememberSignons" = false;
          "ui.key.menuAccessKeyFocuses" = false;
          "widget.content.allow-gtk-dark-theme" = true;
        };
        userChrome = ''
          #TabsToolbar { visibility: collapse !important; }
          #sidebar-panel-header { display: none; }
          #sidebar-header { display: none; }
        '';
      };
    };
  };
}

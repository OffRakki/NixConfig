{osConfig, ...}: let
  searchProperties = {
    search-engine = "https://www.google.com/search?q={QUERY}";
    autofocus = true;
    placeholder = "Generate Luminous Element!";
    bangs = [
      {
        title = "DuckDuckGo";
        shortcut = "!d";
        url = "https://duckduckgo.com/?q={QUERY}";
      }
      {
        title = "YouTube";
        shortcut = "!yt";
        url = "https://www.youtube.com/results?search_query={QUERY}";
      }
      {
        title = "Anilist";
        shortcut = "!ani";
        url = "https://anilist.co/search/anime?search={QUERY}";
      }
      {
        title = "AnilistProfile";
        shortcut = "!anip";
        url = "https://anilist.co/user/{QUERY}";
      }
      {
        title = "MercadoLivre";
        shortcut = "!ml";
        url = "https://lista.mercadolivre.com.br/{QUERY}";
      }
      {
        title = "gmail";
        shortcut = "!gm";
        url = "https://mail.google.com/mail/u/1/#inbox";
      }
    ];
  };

  minecraftWidget = {
    type = "custom-api";
    title = "Minecraft";
    url = "https://api.mcstatus.io/v2/status/java/mc.tmpst.moe";
    cache = "3600s";
    template = ''
      <div style="display:flex; align-items:center; gap:12px;">
        <div style="width:40px; height:40px; flex-shrink:0;  border-radius:4px; display:flex; justify-content:center; align-items:center; overflow:hidden;">
          {{ if .JSON.Bool "online" }}
            <img src="{{ .JSON.String "icon" | safeURL }}" width="64" height="64" style="object-fit:contain;">
          {{ else }}
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" style="width:32px; height:32px; opacity:0.5;">
              <path fill-rule="evenodd" d="M1 5.25A2.25 2.25 0 0 1 3.25 3h13.5A2.25 2.25 0 0 1 19 5.25v9.5A2.25 2.25 0 0 1 16.75 17H3.25A2.25 2.25 0 0 1 1 14.75v-9.5Zm1.5 5.81v3.69c0 .414.336.75.75.75h13.5a.75.75 0 0 0 .75-.75v-2.69l-2.22-2.219a.75.75 0 0 0-1.06 0l-1.91 1.909.47.47a.75.75 0 1 1-1.06 1.06L6.53 8.091a.75.75 0 0 0-1.06 0l-2.97 2.97ZM12 7a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z" clip-rule="evenodd" />
            </svg>
          {{ end }}
        </div>

        <div style="flex-grow:1; min-width:0;">
          <a class="size-h4 block text-truncate color-highlight">
            {{ .JSON.String "host" }}
            {{ if .JSON.Bool "online" }}
            <span
              style="width: 8px; height: 8px; border-radius: 50%; background-color: var(--color-positive); display: inline-block; vertical-align: middle;"
              data-popover-type="text"
              data-popover-text="Online"
            ></span>
            {{ else }}
            <span
              style="width: 8px; height: 8px; border-radius: 50%; background-color: var(--color-negative); display: inline-block; vertical-align: middle;"
              data-popover-type="text"
              data-popover-text="Offline"
            ></span>
            {{ end }}
          </a>

          <ul class="list-horizontal-text">
            <li>
              {{ if .JSON.Bool "online" }}
              <span>{{ .JSON.String "version.name_clean" }}</span>
              {{ else }}
              <span>Offline</span>
              {{ end }}
            </li>
            {{ if .JSON.Bool "online" }}
            <li data-popover-type="html">
              <div data-popover-html>
                {{ range .JSON.Array "players.list" }}{{ .String "name_clean" }}<br>{{ end }}
              </div>
              <p style="display:inline-flex;align-items:center;">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6" style="height:1em;vertical-align:middle;margin-right:0.5em;">
                  <path fill-rule="evenodd" d="M7.5 6a4.5 4.5 0 1 1 9 0 4.5 4.5 0 0 1-9 0ZM3.751 20.105a8.25 8.25 0 0 1 16.498 0 .75.75 0 0 1-.437.695A18.683 18.683 0 0 1 12 22.5c-2.786 0-5.433-.608-7.812-1.7a.75.75 0 0 1-.437-.695Z" clip-rule="evenodd" />
                </svg>
                {{ .JSON.Int "players.online" | formatNumber }}/{{ .JSON.Int "players.max" | formatNumber }} players
              </p>
            </li>
            {{ else }}
            <li>
              <p style="display:inline-flex;align-items:center;">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6" style="height:1em;vertical-align:middle;margin-right:0.5em;opacity:0.5;">
                  <path fill-rule="evenodd" d="M7.5 6a4.5 4.5 0 1 1 9 0 4.5 4.5 0 0 1-9 0ZM3.751 20.105a8.25 8.25 0 0 1 16.498 0 .75.75 0 0 1-.437.695A18.683 18.683 0 0 1 12 22.5c-2.786 0-5.433-.608-7.812-1.7a.75.75 0 0 1-.437-.695Z" clip-rule="evenodd" />
                </svg>
                0 players
              </p>
            </li>
            {{ end }}
          </ul>
        </div>
      </div>
    '';
  };
in {
  services.glance = {
    enable = true;
    settings = {
      server.port = 1201;

      theme = {
        background-color = "240 13 14";
        primary-color = "51 33 68";
        negative-color = "358 100 68";
        contrast-multiplier = 1.2;
      };

      branding.custom-footer = ''
        <p><a href="http://github.com/offrakki">Rakki</a></p>
      '';

      pages = [
        {
          name = "Dashboard";
          hide-desktop-navigation = true;
          center-vertically = false;
          width = "wide";
          head-widgets = [
            ({
                type = "search";
                hide-header = true;
              }
              // searchProperties)
          ];
          columns = [
            {
              size = "small";
              widgets = [
                {
                  type = "clock";
                  hour-format = "24h";
                  timezones = [
                    {
                      timezone = "America/Sao_Paulo";
                      label = "São Paulo";
                    }
                  ];
                }
                {
                  type = "weather";
                  units = "metric";
                  hour-format = "12h";
                  location = "Piracicaba, Brazil";
                }
                {
                  type = "custom-api";
                  title = "Steam Specials";
                  cache = "12h";
                  url = "https://store.steampowered.com/api/featuredcategories?cc=us";
                  template = ''
                    <ul class="list list-gap-10 collapsible-container" data-collapse-after="5">
                    {{ range .JSON.Array "specials.items" }}
                      <li>
                        <a class="size-h4 color-highlight block text-truncate" href="https://store.steampowered.com/app/{{ .Int "id" }}/">{{ .String "name" }}</a>
                        <ul class="list-horizontal-text">
                          <li>{{ div (.Int "final_price" | toFloat) 100 | printf "$%.2f" }}</li>
                          {{ $discount := .Int "discount_percent" }}
                          <li{{ if ge $discount 40 }} class="color-positive"{{ end }}>{{ $discount }}% off</li>
                        </ul>
                      </li>
                    {{ end }}
                    </ul>
                  '';
                }
                {
                  type = "releases";
                  show-source-icon = true;
                  cache = "1d";
                  token = osConfig.sops.placeholder.gitToken;
                  repositories = [
                    "OffRakki/NixConfig"
                    "glanceapp/glance"
                    "immich-app/immich"
                    "spacedriveapp/spacedrive"
                  ];
                }
                {
                  type = "repository";
                  repository = "OffRakki/NixConfig";
                  pull-requests-limit = 5;
                  issues-limit = 3;
                  commits-limit = 3;
                }
              ];
            }
            {
              size = "full";
              widgets = [
                {
                  type = "group";
                  widgets = [
                    {
                      type = "bookmarks";
                      groups = [
                        {
                          title = "AI";
                          color = "214 100 50";
                          links = [
                            {
                              title = "Open WebUI";
                              url = "http://localhost:8090/";
                            }
                            {
                              title = "OpenAI API";
                              url = "https://platform.openai.com/settings/organization/usage";
                            }
                            {
                              title = "DeepSeek API";
                              url = "https://platform.deepseek.com/usage";
                            }
                            {
                              title = "Claude API";
                              url = "https://console.anthropic.com/";
                            }
                          ];
                        }
                        {
                          title = "Social";
                          color = "328 85 57";
                          links = [
                            {
                              title = "X";
                              url = "https://x.com/";
                            }
                            {
                              title = "Instagram";
                              url = "https://www.instagram.com/";
                            }
                          ];
                        }
                        {
                          title = "Dev";
                          color = "210 12 45";
                          links = [
                            {
                              title = "GitHub";
                              url = "https://github.com/";
                            }
                            {
                              title = "Codeberg";
                              url = "https://codeberg.org/";
                            }
                          ];
                        }
                        {
                          title = "Cloud";
                          color = "43 77 44";
                          links = [
                            {
                              title = "Cloudflare";
                              url = "https://dash.cloudflare.com/";
                            }
                          ];
                        }
                        {
                          title = "Media";
                          color = "0 100 50";
                          links = [
                            {
                              title = "YouTube";
                              url = "https://www.youtube.com/";
                            }
                          ];
                        }
                      ];
                    }
                    {type = "to-do";}
                  ];
                }
                {
                  type = "group";
                  widgets = [
                    {
                      type = "rss";
                      title = "animeschedule";
                      title-url = "https://animeschedule.net/";
                      style = "vertical-list";
                      feeds = [
                        {
                          url = "https://animeschedule.net/jpnrss.xml";
                          title = "animeschedule";
                        }
                      ];
                    }
                  ];
                }
                {
                  type = "reddit";
                  collapse-after = 5;
                  subreddit = "unixPorn";
                  show-thumbnails = true;
                }
                minecraftWidget
              ];
            }
            {
              size = "full";
              widgets = [
                {
                  type = "videos";
                  hide-header = true;
                  style = "grid-cards";
                  collapse-after-rows = 5;
                  channels = [
                    "UCXuqSBlHAE6Xw-yeJA0Tunw" # Linus Tech Tips
                    "UC9x0AN7BWHpCDHSm9NiJFJQ" # NetworkChuck
                    "UC0vBXGSyV14uvJ4hECDOl0Q" # Techquickie
                    "UCQSpnDG3YsFNf5-qHocF-WQ" # ThioJoe
                  ];
                }
              ];
            }
          ];
        }
      ];
    };
  };
}

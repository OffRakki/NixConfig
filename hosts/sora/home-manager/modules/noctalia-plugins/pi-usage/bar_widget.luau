--!nonstrict
-- Standalone systemd timers (openai-usage, antigravity-usage) own network/auth
-- and refresh every five minutes. This widget only reads sanitized cache files.

local REFRESH_MS = 30000
local STALE_SEC = 900
local CMD = 'dir="${XDG_CACHE_HOME:-$HOME/.cache}/noctalia"; '
    .. 'o=$(jq -c . "$dir/openai-usage.json" 2>/dev/null); [ -n "$o" ] || o=null; '
    .. 'a=$(jq -c . "$dir/antigravity-usage.json" 2>/dev/null); [ -n "$a" ] || a=null; '
    .. 'jq -cn --argjson openai "$o" --argjson antigravity "$a" "{openai:\\$openai,antigravity:\\$antigravity}"'
local REFRESH_CMD = "sh -c 'systemctl --user start openai-usage.service & p1=$!; "
    .. "systemctl --user start antigravity-usage.service & p2=$!; wait $p1 $p2'"

local PROVIDERS = {
    { key = "openai", title = "OpenAI", glyph = "brand-openai" },
    { key = "antigravity", title = "Antigravity", glyph = "brand-google" },
}

local state = {}

local function parseIso(value)
    if type(value) ~= "string" then return nil end
    local y, mo, d, h, mi, s = value:match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
    if y == nil then return nil end
    local guess = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
    return guess + (guess - os.time(os.date("!*t", guess)))
end

local function shortLabel(label)
    local l = string.lower(tostring(label or ""))
    if l == "week" or l == "weekly" then return "W" end
    return tostring(label or "?")
end

local function colorFor(pct)
    if pct >= 90 then return "error" end
    if pct >= 70 then return "tertiary" end
    return "primary"
end

local function duration(sec)
    if sec <= 0 then return "now" end
    local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
    if d > 0 then return string.format("%dd%dh", d, h) end
    if h > 0 then return string.format("%dh%dm", h, m) end
    return string.format("%dm", m)
end

-- A window whose reset time has passed no longer reflects real usage.
local function windowState(window, now)
    local resetAt = parseIso(window.resetAt)
    if resetAt ~= nil and resetAt <= now then return nil, "reset" end
    return math.max(0, math.min(100, tonumber(window.usedPercent) or 0)),
        resetAt and ("↻ " .. duration(resetAt - now)) or ""
end

local function glyphFor(provider, fallback)
    if provider == "anthropic" then return "message-chatbot" end
    if provider == "antigravity" then return "brand-google" end
    if provider == "openai" then return "brand-openai" end
    return fallback
end

local function appendWindows(parts, tooltip, windows, tooltipPrefix, stale, now)
    for _, window in ipairs(windows or {}) do
        local pct, note = windowState(window, now)
        local label = shortLabel(window.label)
        local tipKey = tooltipPrefix .. " · " .. tostring(window.label or "?")
        if pct ~= nil then
            local rounded = math.floor(pct + 0.5)
            parts[#parts + 1] = ui.progress({ progress = pct / 100, fill = colorFor(pct),
                track = "on_surface/0.16", radius = 0, width = 22, height = 5 })
            parts[#parts + 1] = ui.label({ text = string.format("%s %d%%", label, rounded),
                fontSize = 11, fontWeight = "semibold", color = stale and "on_surface_variant" or "on_surface", maxLines = 1 })
            tooltip[#tooltip + 1] = {
                key = tipKey,
                value = note ~= "" and string.format("%d%% · %s", rounded, note) or string.format("%d%%", rounded),
            }
        else
            parts[#parts + 1] = ui.label({ text = label .. " —", fontSize = 11, color = "on_surface_variant", maxLines = 1 })
            tooltip[#tooltip + 1] = { key = tipKey, value = "reset" }
        end
    end
end

local function render()
    local now = os.time()
    local segments, tooltip = {}, {}

    for _, spec in ipairs(PROVIDERS) do
        local payload = state[spec.key]
        local entry = type(payload) == "table" and type(payload.lastGood) == "table" and payload.lastGood or nil
        local usage = entry and type(entry.usage) == "table" and entry.usage or nil
        local err = type(payload) == "table" and payload.error or nil

        if usage ~= nil then
            local fetched = (tonumber(entry.fetchedAt) or 0) / 1000
            local stale = now - fetched > STALE_SEC
            local parts = {}

            if type(usage.groups) == "table" and #usage.groups > 0 then
                for _, group in ipairs(usage.groups) do
                    if group.id == "gemini" then
                        appendWindows(parts, tooltip, group.windows, tostring(group.name or spec.title), stale, now)
                        break
                    end
                end
            else
                appendWindows(parts, tooltip, usage.windows, spec.title, stale, now)
            end

            if #parts > 0 then
                if stale then
                    tooltip[#tooltip + 1] = { key = spec.title .. " Cache", value = duration(now - fetched) .. " old" }
                end

                if #segments > 0 then
                    segments[#segments + 1] = ui.box({ width = 1, height = 15, fill = "outline/0.35" })
                end
                segments[#segments + 1] = ui.row({ key = spec.key, align = "center", gap = 5 }, {
                    ui.glyph({ name = glyphFor(usage.provider, spec.glyph), size = 13, color = "primary" }),
                    ui.row({ align = "center", gap = 6 }, parts),
                })
            end
        end

        if err ~= nil then
            tooltip[#tooltip + 1] = { key = spec.title .. " Refresh", value = tostring(err) }
        end
    end

    if #segments == 0 then
        segments[1] = ui.label({ text = "AI —", fontSize = 11, color = "on_surface_variant" })
        tooltip[1] = { key = "AI Usage", value = "Waiting for usage refresh" }
    end

    barWidget.render(ui.row({ gap = 7, align = "center" }, segments))
    barWidget.setTooltip(tooltip)
end

local function refresh()
    noctalia.runAsync(CMD, function(result)
        local decoded = noctalia.json.decode((result and result.stdout) or "{}")
        state = type(decoded) == "table" and decoded or {}
        render()
    end, 5000)
end

function update()
    noctalia.setUpdateInterval(REFRESH_MS)
    refresh()
end

function onRightClick()
    noctalia.runAsync(REFRESH_CMD, function() refresh() end, 125000)
end
function onIpc(event, _payload) if event == "refresh" then onRightClick() end end

noctalia.setUpdateInterval(REFRESH_MS)
render()
refresh()

--!nonstrict
-- Reads pi-usage's cache (~/.cache/pi-usage/provider-*.json). Makes no network
-- requests and touches no credentials; data refreshes whenever Pi refreshes it.

local REFRESH_MS = 30000
local STALE_SEC = 3600
local CMD = "jq -c '.lastGood | {fetchedAt, usage}' ${XDG_CACHE_HOME:-$HOME/.cache}/pi-usage/provider-*.json 2>/dev/null"

local entries = {}

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
        resetAt and ("resets in " .. duration(resetAt - now)) or ""
end

local function render()
    local now = os.time()
    local segments, tooltip = {}, {}

    for i, entry in ipairs(entries) do
        local usage = entry.usage
        local fetched = (tonumber(entry.fetchedAt) or 0) / 1000
        local stale = now - fetched > STALE_SEC
        local parts = {}
        local lines = {}
        for _, window in ipairs(usage.windows or {}) do
            local pct, note = windowState(window, now)
            local label = shortLabel(window.label)
            if pct ~= nil then
                parts[#parts + 1] = ui.progress({ progress = pct / 100, fill = colorFor(pct),
                    track = "on_surface/0.16", radius = 6, width = 22, height = 5 })
                parts[#parts + 1] = ui.label({ text = string.format("%s %d%%", label, math.floor(pct + 0.5)),
                    fontSize = 11, fontWeight = "semibold", color = stale and "on_surface_variant" or "on_surface", maxLines = 1 })
                lines[#lines + 1] = string.format("%s: %d%% used, %s", window.label, math.floor(pct + 0.5), note)
            else
                parts[#parts + 1] = ui.label({ text = label .. " —", fontSize = 11, color = "on_surface_variant", maxLines = 1 })
                lines[#lines + 1] = string.format("%s: window reset since last Pi refresh", window.label)
            end
        end
        if stale then lines[#lines + 1] = "Cache is " .. duration(now - fetched) .. " old" end

        if i > 1 then segments[#segments + 1] = ui.box({ width = 1, height = 15, fill = "outline/0.35" }) end
        segments[#segments + 1] = ui.row({ key = "p" .. i, align = "center", gap = 5 }, {
            ui.glyph({ name = usage.provider == "anthropic" and "message-chatbot" or "brand-openai", size = 13, color = "primary" }),
            ui.row({ align = "center", gap = 6 }, parts),
        })
        tooltip[#tooltip + 1] = { key = usage.displayName or usage.provider or "Provider", value = table.concat(lines, "\n") }
    end

    if #segments == 0 then
        segments[1] = ui.label({ text = "Pi usage —", fontSize = 11, color = "on_surface_variant" })
        tooltip[1] = { key = "Pi Usage", value = "No pi-usage cache yet. Start Pi." }
    end

    barWidget.render(ui.row({ gap = 7, align = "center" }, segments))
    barWidget.setTooltip(tooltip)
end

local function refresh()
    noctalia.runAsync(CMD, function(result)
        local found = {}
        for line in string.gmatch((result and result.stdout) or "", "[^\n]+") do
            local decoded = noctalia.json.decode(line)
            if type(decoded) == "table" and type(decoded.usage) == "table" then
                found[#found + 1] = decoded
            end
        end
        entries = found
        render()
    end, 5000)
end

function update()
    noctalia.setUpdateInterval(REFRESH_MS)
    refresh()
end

function onRightClick() refresh() end
function onIpc(event, _payload) if event == "refresh" then refresh() end end

noctalia.setUpdateInterval(REFRESH_MS)
render()
refresh()

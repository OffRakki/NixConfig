--!nonstrict
local library = noctalia.state.get("library") or {}
local previews = noctalia.state.get("previews") or {}
local assignments = noctalia.state.get("assignments") or {}
local outputList = noctalia.state.get("outputs") or noctalia.outputs() or {}
local selected = "*"
local search = ""
local page = 1
local counter = 0
local cursor = 1
local opened = false
local PAGE_SIZE = 16
local render

local function send(command)
    counter = counter + 1
    command.nonce = noctalia.nowMs() * 1000 + counter
    command.output = selected
    noctalia.state.set("command", command)
end
local function filtered()
    local entries = {}
    for _, entry in ipairs(library) do
        if search == "" or entry.name:lower():find(search:lower(), 1, true) then table.insert(entries, entry) end
    end
    return entries
end
local function visiblePreviews()
    local entries = filtered()
    local paths = {}
    for index = (page - 1) * PAGE_SIZE + 1, math.min(page * PAGE_SIZE, #entries) do
        local entry = entries[index]
        if previews[entry.path] == nil then table.insert(paths, entry.path) end
    end
    if #paths > 0 then send({ action = "previews", paths = paths }) end
end
local function chooseCursor()
    local entry = filtered()[cursor]
    if entry and noctalia.state.get("ready") and not noctalia.state.get("busy") then
        send({ action = "apply", path = entry.path })
    end
end
local function turnPage(delta)
    local pages = math.max(1, math.ceil(#filtered() / PAGE_SIZE))
    page = math.clamp(page + delta, 1, pages)
    cursor = (page - 1) * PAGE_SIZE + 1
    render()
    visiblePreviews()
end
function onKey(chord, pressed)
    if not pressed or not opened then return end
    if chord == "Return" then chooseCursor(); return end
    local count = #filtered()
    if count == 0 then return end
    local steps = { Left = -1, Right = 1, Up = -4, Down = 4, Page_Up = -PAGE_SIZE, Page_Down = PAGE_SIZE }
    if chord == "Home" then cursor = 1
    elseif chord == "End" then cursor = count
    else cursor = math.clamp(cursor + (steps[chord] or 0), 1, count) end
    page = math.floor((cursor - 1) / PAGE_SIZE) + 1
    render()
    visiblePreviews()
end
function onChoose() chooseCursor() end
render = function()
    if not opened then return end
    local entries = filtered()
    local pages = math.max(1, math.ceil(#entries / PAGE_SIZE))
    page = math.clamp(page, 1, pages)
    cursor = math.clamp(cursor, 1, math.max(1, #entries))
    local busy = noctalia.state.get("busy") == true
    local ready = noctalia.state.get("ready") == true
    local options = { "All monitors" }
    local selectedIndex = 0
    for index, output in ipairs(outputList) do
        table.insert(options, output.name)
        if selected == output.name then selectedIndex = index end
    end
    local children = {
        ui.row({ align = "center", gap = 8 }, {
            ui.label({ text = "Motion Wallpapers", fontSize = 18, fontWeight = "bold", flexGrow = 1 }),
            ui.button({ glyph = "settings", variant = "ghost", onClick = function() noctalia.openSettings() end }),
            ui.button({ glyph = "close", variant = "ghost", onClick = function() panel.close() end }),
        }),
        ui.row({ gap = 8, align = "center" }, {
            ui.input({ key = "search", value = search, focus = true, placeholder = "Search images and videos…", flexGrow = 1, onChange = "onSearch", onSubmit = "onChoose" }),
            ui.select({ options = options, selectedIndex = selectedIndex, onChange = "onOutput" }),
            ui.button({ glyph = "refresh", variant = "ghost", enabled = ready and not busy, onClick = function() send({ action = "scan" }) end }),
        }),
        ui.row({ gap = 8 }, {
            ui.button({ text = "Pause", enabled = ready and not busy, onClick = function() send({ action = "pause" }) end }),
            ui.button({ text = "Resume", enabled = ready and not busy, onClick = function() send({ action = "resume" }) end }),
            ui.button({ text = "Restore static", enabled = ready and not busy, onClick = function() send({ action = "restore" }) end }),
            ui.label({ text = busy and "Applying…" or "Colors update when a wallpaper is selected", color = "on_surface_variant", fontSize = 11 }),
        }),
    }
    local message = noctalia.state.get("error")
    if message and message ~= "" then table.insert(children, ui.label({ text = message, color = "error", maxLines = 3 })) end
    local warnings = noctalia.state.get("warnings")
    if warnings and warnings ~= "" then table.insert(children, ui.label({ text = warnings, color = "on_surface_variant", maxLines = 2 })) end
    if not ready or noctalia.state.get("scanning") then
        table.insert(children, ui.label({ text = ready and "Scanning wallpaper folder…" or "Starting playback backend…" }))
    end
    local rows = {}
    local cards = {}
    for index = (page - 1) * PAGE_SIZE + 1, math.min(page * PAGE_SIZE, #entries) do
        local entry = entries[index]
        local image = previews[entry.path]
        local highlighted = index == cursor
        local active = false
        for output, assignment in pairs(assignments) do
            if (selected == "*" or selected == output) and assignment.path == entry.path then active = true end
        end
        local choose = nil
        if ready and not busy then choose = function() cursor = index; render(); send({ action = "apply", path = entry.path }) end end
        local tile
        if image then
            tile = ui.image({ path = image, height = 105, fit = "cover", onClick = choose, border = (highlighted or active) and "primary" or "outline/0.4", borderWidth = highlighted and 3 or (active and 2 or 1) })
        else
            tile = ui.button({ glyph = "player-play", text = previews[entry.path] == false and "Preview failed" or "Preparing preview…", border = highlighted and "primary" or "outline/0.4", borderWidth = highlighted and 3 or 1, height = 105, enabled = choose ~= nil, onClick = choose })
        end
        table.insert(cards, ui.column({ width = 210, gap = 4, key = entry.path }, {
            tile,
            ui.label({ text = (entry.kind == "video" and "Video · " or "") .. entry.name, fontSize = 11, maxLines = 1, color = (highlighted or active) and "primary" or "on_surface" }),
        }))
        if #cards == 4 or index == math.min(page * PAGE_SIZE, #entries) then
            table.insert(rows, ui.row({ gap = 10, align = "start" }, cards))
            cards = {}
        end
    end
    if #entries == 0 then table.insert(rows, ui.label({ text = "No matching wallpapers. Check the folder in plugin settings." })) end
    table.insert(children, ui.column({ flexGrow = 1, gap = 12 }, rows))
    table.insert(children, ui.row({ gap = 8, align = "center" }, {
        ui.label({ text = tostring(#entries) .. " wallpapers · Arrows to select · Enter to apply", flexGrow = 1, color = "on_surface_variant" }),
        ui.button({ glyph = "chevron-left", enabled = page > 1, onClick = function() turnPage(-1) end }),
        ui.label({ text = tostring(page) .. " / " .. tostring(pages) }),
        ui.button({ glyph = "chevron-right", enabled = page < pages, onClick = function() turnPage(1) end }),
    }))
    panel.render(ui.column({ padding = 16, gap = 12, flexGrow = 1 }, children))
end
function onSearch(value) search = tostring(value or ""); page = 1; cursor = 1; render(); visiblePreviews() end
function onOutput(value)
    local index = tonumber(value)
    if index == 0 then selected = "*"
    elseif index and outputList[index] then selected = outputList[index].name end
    render()
end
function onClose() opened = false end
function onOpen()
    opened = true
    library = noctalia.state.get("library") or {}
    previews = noctalia.state.get("previews") or {}
    assignments = noctalia.state.get("assignments") or {}
    outputList = noctalia.state.get("outputs") or noctalia.outputs() or {}
    render()
    visiblePreviews()
end
noctalia.state.watch("library", function(value) library = value or {}; page = 1; cursor = 1; render(); if opened then visiblePreviews() end end)
noctalia.state.watch("previews", function(value) previews = value or {}; render() end)
noctalia.state.watch("assignments", function(value) assignments = value or {}; render() end)
noctalia.state.watch("outputs", function(value)
    outputList = value or {}
    local found = selected == "*"
    for _, output in ipairs(outputList) do if output.name == selected then found = true end end
    if not found then selected = "*" end
    render()
end)
for _, key in ipairs({ "error", "warnings", "busy", "ready", "scanning" }) do noctalia.state.watch(key, function() render() end) end

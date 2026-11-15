--!nonstrict
-- Replaced by Nix with the closure-complete executable.
local BACKEND = "@motionwall@"
local data = noctalia.pluginDataDir()
local playback = nil
local connected = {}
local queue = {}
local running, ready, exiting, busy = false, false, false, false
local everReady = false
local previews, previewPending = {}, {}
local scanGeneration, lastNonce = 0, 0
local started = noctalia.nowMs()
local lastHealth = started
local lastRoot = nil
local retries, retryAt = 0, nil
local pump

local function report(message)
    noctalia.state.set("error", tostring(message))
    noctalia.log("Motion Wallpapers: " .. tostring(message))
end
local function outputs()
    local list = noctalia.outputs() or {}
    noctalia.state.set("outputs", list)
    return list
end
local function publish()
    local assignments = {}
    if playback then
        for output in pairs(connected) do assignments[output] = { path = playback.path, preview = playback.preview } end
    end
    noctalia.state.set("assignments", assignments)
    noctalia.state.set("busy", busy)
end
local function save()
    local text = noctalia.json.encode({ version = 2, playback = playback or false })
    if not text or not noctalia.writeFile(data .. "/playback.tmp", text)
        or not noctalia.renameFile(data .. "/playback.tmp", data .. "/playback.json") then report("Could not persist shared wallpaper") end
end
local function enqueue(request, callback, background)
    local item = { request = request, callback = callback }
    if background then table.insert(queue, item) else table.insert(queue, 1, item) end
    pump()
end
pump = function()
    if running or not ready or exiting or #queue == 0 then return end
    local item = table.remove(queue, 1)
    running = true
    local launched = noctalia.runAsync({ BACKEND, "request", noctalia.json.encode(item.request) }, function(result)
        running = false
        if exiting then return end
        local value = noctalia.json.decode(result.stdout or "")
        if result.stdoutTruncated or result.timedOut or type(value) ~= "table" then
            value = { ok = false, error = "Backend request failed or timed out: " .. tostring(result.stderr or "") }
        end
        if value.policy then noctalia.state.set("policy", value.policy) end
        if item.callback then item.callback(value) end
        pump()
    end, 50000)
    if not launched then
        running = false
        if item.callback then item.callback({ ok = false, error = "Could not launch Motion Wallpapers backend" }) end
        pump()
    end
end
local function queuePreviews(paths)
    for _, path in ipairs(paths) do
        if type(path) == "string" and previews[path] == nil and not previewPending[path] then
            previewPending[path] = true
            enqueue({ action = "preview", path = path, thumbnail = true }, function(result)
                previewPending[path] = nil
                previews[path] = result.ok and result.preview or false
                if not result.ok then report(result.error) end
                noctalia.state.set("previews", previews)
            end, true)
        end
    end
end
local function scan(onlyIfChanged)
    local root = noctalia.getConfig("directory")
    if not root or root == "" then root = noctalia.wallpaperDirectory() end
    if not root or root == "" then report("Choose a wallpaper folder in plugin settings"); return end
    root = noctalia.expandPath(root)
    if onlyIfChanged and root == lastRoot then return end
    lastRoot = root
    scanGeneration = scanGeneration + 1
    local generation = scanGeneration
    noctalia.state.set("scanning", true)
    enqueue({ action = "scan", root = root }, function(result)
        if generation ~= scanGeneration then return end
        noctalia.state.set("scanning", false)
        if not result.ok then report(result.error); return end
        previews = {}
        noctalia.state.set("previews", previews)
        noctalia.state.set("library", result.entries or {})
        noctalia.state.set("warnings", table.concat(result.warnings or {}, "\n"))
        local paths = {}
        for index, entry in ipairs(result.entries or {}) do
            if index > 16 then break end
            table.insert(paths, entry.path)
        end
        queuePreviews(paths)
    end, true)
end
local function fallback()
    for output in pairs(connected) do noctalia.setWallpaperEnabled(output, true) end
end
local function apply(path, done)
    local originals = playback and playback.originals or {}
    for output in pairs(connected) do
        if not originals[output] then originals[output] = noctalia.wallpaperPath(output) end
    end
    enqueue({ action = "play", output = "*", path = path, scale = noctalia.getConfig("scale") or "fill", fps = tonumber(noctalia.getConfig("fps")) or 30 }, function(result)
        if result.ok then
            for output in pairs(connected) do
                noctalia.setWallpaper(output, result.preview)
                noctalia.setWallpaperEnabled(output, result.kind ~= "video")
            end
            playback = result.kind == "video" and { path = result.path, preview = result.preview, originals = originals } or nil
            save()
            if noctalia.getSetting("theme.source") ~= "wallpaper" then report("Wallpaper applied; set Noctalia's theme source to Wallpaper for matching colors.") end
        else
            fallback()
            report(result.error or "Shared wallpaper failed")
        end
        publish()
        if done then done() end
    end)
end
local function reconcile()
    local fresh = {}
    for _, output in ipairs(outputs()) do
        fresh[output.name] = true
        if not connected[output.name] and playback then
            if not playback.originals[output.name] then playback.originals[output.name] = noctalia.wallpaperPath(output.name) end
            if playback.preview and noctalia.fileExists(playback.preview) then noctalia.setWallpaper(output.name, playback.preview) end
            noctalia.setWallpaperEnabled(output.name, false)
        end
    end
    -- gSlapper adds/removes surfaces itself; never restart the common timeline on hotplug.
    connected = fresh
    publish()
end
local function configure()
    enqueue({ action = "configure", auto_pause = noctalia.getConfig("auto_pause") ~= false }, function(result)
        if not result.ok then report(result.error) end
    end)
end
local function handle(command)
    if type(command) ~= "table" or type(command.nonce) ~= "number" or command.nonce <= lastNonce then return end
    lastNonce = command.nonce
    if command.action == "scan" then scan(); return end
    if command.action == "previews" then queuePreviews(command.paths or {}); return end
    if busy or not ready then return end
    -- Reject old per-output commands instead of silently changing their meaning.
    if command.output ~= nil and command.output ~= "*" then report("Playback and controls are shared across all monitors"); return end
    if command.action ~= "apply" and command.action ~= "restore" and command.action ~= "pause" and command.action ~= "resume" then return end
    if command.action == "apply" and type(command.path) ~= "string" then return end
    busy = true
    retryAt = nil
    noctalia.state.set("error", "")
    publish()
    local function done() busy = false; publish() end
    if command.action == "apply" then retries = 0; apply(command.path, done)
    else
        enqueue({ action = "control", output = "*", command = command.action == "restore" and "stop" or command.action }, function(result)
            if not result.ok then report(result.error)
            elseif command.action == "restore" then
                for output in pairs(connected) do
                    local original = playback and playback.originals[output]
                    if original and noctalia.fileExists(original) then noctalia.setWallpaper(output, original) end
                end
                fallback()
                playback = nil
                save()
            end
            done()
        end)
    end
end
function onOutputsChanged() if ready then reconcile(); if playback then save() end end end
function onConfigChanged() if ready then configure(); scan(true) end end
function onIpc(event, payload) if event == "command" then handle(noctalia.json.decode(payload or "")) end end
function onExit()
    exiting = true
    fallback()
    -- Host kills the runStream process group. Never send shutdown to a replacement runtime.
end
function update()
    if ready and retryAt and noctalia.nowMs() >= retryAt and not busy then
        retryAt = nil
        if playback then busy = true; publish(); apply(playback.path, function() busy = false; publish() end) end
    end
    if ready and not running and #queue == 0 and noctalia.nowMs() - lastHealth > 15000 then
        lastHealth = noctalia.nowMs()
        enqueue({ action = "status" }, function(result)
            if result.ok then return end
            ready, busy = false, false
            noctalia.state.set("ready", false)
            fallback(); publish()
            report("Backend stopped; disable and re-enable Motion Wallpapers. " .. tostring(result.error))
        end, true)
    end
    if not ready and not everReady and noctalia.nowMs() - started > 5000 then
        report("Backend did not start; inspect Noctalia's log")
        noctalia.setUpdateInterval(60000)
    end
end

if not data then report("No plugin data directory"); return end
local raw = noctalia.readFile(data .. "/playback.json")
if raw then
    local parsed = noctalia.json.decode(raw)
    if type(parsed) == "table" and parsed.version == 2 and type(parsed.playback) == "table"
        and type(parsed.playback.path) == "string" and type(parsed.playback.originals) == "table" then playback = parsed.playback end
else
    -- Non-destructive migration. Prefer DP-1, otherwise deterministic connector order.
    -- Keep the old assignments.json untouched for rollback to the two-player implementation.
    local old = noctalia.json.decode(noctalia.readFile(data .. "/assignments.json") or "")
    if type(old) == "table" then
        local names, originals = {}, {}
        for name, value in pairs(old) do
            if type(name) == "string" and type(value) == "table" and type(value.path) == "string" then
                table.insert(names, name); originals[name] = value.original
            end
        end
        table.sort(names)
        local selected = old["DP-1"] or old[names[1]]
        if type(selected) == "table" and type(selected.path) == "string" then
            playback = { path = selected.path, preview = selected.preview, originals = originals }
        end
    end
end
noctalia.state.watch("command", handle)
noctalia.setUpdateInterval(1000)
publish()
local function shellQuote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local launched = noctalia.runStream("exec " .. shellQuote(BACKEND) .. " serve " .. shellQuote(data), function(line)
    if exiting then return end
    local event = noctalia.json.decode(line)
    if type(event) ~= "table" then return end
    if event.event == "ready" then
        everReady, ready = true, true
        noctalia.state.set("ready", true)
        configure()
        reconcile()
        if playback then apply(playback.path) end
        scan()
        pump()
    elseif event.event == "policy" then noctalia.state.set("policy", event.policy)
    elseif event.event == "stopped" then
        fallback()
        report(event.error)
        if playback and retries < 1 then retries = retries + 1; retryAt = noctalia.nowMs() + 3000 end
    elseif event.error then report(event.error) end
end)
if not launched then report("Could not start Motion Wallpapers") end

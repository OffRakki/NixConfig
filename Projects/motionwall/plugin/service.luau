--!nonstrict
-- This token is replaced by Nix with the wrapped, closure-complete executable.
local BACKEND = "@motionwall@"
local data = noctalia.pluginDataDir()
local assignments = {}
local connected = {}
local queue = {}
local running = false
local ready = false
local everReady = false
local exiting = false
local busy = false
local previews = {}
local previewPending = {}
local scanGeneration = 0
local lastNonce = 0
local started = noctalia.nowMs()
local lastHealth = started
local lastRoot = nil
local pump

local function report(message)
    noctalia.state.set("error", tostring(message))
    noctalia.log("Motion Wallpapers: " .. tostring(message))
end
local function publish()
    noctalia.state.set("assignments", assignments)
    noctalia.state.set("busy", busy)
end
local function save()
    local text = noctalia.json.encode(assignments)
    if not text or not noctalia.writeFile(data .. "/assignments.tmp", text)
        or not noctalia.renameFile(data .. "/assignments.tmp", data .. "/assignments.json") then
        report("Could not persist wallpaper assignments")
    end
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
local function outputs()
    local list = noctalia.outputs() or {}
    noctalia.state.set("outputs", list)
    return list
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
        -- Warm the first page before opening; decoding stays outside Noctalia's UI thread.
        local paths = {}
        for index, entry in ipairs(result.entries or {}) do
            if index > 16 then break end
            table.insert(paths, entry.path)
        end
        queuePreviews(paths)
    end, true)
end
local function apply(output, path, done)
    local original = assignments[output] and assignments[output].original or noctalia.wallpaperPath(output)
    enqueue({ action = "play", output = output, path = path, scale = noctalia.getConfig("scale") or "fill", fps = tonumber(noctalia.getConfig("fps")) or 30 }, function(result)
        if result.ok and connected[output] then
            -- Applying a real, validated JPEG updates Noctalia's palette and templates,
            -- even while its wallpaper surface is externally managed.
            noctalia.setWallpaper(output, result.preview)
            noctalia.setWallpaperEnabled(output, result.kind ~= "video")
            if result.kind == "video" then
                assignments[output] = { path = result.path, preview = result.preview, original = original }
            else
                assignments[output] = nil
            end
            save()
            if noctalia.getSetting("theme.source") ~= "wallpaper" then
                report("Wallpaper applied; set Noctalia's theme source to Wallpaper for matching colors.")
            end
        elseif result.ok then
            enqueue({ action = "control", output = output, command = "stop" }, nil)
        else
            -- A failed replacement may have stopped the old renderer; show its still.
            noctalia.setWallpaperEnabled(output, true)
            report(result.error or "Wallpaper failed")
        end
        publish()
        if done then done() end
    end)
end
local function restore(output, done)
    enqueue({ action = "control", output = output, command = "stop" }, function(result)
        if result.ok then
            local previous = assignments[output] and assignments[output].original
            if connected[output] then
                if previous and noctalia.fileExists(previous) then noctalia.setWallpaper(output, previous) end
                noctalia.setWallpaperEnabled(output, true)
            end
            assignments[output] = nil
            save()
        else report(result.error) end
        publish()
        if done then done() end
    end)
end
local function reconcile()
    local fresh = {}
    for _, output in ipairs(outputs()) do fresh[output.name] = true end
    for output in pairs(connected) do
        if not fresh[output] then enqueue({ action = "control", output = output, command = "stop" }, nil) end
    end
    for output in pairs(fresh) do
        if not connected[output] and assignments[output] then apply(output, assignments[output].path) end
    end
    connected = fresh
end
local function handle(command)
    if type(command) ~= "table" or type(command.nonce) ~= "number" or command.nonce <= lastNonce then return end
    lastNonce = command.nonce
    if command.action == "scan" then scan(); return end
    if command.action == "previews" then
        queuePreviews(command.paths or {})
        return
    end
    if busy or not ready then return end
    local targets = {}
    for _, output in ipairs(outputs()) do
        if command.output == "*" or command.output == output.name then table.insert(targets, output.name) end
    end
    if #targets == 0 then return end
    if command.action ~= "apply" and command.action ~= "restore" and command.action ~= "pause" and command.action ~= "resume" then return end
    if command.action == "apply" and type(command.path) ~= "string" then return end
    busy = true
    noctalia.state.set("error", "")
    publish()
    local remaining = #targets
    local function done()
        remaining = remaining - 1
        if remaining == 0 then busy = false; publish() end
    end
    for _, output in ipairs(targets) do
        if command.action == "apply" then apply(output, command.path, done)
        elseif command.action == "restore" then restore(output, done)
        else
            enqueue({ action = "control", output = output, command = command.action }, function(result)
                if not result.ok then report(result.error) end
                done()
            end)
        end
    end
end
function onOutputsChanged() if ready then reconcile() end end
function onConfigChanged() if ready then scan(true) end end
function onIpc(event, payload)
    if event == "command" then
        local value = noctalia.json.decode(payload or "")
        handle(value)
    end
end
function onExit()
    exiting = true
    for output in pairs(connected) do noctalia.setWallpaperEnabled(output, true) end
    -- Noctalia terminates the runStream process group, including all owned renderers.
    -- Do not launch an asynchronous shutdown request: it could hit the next runtime.
end
function update()
    if ready and not running and #queue == 0 and noctalia.nowMs() - lastHealth > 15000 then
        lastHealth = noctalia.nowMs()
        enqueue({ action = "status" }, function(result)
            if result.ok then return end
            ready = false
            busy = false
            noctalia.state.set("ready", false)
            for output in pairs(connected) do noctalia.setWallpaperEnabled(output, true) end
            publish()
            report("Backend stopped; disable and re-enable Motion Wallpapers. " .. tostring(result.error))
        end, true)
    end
    if not ready and not everReady and noctalia.nowMs() - started > 5000 then
        report("Backend did not start; inspect Noctalia's log")
        noctalia.setUpdateInterval(60000)
    end
end

if not data then report("No plugin data directory"); return end
local raw = noctalia.readFile(data .. "/assignments.json")
if raw then
    local parsed = noctalia.json.decode(raw)
    if type(parsed) == "table" then
        for output, value in pairs(parsed) do
            if type(output) == "string" and type(value) == "table" and type(value.path) == "string" then assignments[output] = value end
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
        everReady = true
        ready = true
        noctalia.state.set("ready", true)
        reconcile()
        scan()
        pump()
    elseif event.event == "stopped" then
        if connected[event.output] then noctalia.setWallpaperEnabled(event.output, true) end
        report(event.error)
    elseif event.error then report(event.error) end
end)
if not launched then report("Could not start Motion Wallpapers") end

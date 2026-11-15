-- Mock the native runtime; exercise the actual service, including legacy migration.
local state, files, packets = {}, {}, {}
local requests, wallpaperCalls, enabled = {}, {}, {}
local configs = { auto_pause = false }
local serial, nonce, clock = 0, 0, 100
local streamCallback
local outputList = { { name = "DP-1" }, { name = "HDMI-A-1" } }
local function encode(value) serial += 1; local key = "json" .. serial; packets[key] = value; return key end
local function decode(value) return packets[value] end
files["/data/assignments.json"] = encode({
    ["DP-1"] = { path = "/primary.mp4", original = "/primary.png", preview = "/old.jpg" },
    ["HDMI-A-1"] = { path = "/secondary.mp4", original = "/secondary.png", preview = "/old2.jpg" },
})
local oldFile = files["/data/assignments.json"]
noctalia = {
    json = { encode = encode, decode = decode },
    state = { get = function(k) return state[k] end, set = function(k,v) state[k] = v end, watch = function() end },
    pluginDataDir = function() return "/data" end,
    nowMs = function() return clock end,
    readFile = function(p) return files[p] end,
    writeFile = function(p,v) files[p] = v; return true end,
    renameFile = function(a,b) files[b] = files[a]; files[a] = nil; return true end,
    getConfig = function(k) return configs[k] end,
    getSetting = function() return "wallpaper" end,
    wallpaperDirectory = function() return "/wallpapers" end,
    expandPath = function(p) return p end,
    wallpaperPath = function(name) return name == "DP-1" and "/primary.png" or "/secondary.png" end,
    fileExists = function() return true end,
    outputs = function() return outputList end,
    log = function() end, setUpdateInterval = function() end,
    setWallpaper = function(output,path) table.insert(wallpaperCalls,{output=output,path=path}) end,
    setWallpaperEnabled = function(output,value) enabled[output] = value end,
    runStream = function(_,callback) streamCallback=callback; return true end,
    runAsync = function(argv,callback)
        local request=decode(argv[3]); table.insert(requests,request)
        local result={ok=true}
        if request.action == "scan" then result.entries={}; result.warnings={}
        elseif request.action == "play" then result.path=request.path; result.preview="/preview.jpg"; result.kind="video"
        elseif request.action == "status" then result.playback={path="/primary.mp4"} end
        callback({stdout=encode(result)})
        return true
    end,
}

local function reload()
-- @service@
end
reload()

streamCallback(encode({event="ready"}))
assert(requests[1].action=="configure" and requests[1].auto_pause==false,"opt-out must reach Rust before playback")
local plays=0
for _,request in ipairs(requests) do
    if request.action=="play" then plays+=1; assert(request.output=="*" and request.path=="/primary.mp4") end
end
assert(plays==1,"migration must start only one shared renderer request")
assert(state.assignments["DP-1"].path==state.assignments["HDMI-A-1"].path)
assert(enabled["DP-1"]==false and enabled["HDMI-A-1"]==false)
assert(files["/data/assignments.json"]==oldFile,"legacy assignments must remain intact for rollback")
local calls=#wallpaperCalls
streamCallback(encode({event="policy",policy={reason="Paused: fullscreen on DP-1"}}))
assert(state.policy.reason=="Paused: fullscreen on DP-1")
local function command(action,output,path)
    nonce+=1; onIpc("command",encode({nonce=nonce,action=action,output=output,path=path}))
end
command("pause","*"); command("resume","*")
assert(#wallpaperCalls==calls,"pause and resume must never trigger palette/wallpaper writes")
local count=#requests
command("pause","HDMI-A-1")
assert(#requests==count,"old per-monitor controls must not silently become global")
outputList={{name="DP-1"},{name="HDMI-A-1"},{name="DP-3"}}
onOutputsChanged()
assert(#requests==count,"hotplug must not restart the common timeline")
command("restore","*")
assert(state.assignments["DP-1"]==nil and enabled["DP-1"]==true and enabled["HDMI-A-1"]==true)
assert(decode(files["/data/playback.json"]).playback==false,"static restoration must persist without re-migrating old assignments")
onExit(); requests={}; reload(); streamCallback(encode({event="ready"}))
for _,request in ipairs(requests) do assert(request.action~="play","persisted static restoration must not resurrect legacy videos") end
command("apply","*","/new-shared.mp4")
assert(state.assignments["DP-1"].path=="/new-shared.mp4")
onExit(); requests={}; reload(); streamCallback(encode({event="ready"}))
local restored=0
for _,request in ipairs(requests) do
    if request.action=="play" then restored+=1; assert(request.path=="/new-shared.mp4") end
end
assert(restored==1,"reload must recover one persisted shared selection")
local beforeRetry=#requests
streamCallback(encode({event="stopped",error="renderer failed"})); clock=5000; update()
assert(#requests==beforeRetry+1 and requests[#requests].action=="play","first crash should retry the shared selection once")
local afterRetry=#requests
streamCallback(encode({event="stopped",error="renderer failed again"})); clock=10000; update()
for index=afterRetry+1,#requests do assert(requests[index].action~="play","automatic crash recovery must be bounded") end
assert(files["/data/assignments.json"]==oldFile)
print("Shared service migration, controls, pause colors, opt-out, hotplug, reload, bounded recovery and restoration passed")

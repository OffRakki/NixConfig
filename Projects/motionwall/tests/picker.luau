-- Native Luau regression harness; the package inserts the actual picker at the marker.
local state = { ready = true, busy = false, library = {}, outputs = {} }
for index = 1, 30 do
    state.library[index] = { name = "wall" .. index, path = "/wall" .. index .. ".png", kind = "image" }
end
local watchers = {}
local renders = 0
local tree
noctalia = {
    state = {
        get = function(key) return state[key] end,
        set = function(key, value) state[key] = value end,
        watch = function(key, callback) watchers[key] = callback end,
    },
    nowMs = function() return 100 end,
    outputs = function() return {} end,
}
ui = setmetatable({}, { __index = function(_, kind)
    return function(props, children) return { kind = kind, props = props, children = children } end
end })
panel = { render = function(value) tree = value; renders += 1 end }

-- @panel@

assert(renders == 0, "closed picker must not build image trees")
onOpen()
assert(tree.children[2].children[1].props.focus == true, "search must take initial control focus")
local grid = tree.children[4]
assert(grid.kind == "column" and #grid.children == 4, "picker must show four rows")
for _, row in ipairs(grid.children) do
    assert(#row.children == 4, "each row must contain four wallpapers")
end
onKey("Right", false)
onKey("Right", true)
onKey("Return", true)
assert(state.command.path == "/wall2.png")
onKey("Down", true)
onKey("Return", true)
assert(state.command.path == "/wall6.png")
onKey("End", true)
onKey("Right", true)
onKey("Return", true)
assert(state.command.path == "/wall30.png", "selection must cross pages and clamp at the end")
onKey("Home", true)
onKey("Up", true)
onKey("Return", true)
assert(state.command.path == "/wall1.png")
onKey("Page_Down", true)
onKey("Return", true)
assert(state.command.path == "/wall17.png")
onSearch("wall30")
onChoose()
assert(state.command.path == "/wall30.png", "search resets selection before Enter")
state.busy = true
state.command = nil
onChoose()
assert(state.command == nil, "busy state must not apply a wallpaper twice")
onClose()
local previousRenders = renders
watchers.previews({})
onKey("Right", true)
assert(renders == previousRenders, "background preview updates must not rebuild a closed picker")
print("Picker focus, arrows, paging, search, busy state and closed-render guards passed")

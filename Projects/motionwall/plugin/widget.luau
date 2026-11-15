--!nonstrict
barWidget.setGlyph("wallpaper-selector")
barWidget.setTooltip("Motion Wallpapers")
function onClick()
    noctalia.togglePanel("local/motionwall:picker")
end

# dmgbuild settings for the Longo Flow installer window. build-app.sh passes these defines:
#   app        path to the built .app
#   background path to the Retina background (.tiff made from Support/dmg/background*.png)
#   volume_icon path to the volume icon (.icns)
# Icon positions match the wells drawn in scripts/dmg/background.html.

app = defines["app"]

format = "UDZO"
filesystem = "HFS+"

# Installed as "Longo Flow.app", the name people see in Applications and Launchpad.
files = [(app, "Longo Flow.app")]
symlinks = {"Applications": "/Applications"}
icon_locations = {
    "Longo Flow.app": (170, 190),
    "Applications": (490, 190),
}

background = defines["background"]
icon = defines["volume_icon"]

# The background is 660×484 pt; the extra height over the 400 pt design covers Finder's title, tab, path and
# status bars, so nothing is hidden whichever bars the viewer has turned on.
window_rect = ((200, 120), (660, 540))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
icon_size = 112
text_size = 13
arrange_by = None

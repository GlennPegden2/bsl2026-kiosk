#!/bin/bash
# Minimal X session for the kiosk slideshow.
# Called by startx: sets display preferences then launches the Python app.

# Disable screen saver, DPMS power-off and display blanking
xset s off
xset -dpms
xset s noblank

# Hide the mouse cursor after 1 second of inactivity
unclutter -idle 1 -root &

# Launch the slideshow (exec replaces this shell process)
exec python3 /usr/local/bin/slideshow.py

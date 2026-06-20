import subprocess
import time

def wdotool(args):
    subprocess.run(['wdotool'] + args)

# Move to center of screen
wdotool(['mousemove', '960', '540'])
time.sleep(0.1)
wdotool(['mousedown', '1'])
time.sleep(0.1)
wdotool(['mousemove', '960', '200']) # Drag UP
time.sleep(0.1)
wdotool(['mouseup', '1'])
time.sleep(0.5)
subprocess.run(['grim', '/home/btw/test/earth/screenshot_drag_up.png'])

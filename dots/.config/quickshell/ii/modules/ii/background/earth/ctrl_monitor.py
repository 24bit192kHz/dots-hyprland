#!/usr/bin/env python3
"""Monitor Ctrl key state via Linux evdev and print 1/0 to stdout."""
import struct, sys, os, glob, select

EVENT_SIZE = struct.calcsize('llHHi')
EV_KEY = 0x01
KEY_LEFTCTRL = 29
KEY_RIGHTCTRL = 97

# Find the FIRST real keyboard device only
kbd_path = None
for path in sorted(glob.glob('/dev/input/by-path/*-event-kbd')):
    # Skip secondary interfaces (e.g. :1.2 media keys) — only use :1.0
    if ':1.0-event-kbd' in path or ':1.1-event-kbd' in path:
        kbd_path = path
        break

if not kbd_path:
    # Fallback: first match
    paths = sorted(glob.glob('/dev/input/by-path/*-event-kbd'))
    if paths:
        kbd_path = paths[0]

if not kbd_path:
    print("no-access", flush=True)
    sys.exit(1)

try:
    kbd = open(kbd_path, 'rb')
except PermissionError:
    print("no-access", flush=True)
    sys.exit(1)

print("0", flush=True)  # initial state: Ctrl not held

ctrl_left = False
ctrl_right = False
last_state = 0

while True:
    data = kbd.read(EVENT_SIZE)
    if len(data) < EVENT_SIZE:
        continue
    _, _, etype, code, value = struct.unpack('llHHi', data)
    if etype != EV_KEY:
        continue
    
    if code == KEY_LEFTCTRL:
        ctrl_left = value > 0
    elif code == KEY_RIGHTCTRL:
        ctrl_right = value > 0
    else:
        continue
        
    new_state = 1 if (ctrl_left or ctrl_right) else 0
    if new_state != last_state:
        last_state = new_state
        print(new_state, flush=True)

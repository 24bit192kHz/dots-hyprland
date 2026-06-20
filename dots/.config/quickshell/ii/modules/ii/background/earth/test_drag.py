import re

with open('/home/btw/test/earth/Earth.qml', 'r') as f:
    content = f.read()
    
drag_block = re.search(r'onPositionChanged.*?\}', content, re.DOTALL)
if drag_block:
    print(drag_block.group(0))

import requests
from PIL import Image, ImageChops
import numpy as np
import time
import os
import io

SATELLITES = [
    "G19-ABI-FD-BAND13",       # GOES East
    "G18-ABI-FD-BAND13",       # GOES West
    "Met11-SEVIRI-FD-BAND09",  # Meteosat 11 (Europe/Africa)
    "HIMAWARI-B13"             # Himawari (Asia/Australia)
]

ZOOM = 3
TILE_SIZE = 256
COLS = 8
ROWS = 4
CANVAS_WIDTH = COLS * TILE_SIZE
CANVAS_HEIGHT = ROWS * TILE_SIZE

OUTPUT_FILE = "local_clouds.png"
TMP_OUTPUT_FILE = "local_clouds_tmp.png"

def fetch_and_stitch():
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Starting global cloud fetch...")
    
    # Initialize a completely black canvas (grayscale mode L)
    master_canvas = Image.new("L", (CANVAS_WIDTH, CANVAS_HEIGHT), 0)
    
    with requests.Session() as session:
        for sat in SATELLITES:
            print(f"Fetching {sat}...")
            sat_canvas = Image.new("L", (CANVAS_WIDTH, CANVAS_HEIGHT), 0)
            
            for y in range(ROWS):
                for x in range(COLS):
                    url = f"https://realearth.ssec.wisc.edu/tiles/{sat}/{ZOOM}/{x}/{y}.png"
                    try:
                        resp = session.get(url, timeout=10)
                        if resp.status_code == 200:
                            try:
                                tile = Image.open(io.BytesIO(resp.content)).convert("L")
                                # Convert to numpy array to apply contrast threshold
                                arr = np.array(tile).astype(float)
                                # Subtract the dark grey surface background (~80) and stretch to 255
                                # This removes the hard edges of the satellite disks
                                arr = np.clip((arr - 80) * (255.0 / (255 - 80)), 0, 255).astype(np.uint8)
                                tile = Image.fromarray(arr, "L")
                                sat_canvas.paste(tile, (x * TILE_SIZE, y * TILE_SIZE))
                            except Exception as e:
                                print(f"  Error opening tile {x},{y}: {e}")
                    except Exception as e:
                        print(f"  Network error fetching {url}: {e}")
            
            # Composite the satellite canvas onto the master canvas
            # We use ImageChops.lighter to take the maximum pixel value across all satellites,
            # which naturally blends the bright clouds and ignores the dark/empty space.
            master_canvas = ImageChops.lighter(master_canvas, sat_canvas)
    
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Saving composite to {TMP_OUTPUT_FILE}...")
    master_canvas.save(TMP_OUTPUT_FILE, "PNG")
    os.rename(TMP_OUTPUT_FILE, OUTPUT_FILE)
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Stitch complete.")

if __name__ == "__main__":
    import sys
    if "--once" in sys.argv:
        fetch_and_stitch()
    else:
        while True:
            try:
                fetch_and_stitch()
            except Exception as e:
                print(f"Critical error during stitch: {e}")
            
            print("Sleeping for 15 minutes...")
            time.sleep(15 * 60)

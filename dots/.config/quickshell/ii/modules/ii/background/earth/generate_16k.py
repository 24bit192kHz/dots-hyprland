import os
from PIL import Image
import sys
import time

# To prevent decompression bomb errors on the 16K image
Image.MAX_IMAGE_PIXELS = None

OUTPUT_WIDTH = 16384
OUTPUT_HEIGHT = 8192

# Level 7 has 160 columns, 80 rows
# 5x5 native tiles = one 512x512 block in the 16K image
cols = 32
rows = 16

out_image = Image.new('RGB', (OUTPUT_WIDTH, OUTPUT_HEIGHT), (0, 0, 0))

start_time = time.time()
print(f"Generating {OUTPUT_WIDTH}x{OUTPUT_HEIGHT} 16K Texture...")

for row in range(rows):
    for col in range(cols):
        # We process a 5x5 chunk of native tiles
        chunk_img = Image.new('RGB', (2560, 2560), (0, 0, 0))
        
        for dy in range(5):
            for dx in range(5):
                native_x = col * 5 + dx
                native_y = row * 5 + dy
                path = f"tiles/7/{native_x}/{native_y}.jpeg"
                if os.path.exists(path):
                    try:
                        tile = Image.open(path).convert('RGB')
                        chunk_img.paste(tile, (dx * 512, dy * 512))
                    except Exception as e:
                        pass
        
        # Scale the 2560x2560 chunk down to 512x512
        scaled_chunk = chunk_img.resize((512, 512), resample=Image.Resampling.LANCZOS)
        
        # Paste into the master 16K image
        out_image.paste(scaled_chunk, (col * 512, row * 512))
        
        sys.stdout.write(f"\rProcessed block {row * cols + col + 1}/{rows * cols}")
        sys.stdout.flush()

print("\nSaving 16K image to disk (this might take a moment)...")
out_image.save("earth_16k.jpg", "JPEG", quality=92, subsampling=1)

elapsed = time.time() - start_time
print(f"Done! Created earth_16k.jpg in {elapsed:.1f} seconds.")

import os
import urllib.request
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE_URL = "https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/BlueMarble_ShadedRelief_Bathymetry/default/500m/{z}/{y}/{x}.jpeg"

LEVELS = [
    (0, 2, 1),
    (1, 3, 2),
    (2, 5, 3),
    (3, 10, 5),
    (4, 20, 10),
    (5, 40, 20),
    (6, 80, 40),
    (7, 160, 80)
]

def download_tile(z, x, y):
    path = f"tiles/{z}/{x}/{y}.jpeg"
    if os.path.exists(path):
        return True, path # Already downloaded

    url = BASE_URL.format(z=z, x=x, y=y)
    
    # Ensure directory exists
    os.makedirs(os.path.dirname(path), exist_ok=True)
    
    retries = 3
    while retries > 0:
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Offline Earth Map Downloader)'})
            with urllib.request.urlopen(req, timeout=10) as response:
                with open(path, 'wb') as f:
                    f.write(response.read())
            return True, path
        except Exception as e:
            retries -= 1
            time.sleep(1)
            
    return False, path

def main():
    print("Generating tile list...")
    tasks = []
    for z, cols, rows in LEVELS:
        for x in range(cols):
            for y in range(rows):
                tasks.append((z, x, y))
                
    total = len(tasks)
    print(f"Total tiles to download: {total}")
    
    completed = 0
    failed = 0
    
    start_time = time.time()
    
    with ThreadPoolExecutor(max_workers=20) as executor:
        futures = {executor.submit(download_tile, z, x, y): (z, x, y) for z, x, y in tasks}
        
        for future in as_completed(futures):
            success, path = future.result()
            completed += 1
            if not success:
                failed += 1
            
            if completed % 100 == 0 or completed == total:
                elapsed = time.time() - start_time
                rate = completed / elapsed
                remaining = (total - completed) / rate if rate > 0 else 0
                print(f"Progress: {completed}/{total} ({(completed/total)*100:.1f}%) - Failed: {failed} - Rate: {rate:.1f} tiles/s - ETA: {remaining:.1f}s")

    print(f"Download finished! Failed tiles: {failed}")

if __name__ == "__main__":
    main()

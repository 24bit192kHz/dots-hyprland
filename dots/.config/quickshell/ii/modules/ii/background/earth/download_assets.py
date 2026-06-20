import os
import urllib.request

# Define required assets and their known public URLs (e.g. Solar System Scope or NASA)
ASSETS = {
    "earth_8k_opt.jpg": "https://www.solarsystemscope.com/textures/download/8k_earth_daymap.jpg",
    "night_8k.jpg": "https://www.solarsystemscope.com/textures/download/8k_earth_nightmap.jpg",
    "clouds_4k.jpg": "https://www.solarsystemscope.com/textures/download/8k_earth_clouds.jpg",
    "elev_bump_8k.jpg": "https://www.solarsystemscope.com/textures/download/8k_earth_normal_map.jpg",
    "water_8k.png": "https://www.solarsystemscope.com/textures/download/8k_earth_specular_map.tif",
    "4k_stars_milky_way.jpg": "https://www.solarsystemscope.com/textures/download/8k_stars_milky_way.jpg",
    "moon_2k.jpg": "https://www.solarsystemscope.com/textures/download/2k_moon.jpg",
}

def download_file(url, filename):
    print(f"Downloading {filename}...")
    try:
        # We spoof a user agent because some servers block python urllib
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response, open(filename, 'wb') as out_file:
            out_file.write(response.read())
        print(f"Successfully downloaded {filename}")
    except Exception as e:
        print(f"Failed to download {filename}. Error: {e}")
        print(f"You may need to download it manually from a texture site (like solarsystemscope.com)")

def main():
    missing_files = []
    for filename in ASSETS:
        if not os.path.exists(filename):
            missing_files.append(filename)
    
    if not missing_files:
        print("All texture assets are already present.")
        return

    print(f"Missing {len(missing_files)} texture assets. Starting downloads...")
    for filename in missing_files:
        download_file(ASSETS[filename], filename)

if __name__ == "__main__":
    main()

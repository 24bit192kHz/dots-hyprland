import http.server
import socketserver
import urllib.parse
import urllib.request
import ssl
import json
import math
from PIL import Image
import io

ssl._create_default_https_context = ssl._create_unverified_context

PORT = 8080
TILE_SIZE = 512

# NASA GIBS EPSG:4326 levels
# Level 0: 2x1 tiles
# Level Z: (2 * 2^Z) x (2^Z) tiles
import os

def get_tile_path(z, x, y):
    return f"tiles/{z}/{x}/{y}.jpeg"

def fetch_tile(z, x, y):
    path = get_tile_path(z, x, y)
    try:
        if os.path.exists(path):
            return Image.open(path).convert('RGB')
        else:
            # Fallback if tile isn't downloaded yet
            url = f"https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/BlueMarble_ShadedRelief_Bathymetry/default/500m/{z}/{y}/{x}.jpeg"
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=5) as response:
                return Image.open(io.BytesIO(response.read())).convert('RGB')
    except Exception as e:
        print(f"Failed to fetch tile {z}/{x}/{y}: {e}")
        return Image.new('RGB', (TILE_SIZE, TILE_SIZE), (0, 0, 0))

class VirtualTextureHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/patch":
            self.send_response(404)
            self.end_headers()
            return
            
        params = urllib.parse.parse_qs(parsed.query)
        try:
            minU = float(params.get('minU', [0])[0])
            minV = float(params.get('minV', [0])[0])
            maxU = float(params.get('maxU', [1])[0])
            maxV = float(params.get('maxV', [1])[0])
        except Exception:
            self.send_response(400)
            self.end_headers()
            return

        # Clamp ONLY V. We allow U to be less than 0 or greater than 1 to support wrapping across the Date Line.
        minV = max(0.0, min(1.0, minV))
        maxV = max(0.0, min(1.0, maxV))
        
        widthU = maxU - minU
        if widthU <= 0.0001:
            widthU = 0.0001
            
        # NASA GIBS 500m TileMatrix definitions (Width, Height in tiles)
        MATRIX_SIZES = [
            (2, 1), (3, 2), (5, 3), (10, 5),
            (20, 10), (40, 20), (80, 40), (160, 80)
        ]
        
        # Calculate ideal zoom level based on requested zoomScale (approx)
        # The QML Earth Sphere vEarthSize is our reference width.
        # But wait, QML doesn't pass zoomScale, it just passes minU, maxU
        # Let's derive the desired level from the UV span we want to cover in 2048 pixels.
        # We are generating a 2048x2048 image for the requested UV patch.
        # So widthU * global_w should be around 2048 for 1:1 pixel mapping.
        desired_global_width = 2048.0 / widthU
        
        z = 0
        for i, (w, h) in enumerate(MATRIX_SIZES):
            if w * 512 >= desired_global_width:
                z = i
                break
        else:
            z = 7
            
        num_tiles_x, num_tiles_y = MATRIX_SIZES[z]
        global_w = num_tiles_x * 512
        global_h = num_tiles_y * 512
        
        px_minX = int(minU * global_w)
        px_maxX = int(maxU * global_w)
        px_minY = int(minV * global_h)
        px_maxY = int(maxV * global_h)
        
        if px_maxX <= px_minX: px_maxX = px_minX + 1
        if px_maxY <= px_minY: px_maxY = px_minY + 1
        
        tx_start = max(0, px_minX // TILE_SIZE)
        tx_end = min(num_tiles_x - 1, px_maxX // TILE_SIZE)
        ty_start = max(0, px_minY // TILE_SIZE)
        ty_end = min(num_tiles_y - 1, px_maxY // TILE_SIZE)
        
        while (tx_end - tx_start + 1) * (ty_end - ty_start + 1) > 25 and z > 0:
            z -= 1
            num_tiles_x, num_tiles_y = MATRIX_SIZES[z]
            global_w = num_tiles_x * 512
            global_h = num_tiles_y * 512
            px_minX = int(minU * global_w)
            px_maxX = int(maxU * global_w)
            px_minY = int(minV * global_h)
            px_maxY = int(maxV * global_h)
            tx_start = max(0, px_minX // TILE_SIZE)
            tx_end = min(num_tiles_x - 1, px_maxX // TILE_SIZE)
            ty_start = max(0, px_minY // TILE_SIZE)
            ty_end = min(num_tiles_y - 1, px_maxY // TILE_SIZE)

        patch_w = px_maxX - px_minX
        patch_h = px_maxY - px_minY
        
        out_img = Image.new('RGB', (patch_w, patch_h))
        
        print(f"Streaming Patch: UV({minU:.3f},{minV:.3f} to {maxU:.3f},{maxV:.3f}) Level: {z} Tiles: {tx_start}-{tx_end}, {ty_start}-{ty_end}")
        
        for ty in range(ty_start, ty_end + 1):
            for tx in range(tx_start, tx_end + 1):
                # Wrap horizontal tile indices to support seamless 180-degree dateline crossing
                wrapped_tx = tx % num_tiles_x
                tile = fetch_tile(z, wrapped_tx, ty)
                
                # Where to place this tile on our big canvas?
                paste_x = (tx * 512) - px_minX
                paste_y = (ty * 512) - px_minY
                
                out_img.paste(tile, (paste_x, paste_y))
                
        img_byte_arr = io.BytesIO()
        out_img.save(img_byte_arr, format='JPEG', quality=85)
        img_byte_arr.seek(0)
        
        self.send_response(200)
        self.send_header('Content-type', 'image/jpeg')
        self.send_header('Access-Control-Allow-Origin', '*')
        # Instead of custom headers, we'll just let QML remember what it asked for.
        self.end_headers()
        try:
            self.wfile.write(img_byte_arr.getvalue())
        except (BrokenPipeError, ConnectionResetError):
            # The client (Quickshell) closed the connection before we finished sending.
            pass

if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), VirtualTextureHandler) as httpd:
        print("Serving Virtual Texture daemon at port", PORT)
        httpd.serve_forever()

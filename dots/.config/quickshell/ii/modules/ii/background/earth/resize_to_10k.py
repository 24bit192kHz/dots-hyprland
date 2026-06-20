from PIL import Image

Image.MAX_IMAGE_PIXELS = None

print("Loading 16K image...")
img = Image.open("earth_16k.jpg")

print("Scaling down to 10K to fit within Qt's 256MB memory limit...")
# 10240x5120 takes 200MB uncompressed, which perfectly bypasses the 256MB limit!
img_10k = img.resize((10240, 5120), Image.Resampling.LANCZOS)

print("Saving earth_10k.jpg...")
img_10k.save("earth_10k.jpg", "JPEG", quality=92, subsampling=1)
print("Done!")

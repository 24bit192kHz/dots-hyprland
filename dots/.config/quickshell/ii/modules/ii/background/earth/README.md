# Quickshell Earth Live

A fully interactive, real-time 3D Earth wallpaper designed for Wayland/Quickshell. 
It features accurate celestial mechanics (sun position, sidereal time, moon orbit) and dynamic cloud covers.

## Features
- **Real-Time Sun & Moon**: Accurate celestial tracking based on current UTC time.
- **ISS Orbital Mode**: After 30 seconds of inactivity, the camera seamlessly transitions into a 5x speed orbit mimicking the International Space Station (51.6° inclination).
- **Parallax Background**: The background Milky Way stars rotate at a 1:10 parallax ratio, creating deep 3D optical illusions.
- **Dynamic Clouds**: Cloud maps are generated dynamically based on real-time meteorological data (via `vtexture_server.py`).

## Requirements
- `quickshell` (Wayland Desktop Shell)
- `python3` (for cloud stitching and asset downloading)
- `curl` (used by QML for geolocation)

## Setup

1. **Download Textures**
   The massive 4K/8K textures are ignored from version control to keep the repo lightweight. 
   Run the download script to automatically fetch them from public archives:
   ```bash
   python3 download_assets.py
   ```

2. **Start the Dynamic Texture Server**
   Start the python backend to generate dynamic cloud layers:
   ```bash
   python3 vtexture_server.py
   ```

3. **Launch Quickshell**
   Start the actual UI:
   ```bash
   quickshell shell.qml
   ```

## Controls
- **Mouse Drag**: Rotate the Earth manually.
- **Scroll Wheel**: Zoom in and out.
- **Idle**: Stop interacting for 30 seconds to automatically trigger the ISS orbital cinematic flyby.

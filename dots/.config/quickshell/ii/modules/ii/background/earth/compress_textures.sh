#!/bin/bash
set -e

echo "Compressing earth_8k.jpg..."
magick earth_8k.jpg -define dds:compression=dxt1 earth_8k.dds &

echo "Compressing normal_water_8k.png..."
# DXT5 is needed for alpha channel (water mask)
magick normal_water_8k.png -define dds:compression=dxt5 normal_water_8k.dds &

echo "Compressing 8k_stars_milky_way.jpg..."
magick 8k_stars_milky_way.jpg -define dds:compression=dxt1 8k_stars_milky_way.dds &

echo "Compressing moon_8k.jpg..."
magick moon_8k.jpg -define dds:compression=dxt1 moon_8k.dds &

wait
echo "All conversions finished."

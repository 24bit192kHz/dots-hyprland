import numpy as np

def simulate(cameraTilt, userOffsetAngle):
    gmst = 0.0
    userLonRad = 0.0
    
    # Screen center
    sphereNorm = np.array([0.0, 0.0, 1.0])
    
    # Rotate by -cameraTilt
    c, s = np.cos(-cameraTilt), np.sin(-cameraTilt)
    earthNorm = np.array([
        sphereNorm[0],
        sphereNorm[1]*c - sphereNorm[2]*s,
        sphereNorm[1]*s + sphereNorm[2]*c
    ])
    
    np_vec = np.array([0.0, 1.0, 0.0])
    
    localSiderealTime = gmst + userLonRad - userOffsetAngle
    greenwichLocalRa = gmst - localSiderealTime
    greenwichVec = np.array([np.sin(greenwichLocalRa), 0.0, np.cos(greenwichLocalRa)])
    eastVec = np.array([np.sin(greenwichLocalRa + np.pi/2), 0.0, np.cos(greenwichLocalRa + np.pi/2)])
    
    eqPlane = earthNorm - np.dot(earthNorm, np_vec) * np_vec
    eqLen = np.linalg.norm(eqPlane)
    if eqLen > 0:
        cosLon = np.dot(eqPlane, greenwichVec) / eqLen
        sinLon = np.dot(eqPlane, eastVec) / eqLen
        absoluteLon = np.arctan2(sinLon, cosLon)
    else:
        absoluteLon = 0.0
        
    earthLat = np.arcsin(np.dot(earthNorm, np_vec))
    
    uv = (absoluteLon / (2*np.pi) + 0.5, 0.5 - earthLat / np.pi)
    return uv

print("Center straight:", simulate(0.0, 0.0))
print("Center tilted 30deg down:", simulate(30.0 * np.pi/180.0, 0.0))
print("Center tilted 30deg down, pan right 90deg:", simulate(30.0 * np.pi/180.0, 90.0 * np.pi/180.0))

import numpy as np

def test(userTiltOffset, userOffsetAngle, moonRa, moonDec):
    gmst = 0.0
    userLonRad = 0.0
    moonDistance = 20.0
    
    localSiderealTime = gmst + userLonRad - userOffsetAngle
    moonLocalRa = moonRa - localSiderealTime
    
    baseMoonX = np.sin(moonLocalRa) * np.cos(moonDec) * moonDistance
    baseMoonY = np.sin(moonDec) * moonDistance
    baseMoonZ = np.cos(moonLocalRa) * np.cos(moonDec) * moonDistance
    
    cameraTilt = userTiltOffset + np.pi/6.0
    
    moonX3D = baseMoonX
    moonY3D = baseMoonY * np.cos(cameraTilt) - baseMoonZ * np.sin(cameraTilt)
    moonZ3D = baseMoonY * np.sin(cameraTilt) + baseMoonZ * np.cos(cameraTilt)
    
    print(f"X: {moonX3D:.2f}, Y: {moonY3D:.2f}, Z: {moonZ3D:.2f}")

# Look straight at the moon
print("Look straight at moon (Ra=0, Dec=0):")
test(0.0, 0.0, 0.0, 0.0)

# Move camera up
print("Tilt camera up:")
test(0.5, 0.0, 0.0, 0.0)

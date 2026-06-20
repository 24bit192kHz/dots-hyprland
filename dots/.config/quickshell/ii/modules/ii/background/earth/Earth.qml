import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    required property var modelData
    required property QtObject solarState
    required property var monitorLayout
    required property real sceneCenterX
    required property real sceneCenterY
    required property real primaryScreenHeight

    screen: modelData

    WlrLayershell.namespace: "earth-sphere-bg"
    WlrLayershell.layer: WlrLayer.Bottom

    focusable: false
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    implicitWidth: root.screen.width
    implicitHeight: root.screen.height

    // ── Screen Position (auto-detected from hyprctl) ─────
    property string screenName: root.modelData.name || ""
    property var myMonitor: root.monitorLayout[root.screenName] || null
    property real screenGlobalX: root.myMonitor ? root.myMonitor.x : 0
    property real screenGlobalY: root.myMonitor ? root.myMonitor.y : 0

    // Scene sizing from primary screen
    property real baseSize: root.primaryScreenHeight * 0.75

    // Scene center (center of primary/focused monitor)
    property real sceneCX: root.sceneCenterX
    property real sceneCY: root.sceneCenterY

    // Convert scene-relative position to local screen coordinates
    function toLocalX(relX) { return root.sceneCX + relX - root.screenGlobalX }
    function toLocalY(relY) { return root.sceneCY + relY - root.screenGlobalY }

    // ── Convenience Aliases ──────────────────────────────
    property real zoomScale: root.solarState.zoomScale
    property real userOffsetAngle: root.solarState.userOffsetAngle
    property real userTiltOffset: root.solarState.userTiltOffset
    property real utcDaysMod: root.solarState.utcDaysMod

    // ── High Precision Astronomical Coordinates ────────────────
    property real sunRa: root.solarState.sunRa
    property real sunDec: root.solarState.sunDec
    property real moonRa: root.solarState.moonRa
    property real moonDec: root.solarState.moonDec
    property real gmst: root.solarState.gmst
    property real eps: root.solarState.eps
    
    // Local Apparent Sidereal Time (LAST) at the center of the screen
    // userOffsetAngle is included so dragging the mouse orbits the camera, changing time-of-day perspective.
    property real localSiderealTime: gmst + root.solarState.userLonRad - root.userOffsetAngle
    
    // Convert Equatorial (RA/Dec) to Local Camera Cartesian
    // Camera is looking down -Z axis, at RA = localSiderealTime, Dec = 0
    property real sunLocalRa: sunRa - localSiderealTime
    property real baseSunX: Math.sin(sunLocalRa) * Math.cos(sunDec) * root.sunDistance
    property real baseSunY: Math.sin(sunDec) * root.sunDistance
    // Positive Z so that when sunLocalRa=0 (camera between Sun and Earth), Sun is behind the camera (+Z)
    property real baseSunZ: Math.cos(sunLocalRa) * Math.cos(sunDec) * root.sunDistance
    
    property real moonLocalRa: moonRa - localSiderealTime
    property real baseMoonX: Math.sin(moonLocalRa) * Math.cos(moonDec) * root.moonDistance
    property real baseMoonY: Math.sin(moonDec) * root.moonDistance
    property real baseMoonZ: Math.cos(moonLocalRa) * Math.cos(moonDec) * root.moonDistance

    // ── Camera Projection ──────────────────────────────
    property real cameraTilt: root.solarState.userTiltOffset + Math.PI / 6.0 // Look down slightly

    // Apply Camera Tilt to Celestial Bodies
    // We intentionally decouple the Sun and Moon from the camera tilt so they remain
    // beautifully framed in the background sky rather than sweeping wildly off-screen.
    property real sunX3D: baseSunX
    property real sunY3D: baseSunY
    property real sunZ3D: baseSunZ

    property real moonX3D: baseMoonX
    property real moonY3D: baseMoonY
    property real moonZ3D: baseMoonZ


    // ── 3D Scene Properties ──────────────────────────────
    property real orbitRadius: root.baseSize * 0.9
    property real cameraZ: root.baseSize * 3.0      // Camera distance from Earth
    property real sunDistance: root.baseSize * 6.0  // True distance to the Sun
    property real moonDistance: root.baseSize * 2.0 // True distance to the Moon

    property bool moonInFrontOfCamera: root.moonZ3D < root.cameraZ
    property real moonDistToCamera: root.cameraZ - root.moonZ3D
    property real moonProjScale: moonInFrontOfCamera ? (root.cameraZ / Math.max(0.001, root.moonDistToCamera)) : 0

    property real moonProjX: root.moonX3D * root.moonProjScale
    property real baseMoonSize: root.baseSize * 0.27
    property real vMoonSize: root.baseMoonSize * root.zoomScale * root.moonProjScale

    

    property bool sunInFrontOfCamera: root.sunZ3D < root.cameraZ
    property real sunDistToCamera: root.cameraZ - root.sunZ3D
    property real sunProjScale: sunInFrontOfCamera ? (root.cameraZ / Math.max(0.001, root.sunDistToCamera)) : 0

    property real sunProjX: root.sunX3D * root.sunProjScale
    property real baseSunSize: root.baseSize * 5.0
    property real vSunSize: root.baseSunSize * root.zoomScale * root.sunProjScale

    // ── Viewport Positions ───────────────────────────────
    property real vEarthSize: root.baseSize * root.zoomScale
    property real vEarthX: toLocalX(-root.vEarthSize / 2)
    property real vEarthY: toLocalY(-root.vEarthSize / 2)

    property real vMoonX: toLocalX(root.moonProjX * root.zoomScale - root.vMoonSize / 2)
    property real vMoonY: toLocalY(-root.moonY3D * root.zoomScale * root.moonProjScale - root.vMoonSize / 2)

    property real vSunX: toLocalX(root.sunProjX * root.zoomScale - root.vSunSize / 2)
    property real vSunY: toLocalY(-root.sunY3D * root.zoomScale * root.sunProjScale - root.vSunSize / 2 + root.baseSize * 0.16 * root.zoomScale * root.sunProjScale)

    // Wayland mask removed to allow the full-screen background to render.
    
    // ── Global Background (Dynamic Equirectangular Panorama) ──
    Image { id: milkyWayTexSrc; source: Qt.resolvedUrl("4k_stars_milky_way.jpg"); mipmap: true; visible: false }

    ShaderEffect {
        id: bgSphere
        anchors.fill: parent
        z: -10

        property real localSiderealTime: root.localSiderealTime
        property real userTiltOffset: root.userTiltOffset
        property real aspect: root.width / Math.max(1.0, root.height)

        property var bgTex: milkyWayTexSrc

        vertexShader: "stars.vert.qsb"
        fragmentShader: "stars.frag.qsb"
    }

    // ── Interaction ──────────────────────────────────────
    MouseArea {
        id: dragArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton

        property real lastX: 0
        property real lastY: 0

        onPressed: (mouse) => {
            lastX = mouse.x
            lastY = mouse.y
            root.solarState.isDragging = true
            root.solarState.issModeActive = false
            root.solarState.lastInteractionTime = Date.now()
        }

        onPositionChanged: (mouse) => {
            root.solarState.lastInteractionTime = Date.now()
            if (root.solarState.isDragging) {
                let dx = mouse.x - lastX
                let dy = mouse.y - lastY
                
                // Scale panning sensitivity inversely with zoom so the screen-space movement matches mouse movement
                let sensitivity = 500.0 * root.zoomScale
                
                root.solarState.userOffsetAngle += dx / sensitivity
                root.solarState.userTiltOffset += dy / sensitivity

                // Allow tilting all the way to the poles (Math.PI / 2)
                // We subtract the base camera tilt (Math.PI / 6) to stop exactly at the poles
                let maxTilt = (Math.PI / 2.0) - (Math.PI / 6.0)
                let minTilt = -(Math.PI / 2.0) - (Math.PI / 6.0)
                if (root.solarState.userTiltOffset > maxTilt) root.solarState.userTiltOffset = maxTilt
                if (root.solarState.userTiltOffset < minTilt) root.solarState.userTiltOffset = minTilt

                lastX = mouse.x
                lastY = mouse.y
            }
        }

        onReleased: {
            root.solarState.isDragging = false
        }

        onWheel: (wheel) => {
            root.solarState.issModeActive = false
            root.solarState.lastInteractionTime = Date.now()
            let factor = root.solarState.ctrlHeld ? 1.5 : 1.15
            if (wheel.angleDelta.y > 0) {
                root.solarState.zoomScale = Math.min(root.solarState.zoomScale * factor, 250.0)
            } else if (wheel.angleDelta.y < 0) {
                root.solarState.zoomScale = Math.max(root.solarState.zoomScale / factor, 0.15)
            }
        }
    }

    // ── Sun depth ────────────────────────────────────────
    // Depth handled by perspective projection above

    // ── Textures ─────────────────────────────────────────
    Image { id: earthTexSrc; source: Qt.resolvedUrl("earth_8k_opt.jpg"); mipmap: true; visible: false }
    Image { id: nightTexSrc; source: Qt.resolvedUrl("night_8k.jpg"); sourceSize: Qt.size(4096, 2048); mipmap: true; visible: false }
    Image { id: bumpTexSrc; source: Qt.resolvedUrl("elev_bump_8k.jpg"); sourceSize: Qt.size(4096, 2048); mipmap: true; visible: false }
    Image { id: waterTexSrc; source: Qt.resolvedUrl("water_8k.png"); sourceSize: Qt.size(4096, 2048); mipmap: true; visible: false }
    Image { id: cloudTexSrc; source: Qt.resolvedUrl("clouds_4k.jpg"); mipmap: true; visible: false }
    Image { id: moonTexSrc; source: Qt.resolvedUrl("moon_2k.jpg"); mipmap: true; visible: false }

    // ── Virtual Texturing ────────────────────────────────
    property string patchUrlA: ""
    property string patchUrlB: ""
    property bool activeIsA: true
    property real patchMinU: 0.0
    property real patchMaxU: 0.0
    property real patchMinV: 0.0
    property real patchMaxV: 0.0

    property real nextPatchMinU: 0.0
    property real nextPatchMaxU: 0.0
    property real nextPatchMinV: 0.0
    property real nextPatchMaxV: 0.0

    Timer {
        id: patchUpdateTimer
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            let max_visible_x = root.width / vEarthSize;
            let max_visible_y = root.height / vEarthSize;
            
            if (max_visible_x > 0.8 || max_visible_y > 0.8) {
                root.patchMinU = 0; root.patchMaxU = 0; root.patchMinV = 0; root.patchMaxV = 0;
                root.nextPatchMinU = 0; root.nextPatchMaxU = 0; root.nextPatchMinV = 0; root.nextPatchMaxV = 0;
                root.patchUrlA = "";
                root.patchUrlB = "";
                return;
            }
            
            let lon_range = Math.asin(Math.min(1.0, max_visible_x));
            let lat_range = Math.asin(Math.min(1.0, max_visible_y));
            
            let center_lon = root.solarState.userLonRad - root.solarState.userOffsetAngle;
            let center_lat = root.cameraTilt;
            
            let u_center = (center_lon / (2.0 * Math.PI)) + 0.5;
            u_center = u_center - Math.floor(u_center);
            let v_center = 0.5 - (center_lat / Math.PI);
            
            // Fetch a patch slightly larger than the screen to avoid edge pop-in
            let bufferU = (lon_range / (2.0 * Math.PI)) * 1.5;
            let bufferV = (lat_range / Math.PI) * 1.5;
            
            let minU = u_center - bufferU;
            let maxU = u_center + bufferU;
            let minV = Math.max(0.0, v_center - bufferV);
            let maxV = Math.min(1.0, v_center + bufferV);
            
            // Allow patches to wrap across the Date Line (minU < 0.0 or maxU > 1.0)
            if (true) {
                // Only request a new patch if we've moved significantly
                if (Math.abs(minU - nextPatchMinU) > (bufferU * 0.2) || Math.abs(minV - nextPatchMinV) > (bufferV * 0.2) || nextPatchMaxU === 0.0) {
                    root.nextPatchMinU = minU;
                    root.nextPatchMaxU = maxU;
                    root.nextPatchMinV = minV;
                    root.nextPatchMaxV = maxV;
                    if (root.activeIsA) {
                        patchTexB.targetMinU = minU;
                        patchTexB.targetMaxU = maxU;
                        patchTexB.targetMinV = minV;
                        patchTexB.targetMaxV = maxV;
                        root.patchUrlB = "http://localhost:8080/patch?minU=" + minU + "&maxU=" + maxU + "&minV=" + minV + "&maxV=" + maxV + "&t=" + Date.now();
                    } else {
                        patchTexA.targetMinU = minU;
                        patchTexA.targetMaxU = maxU;
                        patchTexA.targetMinV = minV;
                        patchTexA.targetMaxV = maxV;
                        root.patchUrlA = "http://localhost:8080/patch?minU=" + minU + "&maxU=" + maxU + "&minV=" + minV + "&maxV=" + maxV + "&t=" + Date.now();
                    }
                }
            } else {
                root.patchMinU = 0; root.patchMaxU = 0;
                root.nextPatchMinU = 0; root.nextPatchMaxU = 0;
                root.patchUrlA = "";
                root.patchUrlB = "";
            }
        }
    }

    Image {
        id: patchTexA
        source: root.patchUrlA
        mipmap: true
        asynchronous: true
        visible: false
        property real targetMinU: 0.0
        property real targetMaxU: 0.0
        property real targetMinV: 0.0
        property real targetMaxV: 0.0
        onStatusChanged: {
            if (status === Image.Ready && !root.activeIsA) {
                root.patchMinU = targetMinU;
                root.patchMaxU = targetMaxU;
                root.patchMinV = targetMinV;
                root.patchMaxV = targetMaxV;
                root.activeIsA = true;
                console.log("Patch A applied!");
            }
        }
    }
    
    Image {
        id: patchTexB
        source: root.patchUrlB
        mipmap: true
        asynchronous: true
        visible: false
        property real targetMinU: 0.0
        property real targetMaxU: 0.0
        property real targetMinV: 0.0
        property real targetMaxV: 0.0
        onStatusChanged: {
            if (status === Image.Ready && root.activeIsA) {
                root.patchMinU = targetMinU;
                root.patchMaxU = targetMaxU;
                root.patchMinV = targetMinV;
                root.patchMaxV = targetMaxV;
                root.activeIsA = false;
                console.log("Patch B applied!");
            }
        }
    }

    // ── Sun ──────────────────────────────────────────────
    ShaderEffect {
        id: sunSphere
        x: root.vSunX; y: root.vSunY
        width: root.vSunSize; height: root.vSunSize
        z: -2
        
        opacity: {
            if (!root.sunInFrontOfCamera) return 0.0;
            // Fade out smoothly as it sweeps past the camera
            let fadeDist = root.cameraZ * 0.3; // start fading when within 30% of camera plane
            if (root.sunDistToCamera < fadeDist) {
                return Math.max(0.0, root.sunDistToCamera / fadeDist);
            }
            return 1.0;
        }
        visible: opacity > 0

        vertexShader: "sun.vert.qsb"
        fragmentShader: "sun.frag.qsb"
    }

    // ── Earth ────────────────────────────────────────────
    ShaderEffect {
        id: earthSphere
        x: root.vEarthX; y: root.vEarthY
        width: root.vEarthSize; height: root.vEarthSize
        z: 0

        property real utcDaysMod: root.utcDaysMod
        property real cameraTilt: root.cameraTilt

        property real time: root.solarState.timeSec
        property real gmst: root.solarState.gmst
        property real sunRa: root.solarState.sunRa
        property real sunDec: root.solarState.sunDec
        property real userLonRad: root.solarState.userLonRad
        property real userOffsetAngle: root.userOffsetAngle

        property variant earthTex: earthTexSrc
        property variant nightTex: nightTexSrc
        property variant bumpTex: bumpTexSrc
        property variant waterTex: waterTexSrc
        property variant cloudTex: cloudTexSrc
        property var patchTex: root.activeIsA ? patchTexA : patchTexB
        property vector4d patchBounds: Qt.vector4d(root.patchMinU, root.patchMinV, root.patchMaxU, root.patchMaxV)
        property real patchReady: ((root.activeIsA ? patchTexA.status : patchTexB.status) === Image.Ready) ? 1.0 : 0.0
        property real cloudOpacity: Math.min(1.0, Math.max(0.0, 1.0 - (root.zoomScale - 15.0) / 10.0))

        vertexShader: "earth.vert.qsb"
        fragmentShader: "earth.frag.qsb"
    }

    // ── Moon ─────────────────────────────────────────────
    ShaderEffect {
        id: moonSphere
        x: root.vMoonX; y: root.vMoonY
        width: root.vMoonSize; height: root.vMoonSize
        z: root.moonZ3D < 0 ? -1 : 1

        property real angle: -(root.moonRa / (Math.PI * 2))
        property real tilt: root.userTiltOffset * Math.PI
        property real lightDirX: root.sunX3D - root.moonX3D
        property real lightDirY: root.sunY3D - root.moonY3D
        property real lightDirZ: root.sunZ3D - root.moonZ3D

        property var moonTex: moonTexSrc

        vertexShader: "moon.vert.qsb"
        fragmentShader: "moon.frag.qsb"
    }
}

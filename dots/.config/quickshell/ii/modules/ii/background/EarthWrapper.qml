import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../../background/earth/core/astronomy.js" as Astro
import "../../background/earth/core"

// ── Embedded Earth Wallpaper ──────────────────────────────────
// Item-based wrapper for embedding inside Background.qml's PanelWindow.
// Combines shell.qml state management + Earth.qml rendering.
// The parent (Background.qml) handles screen positioning and parallax.
Item {
    id: root

    // ── Internal Solar State ─────────────────────────────────
    property var solarState: QtObject {
        id: solarState

        property real targetUserOffsetAngle: 0
        property real targetUserTiltOffset: 0
        property real userOffsetAngle: 0
        property real userTiltOffset: 0
        property real userLonRad: 0
        property real timeSec: 0
        property real targetZoomScale: 1.0
        property real zoomScale: 1.0
        property bool isDragging: false
        property bool ctrlHeld: false
        property bool isSwitchingPlanet: false

        property bool issModeActive: false
        property real issPhase: 0.0
        property real issOmega: 0.0
        property real lastInteractionTime: Date.now()

        function startIssOrbit() {
            if (issModeActive) return
            let actualLat = userTiltOffset + (Math.PI / 6.0)
            let inc = 51.6 * Math.PI / 180.0
            let sinPhase = Math.sin(actualLat) / Math.sin(inc)
            sinPhase = Math.max(-1.0, Math.min(1.0, sinPhase))
            let phase = Math.asin(sinPhase)
            let alpha = Math.atan2(Math.cos(inc) * Math.sin(phase), Math.cos(phase))
            let currentRa = gmst + userLonRad - userOffsetAngle
            let omega = currentRa - alpha
            issPhase = phase
            issOmega = omega
            issModeActive = true
        }

        property var planets: ["earth", "moon", "mercury", "venus_surface", "mars", "jupiter", "saturn", "uranus", "neptune"]
        property var savedRotations: [0, 0, 0, 0, 0, 0, 0, 0, 0]
        property var savedTilts: [0, 0, 0, 0, 0, 0, 0, 0, 0]

        property int activePlanetIndex: Math.max(0, planets.indexOf(Quickshell.env("PLANET")))
        property int previousPlanetIndex: activePlanetIndex
        property string activePlanet: planets[activePlanetIndex]

        onActivePlanetIndexChanged: {
            solarState.isSwitchingPlanet = true
            savedRotations[previousPlanetIndex] = targetUserOffsetAngle
            savedTilts[previousPlanetIndex] = targetUserTiltOffset

            Qt.callLater(function() {
                targetUserOffsetAngle = savedRotations[activePlanetIndex]
                userOffsetAngle = targetUserOffsetAngle

                targetUserTiltOffset = savedTilts[activePlanetIndex]
                userTiltOffset = targetUserTiltOffset

                previousPlanetIndex = activePlanetIndex
                root.forceAstroUpdate()

                Qt.callLater(function() { solarState.isSwitchingPlanet = false })
            })
        }

        property real sunRa: 0
        property real sunDec: 0
        property real moonRa: 0
        property real moonDec: 0
        property real gmst: 0
        property real eps: 0

        property string tileServerUrl: ""

        property real utcDaysMod: 0
        property string cloudUpdateFlag: "init"

        Behavior on zoomScale {
            NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
        }
        Behavior on userOffsetAngle {
            enabled: !solarState.isDragging && !solarState.issModeActive && !solarState.isSwitchingPlanet
            NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
        }
        Behavior on userTiltOffset {
            enabled: !solarState.isDragging && !solarState.issModeActive && !solarState.isSwitchingPlanet
            NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
        }
    }

    // ── Monitor Layout (auto-detected from Hyprland) ────────
    property var monitorLayout: ({})
    property real primaryCenterX: 0
    property real primaryCenterY: 0
    property real primaryScreenHeight: root.height

    Process {
        id: hyprProc
        command: ["hyprctl", "monitors", "-j"]
        running: true

        property string buf: ""

        stdout: SplitParser {
            onRead: data => { hyprProc.buf += data + "\n" }
        }

        onExited: function(exitCode, exitStatus) {
            if (exitCode !== 0) return
            try {
                let monitors = JSON.parse(hyprProc.buf)
                let layout = {}
                let primaryName = ""

                for (let i = 0; i < monitors.length; i++) {
                    let m = monitors[i]
                    let lw = m.width / m.scale
                    let lh = m.height / m.scale
                    if (m.transform % 2 === 1) {
                        let tmp = lw; lw = lh; lh = tmp
                    }
                    layout[m.name] = {
                        x: m.x,
                        y: m.y,
                        width: lw,
                        height: lh,
                        physicalWidth: m.width,
                        physicalHeight: m.height
                    }
                    if (m.focused) primaryName = m.name
                }

                if (!primaryName && monitors.length > 0)
                    primaryName = monitors[0].name

                root.monitorLayout = layout

                let p = layout[primaryName]
                if (p) {
                    root.primaryCenterX = p.x + p.width / 2.0
                    root.primaryCenterY = p.y + p.height / 2.0
                    root.primaryScreenHeight = p.height
                }
            } catch(e) {
                console.error("Failed to parse hyprctl:", e)
            }
        }
    }

    // ── Local SQLite Tile Server ─────────────────────────────
    Process {
        id: tileServerProc
        command: ["python3", Qt.resolvedUrl("../../background/earth/server.py").toString().replace("file://", "")]
        running: true

        stdout: SplitParser {
            onRead: data => {
                if (data.startsWith("http")) {
                    solarState.tileServerUrl = data.trim()
                }
            }
        }
    }

    // ── Cloud API Location Resolver ──────────────────────────
    Process {
        id: locProc
        command: ["curl", "-s", "http://ip-api.com/json/"]
        running: true

        property string buf: ""
        stdout: SplitParser {
            onRead: data => { locProc.buf += data }
        }

        onExited: function(exitCode, exitStatus) {
            if (exitCode !== 0) return
            try {
                let data = JSON.parse(locProc.buf)
                if (data.status === "success" && data.lon !== undefined) {
                    solarState.userLonRad = data.lon * Math.PI / 180.0
                    solarState.targetUserOffsetAngle = 0
                    solarState.userOffsetAngle = 0
                    root.forceAstroUpdate()
                }
            } catch(e) {
                console.error("Failed to parse location:", e)
            }
        }
    }

    // ── Key Monitor (Ctrl) ───────────────────────────────────
    Process {
        id: ctrlProc
        command: ["python3", Qt.resolvedUrl("../../background/earth/scripts/ctrl_monitor.py").toString().replace("file://", "")]
        running: true

        stdout: SplitParser {
            onRead: data => {
                let trimmed = data.trim()
                if (trimmed === "1") solarState.ctrlHeld = true
                else if (trimmed === "0") solarState.ctrlHeld = false
            }
        }
    }

    // ── Astronomy Engine ─────────────────────────────────────
    property real lastAstroCalc: 0

    function forceAstroUpdate() {
        let ms = Date.now()
        lastAstroCalc = ms
        let currentPlanet = solarState.planets[solarState.activePlanetIndex]
        let astro = Astro.calculateAstronomy(ms, solarState.userLonRad, currentPlanet)
        solarState.sunRa = astro.sun_ra
        solarState.sunDec = astro.sun_dec
        solarState.moonRa = astro.moon_ra
        solarState.moonDec = astro.moon_dec
        solarState.gmst = astro.gmst_rad
        solarState.eps = astro.eps_rad
        solarState.utcDaysMod = (ms / 86400000.0) % 1.0
    }

    Component.onCompleted: {
        forceAstroUpdate()
    }

    // ── Real-Time Astronomy Timer ────────────────────────────
    Timer {
        id: astroTimer
        interval: solarState.issModeActive ? 16 : 1000
        running: true
        repeat: true
        onTriggered: {
            let ms = Date.now()

            if (ms - lastAstroCalc > 1000 || solarState.issModeActive) {
                root.forceAstroUpdate()
            }

            if (!solarState.issModeActive && (ms - solarState.lastInteractionTime) > 30000) {
                solarState.startIssOrbit()
                astroTimer.interval = 16
            }

            if (solarState.issModeActive) {
                let phaseDelta = (0.016 * 5.0 / 5520.0) * 2.0 * Math.PI
                solarState.issPhase += phaseDelta
                if (solarState.issPhase > 2.0 * Math.PI) solarState.issPhase -= 2.0 * Math.PI

                let inc = 51.6 * Math.PI / 180.0

                let actualLatRad = Math.asin(Math.sin(inc) * Math.sin(solarState.issPhase))
                solarState.targetUserTiltOffset = actualLatRad - (Math.PI / 6.0)
                solarState.userTiltOffset = solarState.targetUserTiltOffset

                let alpha = Math.atan2(Math.cos(inc) * Math.sin(solarState.issPhase), Math.cos(solarState.issPhase))
                let targetRa = solarState.issOmega + alpha

                solarState.targetUserOffsetAngle = solarState.gmst + solarState.userLonRad - targetRa
                solarState.userOffsetAngle = solarState.targetUserOffsetAngle
            }
        }
    }

    // ── Live Cloud Map Updater ───────────────────────────────
    Timer {
        interval: 10800000
        running: true
        repeat: true
        onTriggered: {
            solarState.cloudUpdateFlag = Date.now().toString()
        }
    }

    // ── Convenience Aliases ──────────────────────────────────
    property real zoomScale: solarState.zoomScale
    property real userOffsetAngle: solarState.userOffsetAngle
    property real userTiltOffset: solarState.userTiltOffset
    property real utcDaysMod: solarState.utcDaysMod

    property real sunRa: solarState.sunRa
    property real sunDec: solarState.sunDec
    property real moonRa: solarState.moonRa
    property real moonDec: solarState.moonDec
    property real gmst: solarState.gmst
    property real eps: solarState.eps

    // ── Screen Position (centered in item) ───────────────────
    property real baseSize: root.height * 0.75
    property real sceneCX: root.width / 2.0
    property real sceneCY: root.height / 2.0
    property real screenGlobalX: 0
    property real screenGlobalY: 0

    function toLocalX(relX) { return root.sceneCX + relX - root.screenGlobalX }
    function toLocalY(relY) { return root.sceneCY + relY - root.screenGlobalY }

    // ── Batch Astro Math Variables ───────────────────────────
    property real localSiderealTime: 0
    property real sunLocalRa: 0
    property real baseSunX: 0
    property real baseSunY: 0
    property real baseSunZ: 0
    property real moonLocalRa: 0
    property real baseMoonX: 0
    property real baseMoonY: 0
    property real baseMoonZ: 0
    property real cameraTilt: 0
    property real tiltParallax: 0
    property real tiltCos: 1
    property real tiltSin: 0
    property real sunX3D: 0
    property real sunY3D: 0
    property real sunZ3D: 0
    property real moonX3D: 0
    property real moonY3D: 0
    property real moonZ3D: 0
    property real orbitRadius: root.baseSize * 0.9
    property real baseCameraZ: root.baseSize * 3.0
    property real currentCameraZ: baseCameraZ
    property real sunDistance: solarState.activePlanet === "moon" ? root.baseSize * 150.0 : root.baseSize * 6.0
    property real moonDistance: solarState.activePlanet === "moon" ? root.baseSize * 44.24 : root.baseSize * 2.0
    property bool moonInFrontOfCamera: false
    property real moonDistToCamera: 1
    property real moonProjScale: 0
    property real moonProjX: 0
    property real baseMoonSize: solarState.activePlanet === "moon" ? root.baseSize * 3.667 : root.baseSize * 0.27
    property real vMoonSize: 0
    property bool sunInFrontOfCamera: false
    property real sunDistToCamera: 1
    property real sunProjScale: 0
    property real sunProjX: 0
    property real baseSunSize: solarState.activePlanet === "moon" ? root.baseSize * 125.0 : root.baseSize * 5.0
    property real vSunSize: 0
    property real earthProjScale: 1
    property real vEarthSize: 0
    property real vEarthX: 0
    property real vEarthY: 0
    property real vMoonX: 0
    property real vMoonY: 0
    property real vSunX: 0
    property real vSunY: 0

    function updateAstroMath() {
        let _lst = root.gmst + solarState.userLonRad - root.userOffsetAngle;
        root.localSiderealTime = _lst;

        let _sunRa = root.sunRa;
        let _sunDec = root.sunDec;
        let _moonRa = root.moonRa;
        let _moonDec = root.moonDec;
        let _sunDist = root.sunDistance;
        let _moonDist = root.moonDistance;

        let _sunLocalRa = _sunRa - _lst;
        root.sunLocalRa = _sunLocalRa;
        let _cosSunDec = Math.cos(_sunDec);
        let _sinSunDec = Math.sin(_sunDec);
        let _bsx = Math.sin(_sunLocalRa) * _cosSunDec * _sunDist;
        let _bsy = _sinSunDec * _sunDist;
        let _bsz = Math.cos(_sunLocalRa) * _cosSunDec * _sunDist;
        root.baseSunX = _bsx;
        root.baseSunY = _bsy;
        root.baseSunZ = _bsz;

        let _moonLocalRa = _moonRa - _lst;
        root.moonLocalRa = _moonLocalRa;
        let _cosMoonDec = Math.cos(_moonDec);
        let _sinMoonDec = Math.sin(_moonDec);
        let _bmx = Math.sin(_moonLocalRa) * _cosMoonDec * _moonDist;
        let _bmy = _sinMoonDec * _moonDist;
        let _bmz = Math.cos(_moonLocalRa) * _cosMoonDec * _moonDist;
        root.baseMoonX = _bmx;
        root.baseMoonY = _bmy;
        root.baseMoonZ = _bmz;

        let _tiltOffset = solarState.userTiltOffset;
        root.cameraTilt = _tiltOffset + Math.PI / 6.0;
        let _tiltParallax = _tiltOffset * 0.1;
        root.tiltParallax = _tiltParallax;
        let _tiltCos = Math.cos(_tiltParallax);
        let _tiltSin = Math.sin(_tiltParallax);
        root.tiltCos = _tiltCos;
        root.tiltSin = _tiltSin;

        let _sunY3D = _bsy * _tiltCos - _bsz * _tiltSin;
        let _sunZ3D = _bsy * _tiltSin + _bsz * _tiltCos;
        root.sunX3D = _bsx;
        root.sunY3D = _sunY3D;
        root.sunZ3D = _sunZ3D;

        let _moonY3D = _bmy * _tiltCos - _bmz * _tiltSin;
        let _moonZ3D = _bmy * _tiltSin + _bmz * _tiltCos;
        root.moonX3D = _bmx;
        root.moonY3D = _moonY3D;
        root.moonZ3D = _moonZ3D;

        let _camZ = root.baseCameraZ / Math.max(0.0001, root.zoomScale);
        root.currentCameraZ = _camZ;

        let _mFront = _moonZ3D < _camZ;
        root.moonInFrontOfCamera = _mFront;
        let _mDist = _camZ - _moonZ3D;
        root.moonDistToCamera = _mDist;
        let _mScale = _mFront ? (root.baseCameraZ / Math.max(0.001, _mDist)) : 0;
        root.moonProjScale = _mScale;
        let _mProjX = _bmx * _mScale;
        root.moonProjX = _mProjX;
        let _vMSz = root.baseMoonSize * _mScale;
        root.vMoonSize = _vMSz;

        let _sFront = _sunZ3D < _camZ;
        root.sunInFrontOfCamera = _sFront;
        let _sDist = _camZ - _sunZ3D;
        root.sunDistToCamera = _sDist;
        let _sScale = _sFront ? (root.baseCameraZ / Math.max(0.001, _sDist)) : 0;
        root.sunProjScale = _sScale;
        let _sProjX = _bsx * _sScale;
        root.sunProjX = _sProjX;
        let _vSSz = root.baseSunSize * _sScale;
        root.vSunSize = _vSSz;

        let _eScale = root.baseCameraZ / _camZ;
        root.earthProjScale = _eScale;
        let _vESz = root.baseSize * _eScale;
        root.vEarthSize = _vESz;

        root.vEarthX = root.toLocalX(-_vESz / 2);
        root.vEarthY = root.toLocalY(-_vESz / 2);

        root.vMoonX = root.toLocalX(_mProjX - _vMSz / 2);
        root.vMoonY = root.toLocalY(-_moonY3D * _mScale - _vMSz / 2);

        root.vSunX = root.toLocalX(_sProjX - _vSSz / 2);
        root.vSunY = root.toLocalY(-_sunY3D * _sScale - _vSSz / 2 + root.baseSize * 0.16 * _sScale);
    }

    Connections {
        target: root
        function onUserOffsetAngleChanged() { root.updateAstroMath() }
        function onUserTiltOffsetChanged() { root.updateAstroMath() }
        function onZoomScaleChanged() { root.updateAstroMath() }
        function onSunRaChanged() { root.updateAstroMath() }
        function onSunDecChanged() { root.updateAstroMath() }
        function onMoonRaChanged() { root.updateAstroMath() }
        function onMoonDecChanged() { root.updateAstroMath() }
        function onGmstChanged() { root.updateAstroMath() }
        function onBaseSizeChanged() { root.updateAstroMath() }
    }

    Component.onCompleted: {
        updateAstroMath()
    }

    // ── Global Background (Milky Way) ────────────────────────
    ShaderEffect {
        id: bgSphere
        anchors.fill: parent
        z: -10

        property real localSiderealTime: root.localSiderealTime
        property real userTiltOffset: root.userTiltOffset
        property real aspect: root.width / Math.max(1.0, root.height)

        property var bgTex: milkyWayImg

        vertexShader: "../../background/earth/assets/shaders/stars.vert.qsb"
        fragmentShader: "../../background/earth/assets/shaders/stars.frag.qsb"
    }

    // ── Interaction ──────────────────────────────────────────
    MouseArea {
        id: dragArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton

        property real lastX: 0
        property real lastY: 0

        onPressed: (mouse) => {
            lastX = mouse.x
            lastY = mouse.y
            solarState.isDragging = true
            solarState.issModeActive = false
            solarState.lastInteractionTime = Date.now()
        }

        onPositionChanged: (mouse) => {
            solarState.lastInteractionTime = Date.now()
            if (solarState.isDragging) {
                let dx = mouse.x - lastX
                let dy = mouse.y - lastY

                let sensitivity = 500.0 * root.zoomScale

                solarState.targetUserOffsetAngle += dx / sensitivity
                solarState.targetUserTiltOffset += dy / sensitivity

                let maxTilt = (Math.PI / 2.0) - (Math.PI / 6.0)
                let minTilt = -(Math.PI / 2.0) - (Math.PI / 6.0)
                if (solarState.targetUserTiltOffset > maxTilt) solarState.targetUserTiltOffset = maxTilt
                if (solarState.targetUserTiltOffset < minTilt) solarState.targetUserTiltOffset = minTilt

                solarState.userOffsetAngle = solarState.targetUserOffsetAngle
                solarState.userTiltOffset = solarState.targetUserTiltOffset

                lastX = mouse.x
                lastY = mouse.y
            }
        }

        onReleased: {
            solarState.isDragging = false
        }

        onWheel: (wheel) => {
            solarState.issModeActive = false
            solarState.lastInteractionTime = Date.now()

            let old_zoomScale = solarState.targetZoomScale
            let input_factor = solarState.ctrlHeld ? 1.5 : 1.15

            if (wheel.angleDelta.y > 0) {
                solarState.targetZoomScale = Math.min(old_zoomScale * input_factor, 250.0)
            } else if (wheel.angleDelta.y < 0) {
                solarState.targetZoomScale = Math.max(old_zoomScale / input_factor, 0.15)
            }

            let new_zoomScale = solarState.targetZoomScale
            let actual_factor = new_zoomScale / old_zoomScale

            if (actual_factor !== 1.0) {
                let getLonLatAt = function(px, py, zoom) {
                    let vSize = root.baseSize * zoom;
                    let vX = root.sceneCX - vSize / 2.0 - root.screenGlobalX;
                    let vY = root.sceneCY - vSize / 2.0 - root.screenGlobalY;

                    let nx = (px - vX) / vSize * 2.0 - 1.0;
                    let ny = 1.0 - (py - vY) / vSize * 2.0;

                    let z2 = 1.0 - nx*nx - ny*ny;
                    if (z2 < 0.0) return null;

                    let z = Math.sqrt(z2);
                    let a = -solarState.targetUserTiltOffset - (Math.PI / 6.0);
                    let c = Math.cos(a);
                    let s = Math.sin(a);

                    let normY = ny * c - z * s;
                    let normZ = ny * s + z * c;
                    let normX = nx;

                    let lat = Math.asin(Math.max(-1.0, Math.min(1.0, normY)));

                    let greenwichLocalRa = -solarState.userLonRad + solarState.targetUserOffsetAngle;
                    let sinG = Math.sin(greenwichLocalRa);
                    let cosG = Math.cos(greenwichLocalRa);

                    let dotEast = normX * cosG - normZ * sinG;
                    let dotGreenwich = normX * sinG + normZ * cosG;
                    let lon = Math.atan2(dotEast, dotGreenwich);

                    return {lon: lon, lat: lat};
                };

                let before = getLonLatAt(wheel.x, wheel.y, old_zoomScale);
                let after = getLonLatAt(wheel.x, wheel.y, new_zoomScale);

                if (before && after) {
                    solarState.targetUserOffsetAngle += (after.lon - before.lon);

                    let new_tilt = solarState.targetUserTiltOffset + (before.lat - after.lat);
                    let maxTilt = (Math.PI / 2.0) - (Math.PI / 6.0);
                    let minTilt = -(Math.PI / 2.0) - (Math.PI / 6.0);
                    solarState.targetUserTiltOffset = Math.max(minTilt, Math.min(maxTilt, new_tilt));
                }
            }

            solarState.zoomScale = solarState.targetZoomScale
            solarState.userOffsetAngle = solarState.targetUserOffsetAngle
            solarState.userTiltOffset = solarState.targetUserTiltOffset
        }
    }

    // ── Textures ─────────────────────────────────────────────
    Image { id: milkyWayImg; asynchronous: true; source: Qt.resolvedUrl("../../background/earth/assets/textures/8k_stars_milky_way.jpg"); sourceSize: Qt.size(4096, 2048); mipmap: true; visible: false }

    Image { id: earthImg; asynchronous: true; source: solarState.activePlanet === "earth" ? Qt.resolvedUrl("../../background/earth/assets/textures/earth_8k_opt.jpg") : (solarState.activePlanet === "moon" ? Qt.resolvedUrl("../../background/earth/assets/textures/8k_moon.jpg") : Qt.resolvedUrl("../../background/earth/assets/textures/2k_" + solarState.activePlanet + ".jpg")); sourceSize: Qt.size(4096, 2048); mipmap: true; visible: false }
    Image { id: satelliteEarthImg; asynchronous: true; source: solarState.activePlanet === "moon" ? Qt.resolvedUrl("../../background/earth/assets/textures/earth_8k_opt.jpg") : ""; sourceSize: Qt.size(2048, 2048); mipmap: true; visible: false }

    Image { id: nightTexSrc; asynchronous: true; source: Qt.resolvedUrl("../../background/earth/assets/textures/night_8k.jpg"); sourceSize: Qt.size(4096, 2048); mipmap: true; visible: false }

    Image { id: bumpTexSrc; asynchronous: true; source: Qt.resolvedUrl("../../background/earth/assets/textures/elev_bump_8k.jpg"); sourceSize: Qt.size(4096, 2048); mipmap: true; visible: false }

    Image { id: waterTexSrc; asynchronous: true; source: Qt.resolvedUrl("../../background/earth/assets/textures/water_8k.png"); sourceSize: Qt.size(4096, 2048); mipmap: true; visible: false }

    Image { id: cloudTexSrc; asynchronous: true; source: Qt.resolvedUrl("../../background/earth/assets/textures/8k_earth_clouds.jpg"); sourceSize: Qt.size(4096, 2048); mipmap: true; visible: false }

    Image { id: moonImg; asynchronous: true; source: Qt.resolvedUrl("../../background/earth/assets/textures/moon_2k.jpg"); sourceSize: Qt.size(4096, 2048); mipmap: true; visible: false }

    Image { id: saturnRingTexSrc; asynchronous: true; source: Qt.resolvedUrl("../../background/earth/assets/textures/8k_saturn_ring_alpha.png"); sourceSize: Qt.size(4096, 2048); mipmap: true; visible: false }

    // ── Native Virtual Texturing ─────────────────────────────
    property real patchMinU: 0.0
    property real patchMaxU: 0.0
    property real patchMinV: 0.0
    property real patchMaxV: 0.0

    VirtualPatch {
        id: virtualPatch
        minU: root.patchMinU
        maxU: root.patchMaxU
        minV: root.patchMinV
        maxV: root.patchMaxV
        tileServerUrl: solarState.tileServerUrl
    }

    onCameraTiltChanged: updatePatchBounds()
    onWidthChanged: updatePatchBounds()
    onHeightChanged: updatePatchBounds()
    onVEarthSizeChanged: updatePatchBounds()

    Connections {
        target: solarState
        function onUserOffsetAngleChanged() { root.updatePatchBounds() }
        function onUserLonRadChanged() { root.updatePatchBounds() }
    }

    function updatePatchBounds() {
        if (!solarState) return;

        let max_visible_x = root.width / vEarthSize;
        let max_visible_y = root.height / vEarthSize;

        if (max_visible_x > 1.5 || max_visible_y > 1.5) {
            root.patchMinU = 0; root.patchMaxU = 0; root.patchMinV = 0; root.patchMaxV = 0;
            return;
        }

        let lon_range = Math.asin(Math.min(1.0, max_visible_x));
        let lat_range = Math.asin(Math.min(1.0, max_visible_y));

        let local_vEarthX = root.sceneCX - root.vEarthSize / 2.0 - root.screenGlobalX;
        let local_vEarthY = root.sceneCY - root.vEarthSize / 2.0 - root.screenGlobalY;

        let screenCenterLocalX = root.width / 2.0 - local_vEarthX;
        let screenCenterLocalY = root.height / 2.0 - local_vEarthY;

        let x = (screenCenterLocalX / root.vEarthSize) * 2.0 - 1.0;
        let y = 1.0 - (screenCenterLocalY / root.vEarthSize) * 2.0;

        let center_lon = solarState.userLonRad - solarState.userOffsetAngle;
        let center_lat = root.cameraTilt;

        let z2 = 1.0 - x*x - y*y;
        if (z2 >= 0.0) {
            let z = Math.sqrt(z2);
            let a = -root.cameraTilt;
            let c = Math.cos(a);
            let s = Math.sin(a);

            let normY = y * c - z * s;
            let normZ = y * s + z * c;
            let normX = x;

            center_lat = Math.asin(Math.max(-1.0, Math.min(1.0, normY)));

            let greenwichLocalRa = -solarState.userLonRad + solarState.userOffsetAngle;
            let sinG = Math.sin(greenwichLocalRa);
            let cosG = Math.cos(greenwichLocalRa);

            let dotEast = normX * cosG - normZ * sinG;
            let dotGreenwich = normX * sinG + normZ * cosG;
            center_lon = Math.atan2(dotEast, dotGreenwich);
        }

        let u_center = (center_lon / (2.0 * Math.PI)) + 0.5;
        u_center = u_center - Math.floor(u_center);

        let maxLat = 1.4844;
        let clamped_lat = Math.max(-maxLat, Math.min(maxLat, center_lat));
        let v_center = 0.5 - Math.log(Math.tan(Math.PI / 4.0 + clamped_lat / 2.0)) / (2.0 * Math.PI);

        let bufferU = (lon_range / (2.0 * Math.PI)) * 1.5;
        let mercator_scale = 1.0 / Math.max(0.01, Math.cos(clamped_lat));
        let bufferV = (lat_range / (2.0 * Math.PI)) * 1.5 * mercator_scale;

        root.patchMinU = u_center - bufferU;
        root.patchMaxU = u_center + bufferU;
        root.patchMinV = Math.max(0.0, v_center - bufferV);
        root.patchMaxV = Math.min(1.0, v_center + bufferV);
    }

    // ── Sun ──────────────────────────────────────────────────
    ShaderEffect {
        id: sunSphere
        x: root.vSunX; y: root.vSunY
        width: root.vSunSize; height: root.vSunSize
        z: -2

        opacity: {
            if (!root.sunInFrontOfCamera) return 0.0;
            let fadeDist = root.baseCameraZ * 0.3;
            if (root.sunDistToCamera < fadeDist) {
                return Math.max(0.0, root.sunDistToCamera / fadeDist);
            }
            return 1.0;
        }
        visible: opacity > 0

        vertexShader: "../../background/earth/assets/shaders/sun.vert.qsb"
        fragmentShader: "../../background/earth/assets/shaders/sun.frag.qsb"
    }

    // ── Planet Label ─────────────────────────────────────────
    Connections {
        target: solarState
        function onActivePlanetChanged() {
            planetLabel.opacity = 0.8
            labelTimer.restart()
        }
    }

    Text {
        id: planetLabel
        text: {
            let name = solarState.activePlanet
            if (name === "venus_surface") return "VENUS"
            return name.toUpperCase()
        }
        color: "#f4f4f4"
        font.family: "Futura"
        font.pixelSize: 64
        font.weight: Font.Thin
        font.letterSpacing: 48
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#cc000000"
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 4
            shadowBlur: 1.0
        }

        anchors.horizontalCenter: earthSphere.horizontalCenter
        y: Math.max(parent.height * 0.15, earthSphere.y - height - 60)
        z: 10

        opacity: 0.0

        Behavior on opacity {
            NumberAnimation { duration: 800; easing.type: Easing.InOutQuad }
        }

        Timer {
            id: labelTimer
            interval: 1500
            onTriggered: planetLabel.opacity = 0.0
        }
    }

    // ── Earth Sphere ─────────────────────────────────────────
    ShaderEffect {
        id: earthSphere
        x: root.vEarthX; y: root.vEarthY
        width: root.vEarthSize; height: root.vEarthSize
        z: 0

        property real isEarth: solarState.activePlanet === "earth" ? 1.0 : 0.0
        property real isSaturn: solarState.activePlanet === "saturn" ? 1.0 : 0.0

        property real utcDaysMod: root.utcDaysMod
        property real cameraTilt: root.cameraTilt

        property real time: solarState.timeSec
        property real gmst: solarState.gmst
        property real sunRa: solarState.sunRa
        property real sunDec: solarState.sunDec
        property real userLonRad: solarState.userLonRad
        property real userOffsetAngle: root.userOffsetAngle

        property variant earthTex: earthImg
        property variant moonTex: moonImg

        property variant nightTex: nightTexSrc
        property variant bumpTex: bumpTexSrc
        property variant waterTex: waterTexSrc
        property variant cloudTex: cloudTexSrc
        property var patchTex: virtualPatch.textureProvider
        property vector4d patchBounds: Qt.vector4d(root.patchMinU, root.patchMinV, root.patchMaxU, root.patchMaxV)
        property real patchReady: 1.0
        property real cloudOpacity: solarState.activePlanet === "earth" ? Math.min(1.0, Math.max(0.0, 1.0 - (root.zoomScale - 15.0) / 10.0)) : 0.0

        vertexShader: "../../background/earth/assets/shaders/earth.vert.qsb"
        fragmentShader: "../../background/earth/assets/shaders/earth.frag.qsb"
    }

    // ── Saturn Rings ─────────────────────────────────────────
    ShaderEffect {
        id: saturnRing
        visible: solarState.activePlanet === "saturn"

        x: root.vEarthX - root.vEarthSize
        y: root.vEarthY - root.vEarthSize
        width: root.vEarthSize * 3.0
        height: root.vEarthSize * 3.0
        z: 1

        property real utcDaysMod: 0.0
        property real cameraTilt: root.cameraTilt
        property real time: 0.0
        property real gmst: solarState.gmst
        property real sunRa: solarState.sunRa
        property real sunDec: solarState.sunDec
        property real userLonRad: solarState.userLonRad
        property real userOffsetAngle: root.userOffsetAngle
        property vector4d patchBounds: Qt.vector4d(0,0,0,0)
        property real patchReady: 0.0
        property real cloudOpacity: 0.0
        property real isEarth: 0.0
        property real isSaturn: 1.0

        property var ringTex: saturnRingTexSrc

        vertexShader: "../../background/earth/assets/shaders/earth.vert.qsb"
        fragmentShader: "../../background/earth/assets/shaders/saturn_ring.frag.qsb"
    }

    // ── Satellite (Moon or Earth) ────────────────────────────
    ShaderEffect {
        id: satelliteSphere

        opacity: {
            if (!root.moonInFrontOfCamera) return 0.0;
            let fadeDist = root.baseCameraZ * 0.1;
            if (root.moonDistToCamera < fadeDist) {
                return Math.max(0.0, root.moonDistToCamera / fadeDist);
            }
            return 1.0;
        }
        visible: (solarState.activePlanet === "earth" || solarState.activePlanet === "moon") && opacity > 0

        x: root.vMoonX; y: root.vMoonY
        width: root.vMoonSize; height: root.vMoonSize
        z: root.moonZ3D < 0 ? -1 : 1

        property real angle: solarState.activePlanet === "moon" ? -(solarState.userLonRad - root.userOffsetAngle) / (Math.PI * 2) : -(root.moonRa / (Math.PI * 2))
        property real tilt: root.userTiltOffset * Math.PI
        property real rawLightDirX: solarState.activePlanet === "moon" ? 1.0 : root.sunX3D - root.moonX3D
        property real rawLightDirY: solarState.activePlanet === "moon" ? 0.3 : root.sunY3D - root.moonY3D
        property real rawLightDirZ: solarState.activePlanet === "moon" ? 0.5 : root.sunZ3D - root.moonZ3D
        property real lightDirLen: Math.max(0.001, Math.sqrt(rawLightDirX*rawLightDirX + rawLightDirY*rawLightDirY + rawLightDirZ*rawLightDirZ))
        property real lightDirX: rawLightDirX / lightDirLen
        property real lightDirY: rawLightDirY / lightDirLen
        property real lightDirZ: rawLightDirZ / lightDirLen

        property var moonTex: solarState.activePlanet === "moon" ? satelliteEarthImg : moonImg
        property var cloudTex: cloudTexSrc
        property var nightTex: nightTexSrc
        property real time: solarState.timeSec

        vertexShader: "../../background/earth/assets/shaders/moon.vert.qsb"
        fragmentShader: solarState.activePlanet === "moon" ? "../../background/earth/assets/shaders/satellite_earth.frag.qsb" : "../../background/earth/assets/shaders/moon.frag.qsb"
    }

    // ── Keyboard Shortcuts ───────────────────────────────────
    Shortcut {
        sequence: "Right"
        onActivated: {
            solarState.activePlanetIndex = (solarState.activePlanetIndex + 1) % solarState.planets.length
        }
    }

    Shortcut {
        sequence: "Left"
        onActivated: {
            solarState.activePlanetIndex = (solarState.activePlanetIndex - 1 + solarState.planets.length) % solarState.planets.length
        }
    }
}

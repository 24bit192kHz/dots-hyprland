pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.weather
import qs.modules.ii.background.widgets.weather
import "earth/core/astronomy.js" as Astro

Variants {
    id: root
    model: Quickshell.screens

    // ── Shared Monitor Layout (populated by hyprProc) ─────
    property var monitorLayout: ({})
    property real primaryCenterX: 960
    property real primaryCenterY: 540
    property real primaryHeight: 1080

    // ── Shared Solar System State ────────────────────────
    property QtObject solarState: QtObject {
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

            // Update planet color immediately
            root.updateActivePlanetColor()

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

    // ── Planet Dominant Colors ───────────────────────────
    // Imperatively managed — QML can't track JS object key mutations,
    // so we store the *active* planet's color as a dedicated property.
    property color activePlanetColor: Appearance.colors.colPrimary

    function updateActivePlanetColor() {
        let name = solarState.activePlanet
        let cached = _planetColorCache[name]
        if (cached !== undefined) {
            activePlanetColor = Qt.color(cached)
        } else {
            activePlanetColor = Appearance.colors.colPrimary
        }
    }

    property var _planetColorCache: ({})

    Component.onCompleted: {
        forceAstroUpdate()
    }

    // ── Astronomy Engine ─────────────────────────────────
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

    // ── Real-Time Astronomy Timer ────────────────────────
    Timer {
        id: astroTimer
        interval: solarState.issModeActive ? 16 : 1000
        running: true
        repeat: true
        onTriggered: {
            let ms = Date.now()

            if (ms - root.lastAstroCalc > 1000 || solarState.issModeActive) {
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

    // ── Live Cloud Map Updater ───────────────────────────
    Timer {
        interval: 10800000
        running: true
        repeat: true
        onTriggered: {
            solarState.cloudUpdateFlag = Date.now().toString()
        }
    }

    PanelWindow {
        id: bgRoot

        required property var modelData

        property bool isFirstScreen: bgRoot.modelData === Quickshell.screens[0]

        // Hide when fullscreen
        property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
        property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
        visible: GlobalStates.screenLocked || (!(activeWorkspaceWithFullscreen != undefined)) || !Config?.options.background.hideWhenFullscreen

        // Workspaces
        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
        property list<var> relevantWindows: HyprlandData.windowList.filter(win => win.monitor == monitor?.id && win.workspace.id >= 0).sort((a, b) => a.workspace.id - b.workspace.id)
        property int firstWorkspaceId: relevantWindows[0]?.workspace.id || 1
        property int lastWorkspaceId: relevantWindows[relevantWindows.length - 1]?.workspace.id || 10
        property int workspaceChunkSize: Config?.options.bar.workspaces.shown ?? 10
        property int totalWorkspaces: Math.ceil(lastWorkspaceId / workspaceChunkSize) * workspaceChunkSize
        // Wallpaper
        property bool wallpaperIsVideo: Config.options.background.wallpaperPath.endsWith(".mp4") || Config.options.background.wallpaperPath.endsWith(".webm") || Config.options.background.wallpaperPath.endsWith(".mkv") || Config.options.background.wallpaperPath.endsWith(".avi") || Config.options.background.wallpaperPath.endsWith(".mov")
        property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
        property bool wallpaperSafetyTriggered: {
            const enabled = Config.options.workSafety.enable.wallpaper;
            const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
            const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
            return enabled && sensitiveWallpaper && sensitiveNetwork;
        }
        readonly property real parallaxRation: Config.options.background.parallax.workspaceZoom
        property real minSuitableScale: 1 // Some reasonable init, to be updated
        property real effectiveWallpaperScale: minSuitableScale * parallaxRation
        property int wallpaperWidth: modelData.width // Some reasonable init value, to be updated
        property int wallpaperHeight: modelData.height // Some reasonable init value, to be updated
        property real scaledWallpaperWidth: wallpaperWidth * effectiveWallpaperScale
        property real scaledWallpaperHeight: wallpaperHeight * effectiveWallpaperScale
        property real parallaxTotalPixelsX: Math.max(0, scaledWallpaperWidth - screen.width)
        property real parallaxTotalPixelsY: Math.max(0, scaledWallpaperHeight - screen.height)
        readonly property bool verticalParallax: (Config.options.background.parallax.autoVertical && wallpaperHeight > wallpaperWidth) || Config.options.background.parallax.vertical
        // Colors
        property bool shouldBlur: (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        property color dominantColor: root.activePlanetColor
        property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
        property color colText: {
            if (wallpaperSafetyTriggered)
                return CF.ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.75);
            return (GlobalStates.screenLocked && shouldBlur) ? Appearance.colors.colOnLayer0 : CF.ColorUtils.colorWithLightness(dominantColor, (dominantColorIsDark ? 0.8 : 0.12));
        }
        Behavior on dominantColor {
            ColorAnimation { duration: 600; easing.type: Easing.InOutQuad }
        }
        Behavior on colText {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // Layer props
        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: (GlobalStates.screenLocked && !scaleAnim.running) ? WlrLayer.Overlay : WlrLayer.Bottom
        // WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:background"
        focusable: true
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: {
            if (!bgRoot.wallpaperSafetyTriggered || bgRoot.wallpaperIsVideo)
                return "transparent";
            return CF.ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colPrimary, 0.75);
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        onWallpaperPathChanged: {
            bgRoot.updateZoomScale();
            // Clock position gets updated after zoom scale is updated
        }

        // Wallpaper zoom scale
        function updateZoomScale() {
            getWallpaperSizeProc.path = bgRoot.wallpaperPath;
            getWallpaperSizeProc.running = true;
        }
        Process {
            id: getWallpaperSizeProc
            property string path: bgRoot.wallpaperPath
            command: ["magick", "identify", "-format", "%w %h", path]
            stdout: StdioCollector {
                id: wallpaperSizeOutputCollector
                onStreamFinished: {
                    const output = wallpaperSizeOutputCollector.text;
                    const [width, height] = output.split(" ").map(Number);
                    const [screenWidth, screenHeight] = [bgRoot.screen.width, bgRoot.screen.height];
                    bgRoot.wallpaperWidth = width;
                    bgRoot.wallpaperHeight = height;

                    // Perfect image; scale = 1
                    // Small picture; scale > 1; will zoom in the picture
                    // Big picture; scale < 1; will zoom out the picture
                    // Choose max number so every side will fit
                    bgRoot.minSuitableScale = Math.max(screenWidth / width, screenHeight / height);
                }
            }
        }

        // ── Monitor Layout Detection (all instances, fast read-only) ───
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
                        root.primaryHeight = p.height
                    }
                } catch(e) {
                    console.error("Failed to parse hyprctl:", e)
                }
            }
        }

        // ── Local SQLite Tile Server (first screen only) ──────────────
        Process {
            id: tileServerProc
            command: ["python3", Qt.resolvedUrl("earth/server.py").toString().replace("file://", "")]
            running: bgRoot.isFirstScreen

            stdout: SplitParser {
                onRead: data => {
                    if (data.startsWith("http")) {
                        solarState.tileServerUrl = data.trim()
                    }
                }
            }
        }

        // ── Cloud API Location Resolver (all instances, idempotent) ───
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

        // ── Key Monitor — Ctrl (first screen only) ────────────────────
        Process {
            id: ctrlProc
            command: ["python3", Qt.resolvedUrl("earth/scripts/ctrl_monitor.py").toString().replace("file://", "")]
            running: bgRoot.isFirstScreen

            stdout: SplitParser {
                onRead: data => {
                    let trimmed = data.trim()
                    if (trimmed === "1") solarState.ctrlHeld = true
                    else if (trimmed === "0") solarState.ctrlHeld = false
                }
            }
        }

        // ── Planet Color Extraction (first screen only) ──────────────
        property var planetTextures: ({
            "earth": "textures/earth_8k_opt.jpg",
            "moon": "textures/moon_2k.jpg",
            "mercury": "textures/2k_mercury.jpg",
            "venus_surface": "textures/2k_venus_surface.jpg",
            "mars": "textures/2k_mars.jpg",
            "jupiter": "textures/2k_jupiter.jpg",
            "saturn": "textures/2k_saturn.jpg",
            "uranus": "textures/2k_uranus.jpg",
            "neptune": "textures/2k_neptune.jpg"
        })

        function extractPlanetColor(planetName) {
            let texFile = bgRoot.planetTextures[planetName]
            if (!texFile) return
            let fullPath = Qt.resolvedUrl("earth/" + texFile).toString().replace("file://", "")
            planetColorProc.texturePath = fullPath
            planetColorProc.planetName = planetName
            planetColorProc.running = false
            planetColorProc.running = true
        }

        Process {
            id: planetColorProc
            property string texturePath: ""
            property string planetName: ""
            command: ["python3", Qt.resolvedUrl("scripts/images/extract_dominant_color.py").toString().replace("file://", ""), texturePath]
            running: false

            stdout: StdioCollector {
                id: planetColorOutput
                onStreamFinished: {
                    let hex = planetColorOutput.text.trim()
                    if (hex && hex.startsWith("#")) {
                        root._planetColorCache[planetColorProc.planetName] = hex
                        if (planetColorProc.planetName === solarState.activePlanet) {
                            root.activePlanetColor = Qt.color(hex)
                        }
                    }
                }
            }
        }

        Component.onCompleted: {
            if (isFirstScreen) {
                for (let i = 0; i < solarState.planets.length; i++) {
                    extractPlanetColor(solarState.planets[i])
                }
            }
        }

        // ── Keyboard Shortcuts (PanelWindow level for focus) ───────────
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

        Item {
            anchors.fill: parent

            // Dynamic Earth Wallpaper
            EarthWrapper {
                id: wallpaper
                width: bgRoot.screen.width + bgRoot.parallaxTotalPixelsX
                height: bgRoot.screen.height + bgRoot.parallaxTotalPixelsY
                visible: opacity > 0 && !blurLoader.active
                opacity: (!bgRoot.wallpaperIsVideo) ? 1 : 0

                solarState: root.solarState
                monitorLayout: root.monitorLayout
                sceneCenterX: root.primaryCenterX
                sceneCenterY: root.primaryCenterY
                primaryScreenHeight: root.primaryHeight
                screenName: bgRoot.modelData.name || ""

                property int workspaceIndex: (bgRoot.monitor.activeWorkspace?.id ?? 1) - 1
                property real middleFraction: 0.5
                property real fraction: {
                    if (bgRoot.totalWorkspaces <= 1) {
                        return middleFraction;
                    }
                    return Math.max(0, Math.min(1, workspaceIndex / (bgRoot.totalWorkspaces - 1)));
                }

                property real usedFractionX: {
                    let usedFraction = middleFraction;
                    if (Config.options.background.parallax.enableWorkspace && !bgRoot.verticalParallax) {
                        usedFraction = fraction;
                    }
                    if (Config.options.background.parallax.enableSidebar) {
                        let sidebarFraction = bgRoot.parallaxRation / bgRoot.workspaceChunkSize / 2;
                        usedFraction += (sidebarFraction * GlobalStates.sidebarRightOpen - sidebarFraction * GlobalStates.sidebarLeftOpen);
                    }
                    return Math.max(0, Math.min(1, usedFraction));
                }
                property real usedFractionY: {
                    let usedFraction = middleFraction;
                    if (Config.options.background.parallax.enableWorkspace && bgRoot.verticalParallax) {
                        usedFraction = fraction;
                    }
                    return Math.max(0, Math.min(1, usedFraction));
                }

                x: {
                    if (bgRoot.screen.width > width) {
                        return (bgRoot.screen.width - width) / 2;
                    }
                    return - bgRoot.parallaxTotalPixelsX * usedFractionX;
                }
                y: {
                    if (bgRoot.screen.height > height) {
                        return (bgRoot.screen.height - height) / 2;
                    }
                    return - bgRoot.parallaxTotalPixelsY * usedFractionY;
                }

                Behavior on x {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
            }


            Loader {
                id: blurLoader
                active: Config.options.lock.blur.enable && (GlobalStates.screenLocked || scaleAnim.running)
                anchors.fill: wallpaper
                scale: GlobalStates.screenLocked ? Config.options.lock.blur.extraZoom : 1
                Behavior on scale {
                    NumberAnimation {
                        id: scaleAnim
                        duration: 400
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                    }
                }
                sourceComponent: GaussianBlur {
                    source: wallpaper
                    radius: GlobalStates.screenLocked ? Config.options.lock.blur.radius : 0
                    samples: radius * 2 + 1

                    Rectangle {
                        opacity: GlobalStates.screenLocked ? 1 : 0
                        anchors.fill: parent
                        color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                    }
                }
            }

            WidgetCanvas {
                id: widgetCanvas
                width: parent.width
                height: parent.height
                readonly property real parallaxFactor: {
                    var f = Config.options.background.parallax.widgetsFactor;
                    return f / bgRoot.parallaxRation;
                }
                readonly property real baseWallpaperOffsetX: (bgRoot.screen.width - wallpaper.width) / 2
                readonly property real baseWallpaperOffsetY: (bgRoot.screen.height - wallpaper.height) / 2
                readonly property real wallpaperTotalOffsetX: wallpaper.x - baseWallpaperOffsetX
                readonly property real wallpaperTotalOffsetY: wallpaper.y - baseWallpaperOffsetY
                readonly property bool locked: GlobalStates.screenLocked
                x: wallpaperTotalOffsetX * parallaxFactor * !locked
                y: wallpaperTotalOffsetY * parallaxFactor * !locked

                transitions: Transition {
                    PropertyAnimation {
                        properties: "width,height"
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                    AnchorAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.weather.enable
                    sourceComponent: WeatherWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.clock.enable
                    sourceComponent: ClockWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                    }
                }
            }

            // ── Mouse Interaction (z:100 — above all widgets) ──────────
            MouseArea {
                id: earthMouseArea
                z: 100
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

                        let sensitivity = 500.0 * solarState.zoomScale

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
                            let vSize = wallpaper.baseSize * zoom;
                            let vX = wallpaper.sceneCX - vSize / 2.0 - wallpaper.screenGlobalX;
                            let vY = wallpaper.sceneCY - vSize / 2.0 - wallpaper.screenGlobalY;

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
        }
    }
}

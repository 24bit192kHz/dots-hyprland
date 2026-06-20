import Quickshell
import Quickshell.Io
import QtQuick
import "astronomy.js" as Astro

ShellRoot {
    id: shell

    // ── Monitor Layout (auto-detected from Hyprland) ─────
    property var monitorLayout: ({})
    property real primaryCenterX: 960
    property real primaryCenterY: 540
    property real primaryHeight: 1080

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
                    layout[m.name] = { x: m.x, y: m.y, width: lw, height: lh }
                    if (m.focused) primaryName = m.name
                }

                if (!primaryName && monitors.length > 0)
                    primaryName = monitors[0].name

                shell.monitorLayout = layout

                let p = layout[primaryName]
                if (p) {
                    shell.primaryCenterX = p.x + p.width / 2.0
                    shell.primaryCenterY = p.y + p.height / 2.0
                    shell.primaryHeight = p.height
                }
            } catch(e) {
                console.error("Failed to parse hyprctl:", e)
            }
        }
    }

    // ── IP Geolocation (Auto-Center) ─────────────────────
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
                    // Center the camera mathematically on the user's longitude
                    state.userLonRad = data.lon * Math.PI / 180.0
                    state.userOffsetAngle = 0
                    
                    console.log("Centered Earth on", data.city + ",", data.country, "(Lon:", data.lon + ")")
                    
                    // Now that we are perfectly centered over the user, start the orbit seamlessly!
                    state.startIssOrbit()
                }
            } catch(e) {
                console.error("Failed to parse location:", e)
            }
        }
    }

    // ── Shared Solar System State ────────────────────────
    QtObject {
        id: state

        property real userOffsetAngle: 0
        property real userTiltOffset: 0
        property real userLonRad: 0
        property real timeSec: 0
        property real zoomScale: 1.0
        property bool isDragging: false
        property bool ctrlHeld: false
        property bool issModeActive: false
        property real issPhase: 0.0 // Phase of the ISS orbit (0 to 2PI)
        property real issOmega: 0.0 // Right Ascension of the ascending node
        property real lastInteractionTime: Date.now()
        
        function startIssOrbit() {
            if (issModeActive) return
            
            // Initialize orbit to start seamlessly at the current camera view
            let actualLat = userTiltOffset + (Math.PI / 6.0)
            let inc = 51.6 * Math.PI / 180.0 // ISS Inclination
            
            // Clamp latitude to the maximum orbital inclination bounds
            let sinPhase = Math.sin(actualLat) / Math.sin(inc)
            sinPhase = Math.max(-1.0, Math.min(1.0, sinPhase))
            
            // Calculate initial orbital phase from equator
            let phase = Math.asin(sinPhase)
            
            // Calculate the absolute Right Ascension of the orbit's ascending node
            let alpha = Math.atan2(Math.cos(inc) * Math.sin(phase), Math.cos(phase))
            let currentRa = gmst + userLonRad - userOffsetAngle
            let omega = currentRa - alpha
            
            issPhase = phase
            issOmega = omega
            issModeActive = true
            console.log("ISS Orbit Mode ACTIVATED (Idle Timeout)")
        }

        property real sunRa: 0
        property real sunDec: 0
        property real moonRa: 0
        property real moonDec: 0
        property real gmst: 0
        property real eps: 0
        
        property real utcDaysMod: 0
        property string cloudUpdateFlag: "init"

        Behavior on userTiltOffset {
            enabled: !state.isDragging && !state.issModeActive
            SpringAnimation { spring: 0.4; damping: 0.15; mass: 2.0; epsilon: 0.001 }
        }

        Behavior on zoomScale {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }

    // ── Key Monitor (Ctrl) ─────────────────
    Process {
        id: ctrlProc
        command: ["python3", Qt.resolvedUrl("ctrl_monitor.py").toString().replace("file://", "")]
        running: true

        stdout: SplitParser {
            onRead: data => {
                let trimmed = data.trim()
                if (trimmed === "1") state.ctrlHeld = true
                else if (trimmed === "0") state.ctrlHeld = false
            }
        }
    }

    // ── Real-Time Astronomy Engine ───────────────────────
    Timer {
        interval: 16 // 60fps
        running: true
        repeat: true
        onTriggered: {
            let ms = Date.now()
            let now = new Date(ms)
            
            // Fast time for shader animations (lightning, etc)
            state.timeSec = (ms % 1000000) / 1000.0
            
            // Execute rigorous astronomical algorithms
            let astro = Astro.calculateAstronomy(ms, state.userLonRad)
            state.sunRa = astro.sun_ra
            state.sunDec = astro.sun_dec
            state.moonRa = astro.moon_ra
            state.moonDec = astro.moon_dec
            state.gmst = astro.gmst_rad
            state.eps = astro.eps_rad
            state.utcDaysMod = (ms / 86400000.0) % 1.0
            
            // Execute ISS Orbital Dynamics
            if (!state.issModeActive && (ms - state.lastInteractionTime) > 30000) {
                state.startIssOrbit()
            }
            
            if (state.issModeActive) {
                // ISS completes one orbit every 92 minutes (5520 seconds)
                // We run at 5x real-time speed. dt is 16ms = 0.016s
                let phaseDelta = (0.016 * 5.0 / 5520.0) * 2.0 * Math.PI
                state.issPhase += phaseDelta
                if (state.issPhase > 2.0 * Math.PI) state.issPhase -= 2.0 * Math.PI
                
                let inc = 51.6 * Math.PI / 180.0
                
                // Calculate Orbital Latitude (subtract base camera tilt of 30 degrees)
                let actualLatRad = Math.asin(Math.sin(inc) * Math.sin(state.issPhase))
                state.userTiltOffset = actualLatRad - (Math.PI / 6.0)
                
                // Calculate Right Ascension from orbital phase
                let alpha = Math.atan2(Math.cos(inc) * Math.sin(state.issPhase), Math.cos(state.issPhase))
                let targetRa = state.issOmega + alpha
                
                // Keep the camera locked exactly to the orbital position over the rotating Earth
                // targetRa = gmst + userLonRad - userOffsetAngle
                state.userOffsetAngle = state.gmst + state.userLonRad - targetRa
            }
        }
    }

    // ── Live Cloud Map Updater ───────────────────────────
    Timer {
        interval: 10800000 // 3 hours in ms
        running: true
        repeat: true
        onTriggered: {
            state.cloudUpdateFlag = Date.now().toString()
            console.log("Fetching latest real-time cloud satellite imagery...")
        }
    }

    // One Earth panel per screen, all sharing the same state
    Variants {
        model: Quickshell.screens
        Earth {
            solarState: state
            monitorLayout: shell.monitorLayout
            sceneCenterX: shell.primaryCenterX
            sceneCenterY: shell.primaryCenterY
            primaryScreenHeight: shell.primaryHeight
        }
    }
}

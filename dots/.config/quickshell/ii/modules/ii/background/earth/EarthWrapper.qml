import QtQuick
import Quickshell
import Quickshell.Io
import "astronomy.js" as Astro

Item {
    id: wrapper
    
    // ── Monitor Layout ─────
    property var monitorLayout: ({})
    property real primaryCenterX: width / 2
    property real primaryCenterY: height / 2
    property real primaryHeight: height

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
                    state.userLonRad = data.lon * Math.PI / 180.0
                    state.userOffsetAngle = 0
                    state.startIssOrbit()
                }
            } catch(e) { }
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
            
            state.timeSec = (ms % 1000000) / 1000.0
            
            let astro = Astro.calculateAstronomy(ms, state.userLonRad)
            state.sunRa = astro.sun_ra
            state.sunDec = astro.sun_dec
            state.moonRa = astro.moon_ra
            state.moonDec = astro.moon_dec
            state.gmst = astro.gmst_rad
            state.eps = astro.eps_rad
            state.utcDaysMod = (ms / 86400000.0) % 1.0
            
            if (!state.issModeActive && (ms - state.lastInteractionTime) > 30000) {
                state.startIssOrbit()
            }
            
            if (state.issModeActive) {
                let phaseDelta = (0.016 * 5.0 / 5520.0) * 2.0 * Math.PI
                state.issPhase += phaseDelta
                if (state.issPhase > 2.0 * Math.PI) state.issPhase -= 2.0 * Math.PI
                
                let inc = 51.6 * Math.PI / 180.0
                let actualLatRad = Math.asin(Math.sin(inc) * Math.sin(state.issPhase))
                state.userTiltOffset = actualLatRad - (Math.PI / 6.0)
                
                let alpha = Math.atan2(Math.cos(inc) * Math.sin(state.issPhase), Math.cos(state.issPhase))
                let targetRa = state.issOmega + alpha
                state.userOffsetAngle = state.gmst + state.userLonRad - targetRa
            }
        }
    }

    Timer {
        interval: 10800000 // 3 hours
        running: true
        repeat: true
        onTriggered: state.cloudUpdateFlag = Date.now().toString()
    }

    Earth {
        anchors.fill: parent
        solarState: state
        monitorLayout: wrapper.monitorLayout
        sceneCenterX: wrapper.primaryCenterX
        sceneCenterY: wrapper.primaryCenterY
        primaryScreenHeight: wrapper.primaryHeight
    }
}

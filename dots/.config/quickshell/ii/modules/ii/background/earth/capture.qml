import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    PanelWindow {
        color: "transparent"
        Earth {
            id: earthItem
            solarState: QtObject {
                property real zoomScale: 1.0
                property real userOffsetAngle: 0.0
                property real userTiltOffset: 0.0
                property real sunOrbitAngle: 0.0
                property real moonOrbitAngle: 0.0
                property real utcDaysMod: 0.3895 // Approx 12:21 PM Saudi Arabia
                property real userLonRad: 0.815 // Saudi Arabia
            }
            monitorLayout: {}
            sceneCenterX: 500
            sceneCenterY: 500
            primaryScreenHeight: 1080
        }
        Timer {
            interval: 1000
            running: true
            onTriggered: {
                earthItem.grabToImage(function(result) {
                    result.saveToFile("/home/btw/test/earth/test_screenshot.png");
                    Qt.quit();
                });
            }
        }
    }
}

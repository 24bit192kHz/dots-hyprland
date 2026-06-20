import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    WlrLayershell.namespace: "earth-stars-bg"
    WlrLayershell.layer: WlrLayer.Bottom

    focusable: false
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    color: "transparent"

    implicitWidth: root.screen.width
    implicitHeight: root.screen.height

    Item {
        anchors.fill: parent

        // Star field — 600 random twinkling dots
        Repeater {
            model: 600

            Rectangle {
                id: star

                property real baseSize: 1.0 + Math.random() * 3.5
                width: baseSize
                height: baseSize
                radius: width / 2

                x: Math.random() * root.width
                y: Math.random() * root.height

                color: {
                    let r = Math.random();
                    if (r < 0.15) return "#cfe8ff";   // blue-white
                    if (r < 0.25) return "#fff4e0";   // warm
                    if (r < 0.35) return "#e0e8ff";   // cool
                    return "#ffffff";
                }

                opacity: 0.3 + Math.random() * 0.7

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    PauseAnimation { duration: Math.random() * 6000 }
                    NumberAnimation {
                        to: 0.1 + Math.random() * 0.3
                        duration: 800 + Math.random() * 2400
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        to: 0.5 + Math.random() * 0.5
                        duration: 800 + Math.random() * 2400
                        easing.type: Easing.InOutSine
                    }
                }

                layer.enabled: baseSize > 2.5
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blurMax: 8
                    blur: 0.3
                }
            }
        }
    }
}

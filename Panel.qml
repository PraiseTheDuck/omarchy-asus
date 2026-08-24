import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
    id: root
    moduleName: "io.github.moneytosms.asus"
    ipcTarget: "io.github.moneytosms.asus"
    manageIpc: false

    // Reusable draggable fan-curve editor. Shows a temp/speed line with
    // draggable points; commits the whole curve via onCommit(points) on
    // release, and offers a per-fan reset via onReset(). Points never leave
    // [30,100]c / [0,100]% and stay ordered by temp — see Model.moveFanPoint.
    component FanCurveEditor: Column {
        id: editor
        property var points: []
        property bool enabledState: false
        property color accent: "#44cc44"
        property color foreground: "white"
        property string fontFamily: "monospace"
        property bool interactive: true
        signal commit(var points)
        signal reset()

        width: parent ? parent.width : 0
        spacing: Style.space(4)

        Rectangle {
            width: parent.width
            height: Style.space(64)
            radius: Style.cornerRadius
            color: Qt.rgba(editor.foreground.r, editor.foreground.g, editor.foreground.b, 0.04)
            opacity: editor.interactive ? 1 : 0.4

            Canvas {
                id: canvas
                anchors.fill: parent
                anchors.margins: Style.space(6)
                renderStrategy: Canvas.Immediate

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    if (editor.points.length < 2) return
                    var w = width, h = height
                    ctx.strokeStyle = Qt.rgba(editor.foreground.r, editor.foreground.g, editor.foreground.b, 0.6)
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    for (var i = 0; i < editor.points.length; i++) {
                        var px = (editor.points[i].temp - 30) / 70 * w
                        var py = h - (editor.points[i].speed / 100) * h
                        if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py)
                    }
                    ctx.stroke()
                }

                Connections { target: editor; function onPointsChanged() { canvas.requestPaint() } }

                Repeater {
                    model: editor.points
                    Rectangle {
                        id: handle
                        required property var modelData
                        required property int index
                        width: Style.space(10); height: Style.space(10); radius: Style.space(5)
                        color: editor.enabledState ? editor.accent : Qt.rgba(editor.foreground.r, editor.foreground.g, editor.foreground.b, 0.4)
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.3)
                        x: (modelData.temp - 30) / 70 * canvas.width - width / 2
                        y: canvas.height - (modelData.speed / 100) * canvas.height - height / 2

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Style.space(4)
                            enabled: editor.interactive
                            cursorShape: Qt.PointingHandCursor
                            drag.target: handle
                            drag.axis: Drag.XAndYAxis
                            drag.minimumX: -handle.width / 2
                            drag.maximumX: canvas.width - handle.width / 2
                            drag.minimumY: -handle.height / 2
                            drag.maximumY: canvas.height - handle.height / 2
                            onPositionChanged: {
                                if (!drag.active) return
                                var temp = (handle.x + handle.width / 2) / canvas.width * 70 + 30
                                var speed = (1 - (handle.y + handle.height / 2) / canvas.height) * 100
                                editor.points = Model.moveFanPoint(editor.points, index, temp, speed)
                            }
                            onReleased: editor.commit(editor.points)
                        }
                    }
                }
            }

            Text {
                anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.margins: Style.space(2)
                text: editor.points.length + " pts"
                color: Qt.darker(editor.foreground, 1.6)
                font.family: editor.fontFamily
                font.pixelSize: 8
            }
        }

        Row {
            width: parent.width
            Item { width: parent.width - resetBtn.width; height: 1 }
            Button {
                id: resetBtn
                text: "Reset"
                fontSize: Style.font.caption
                foreground: editor.foreground
                fontFamily: editor.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                onClicked: editor.reset()
            }
        }
    }

    property string currentProfile: ""
    property bool profileLoaded: false
    property bool infoLoaded: false
    property var profiles: ["Quiet", "Balanced", "Performance"]
    property int profileIndex: 1
    property var acProfile: ({ ac: "", battery: "" })
    property var supported: ({ hasAura: false, hasFanCurve: false, hasBattery: false, hasProfile: false, auraModes: [] })
    property bool fanCurveEnabled: false
    property int batteryLimit: 100
    property bool asusctlAvailable: false
    property bool cursorActive: false

    // ---- Tabs -----------------------------------------------------------
    property string tabKey: "main"
    readonly property var tabs: {
        var t = [{ key: "main", label: "Main" }]
        if (root.supported.hasAura || !root.infoLoaded) t.push({ key: "rgb", label: "RGB" })
        if (root.supported.hasFanCurve || !root.infoLoaded) t.push({ key: "fan", label: "Fan" })
        t.push({ key: "advanced", label: "Advanced" })
        return t
    }
    readonly property int tabIndex: { for (var i = 0; i < tabs.length; i++) if (tabs[i].key === tabKey) return i; return 0 }
    function selectTab(index) {
        if (tabs.length === 0) return
        var n = tabs.length, i = ((index % n) + n) % n
        tabKey = tabs[i].key
    }

    // RGB
    property string currentEffect: "static"
    property int colorR: 255
    property int colorG: 0
    property int colorB: 0
    property int color2R: 0
    property int color2G: 0
    property int color2B: 255
    property string currentSpeed: "med"
    property string currentDirection: "left"
    property bool ledAwake: true
    property string ledBrightness: "med"
    readonly property string colorHex: Model.rgbToHex(colorR, colorG, colorB)
    readonly property string color2Hex: Model.rgbToHex(color2R, color2G, color2B)
    readonly property color liveColor: Qt.rgba(colorR / 255, colorG / 255, colorB / 255, 1)
    readonly property color liveColor2: Qt.rgba(color2R / 255, color2G / 255, color2B / 255, 1)

    readonly property var auraSupportedEffects: Model.supportedEffects(root.supported.auraModes)
    readonly property var effectDef: { for (var i = 0; i < Model.effects.length; i++) { if (Model.effects[i].id === currentEffect) return Model.effects[i] }; return Model.effects[0] }
    readonly property bool needsColor: effectDef.params.indexOf("color") >= 0
    readonly property bool needsColor2: effectDef.params.indexOf("color2") >= 0
    readonly property bool needsSpeed: effectDef.params.indexOf("speed") >= 0
    readonly property bool needsDirection: effectDef.params.indexOf("direction") >= 0

    // Fan curves
    property bool cpuFanEnabled: false
    property bool gpuFanEnabled: false
    property bool midFanEnabled: false
    property bool hasMidFan: false
    property var cpuFanPoints: []
    property var gpuFanPoints: []
    property var midFanPoints: []

    // Armoury — armourySupported gates each Advanced control per-model, since
    // `asusctl armoury list` only reports attributes the running laptop
    // actually exposes (no dGPU / no panel overdrive on some models).
    property var armourySupported: ({ panelOverdrive: false, gpuMux: false, dgpuDisable: false, pptPl1: false, pptPl2: false, nvDynBoost: false, nvTempTarget: false })
    property bool panelOverdrive: false
    property bool gpuMux: false
    property bool dgpuDisable: false
    property int pptPl1: 115
    property int pptPl1Min: 25
    property int pptPl1Max: 45
    property int pptPl2: 135
    property int pptPl2Min: 35
    property int pptPl2Max: 60
    property int nvDynBoost: 25
    property int nvTempTarget: 87

    readonly property bool showBatteryLimit: setting("showBatteryLimit", true) === true
    readonly property int refreshInterval: Math.max(5, Math.min(60, Number(setting("refreshIntervalSec", 10)) || 10)) * 1000

    function refresh() {
        if (!asusctlAvailable) { checkAsusctl.running = true; return }
        if (!profileProc.running) profileProc.running = true
        if (!infoProc.running) infoProc.running = true
        if (supported.hasBattery && !batteryProc.running) batteryProc.running = true
        if (!ledProc.running) ledProc.running = true
        if (!armouryProc.running) armouryProc.running = true
        if (supported.hasFanCurve) { if (!fanDetailProc.running) fanDetailProc.running = true }
    }

    function setProfile(p) { if (!p || actionProc.running) return; actionProc.command = ["asusctl", "profile", "set", p]; actionProc.running = true }
    function cycleProfile(d) { profileIndex = Model.selectProfileIndex(profileIndex, d, profiles); setProfile(profiles[profileIndex]) }

    function applyEffect() {
        if (!supported.hasAura) return
        var params = {}
        if (needsColor) params.color = colorHex
        if (needsColor2) params.color2 = color2Hex
        if (needsSpeed) params.speed = currentSpeed
        if (needsDirection) params.direction = currentDirection
        actionProc.command = Model.buildAuraCommand(currentEffect, params); actionProc.running = true
    }
    function selectEffect(id) { currentEffect = id; applyEffect() }
    function setPresetColor(hex) { var r = Model.hexToRgb(hex); colorR = r.r; colorG = r.g; colorB = r.b; applyEffect() }
    function setPresetColor2(hex) { var r = Model.hexToRgb(hex); color2R = r.r; color2G = r.g; color2B = r.b; applyEffect() }

    function setLedPower(on) { ledAwake = on; actionProc.command = ["asusctl", "aura", "power-tuf", "--awake", on ? "true" : "false", "--keyboard"]; actionProc.running = true }
    function setLedBrightness(level) { ledBrightness = level; actionProc.command = ["asusctl", "leds", "set", level]; actionProc.running = true }
    function setBatteryLimit(l) { if (!supported.hasBattery) return; var c = Math.max(20, Math.min(100, Math.round(l))); actionProc.command = ["asusctl", "battery", "limit", String(c)]; actionProc.running = true }

    // Fan curves — every write is gated on profileLoaded so an action never
    // silently lands on the wrong (hardcoded "Balanced") profile because the
    // real active profile hadn't loaded yet. This was the root cause of fan
    // controls appearing to "not work sometimes".
    function toggleFanCurves() { if (!supported.hasFanCurve || !profileLoaded) return; var n = !fanCurveEnabled; var p = currentProfile || "Balanced"; actionProc.command = ["asusctl", "fan-curve", "--mod-profile", p, "--enable-fan-curves", n ? "true" : "false"]; actionProc.running = true }
    function toggleCpuFan() { if (!profileLoaded) return; var n = !cpuFanEnabled; var p = currentProfile || "Balanced"; actionProc.command = ["asusctl", "fan-curve", "--mod-profile", p, "--enable-fan-curve", n ? "true" : "false", "--fan", "cpu"]; actionProc.running = true }
    function toggleGpuFan() { if (!profileLoaded) return; var n = !gpuFanEnabled; var p = currentProfile || "Balanced"; actionProc.command = ["asusctl", "fan-curve", "--mod-profile", p, "--enable-fan-curve", n ? "true" : "false", "--fan", "gpu"]; actionProc.running = true }
    function toggleMidFan() { if (!profileLoaded || !hasMidFan) return; var n = !midFanEnabled; var p = currentProfile || "Balanced"; actionProc.command = ["asusctl", "fan-curve", "--mod-profile", p, "--enable-fan-curve", n ? "true" : "false", "--fan", "mid"]; actionProc.running = true }
    function resetFanCurves() { if (!profileLoaded) return; var p = currentProfile || "Balanced"; actionProc.command = ["asusctl", "fan-curve", "--mod-profile", p, "--default"]; actionProc.running = true }
    function applyFanCurve(fan, points) {
        if (!profileLoaded || actionProc.running) return
        var p = currentProfile || "Balanced"
        actionProc.command = ["asusctl", "fan-curve", "--mod-profile", p, "--fan", fan, "--data", Model.serializeFanPoints(points)]
        actionProc.running = true
    }

    function setArmouryAttr(a, v) { actionProc.command = ["asusctl", "armoury", "set", a, String(v)]; actionProc.running = true }
    function togglePanelOverdrive() { panelOverdrive = !panelOverdrive; setArmouryAttr("panel_overdrive", panelOverdrive ? 1 : 0) }
    function toggleGpuMux() { gpuMux = !gpuMux; setArmouryAttr("gpu_mux_mode", gpuMux ? 1 : 0) }
    function toggleDgpuDisable() { dgpuDisable = !dgpuDisable; setArmouryAttr("dgpu_disable", dgpuDisable ? 1 : 0) }
    function setPptPl1(v) { pptPl1 = Math.round(v); setArmouryAttr("ppt_pl1_spl", pptPl1) }
    function setPptPl2(v) { pptPl2 = Math.round(v); setArmouryAttr("ppt_pl2_sppt", pptPl2) }
    function setNvDynBoost(v) { nvDynBoost = Math.round(v); setArmouryAttr("nv_dynamic_boost", nvDynBoost) }
    function setNvTempTarget(v) { nvTempTarget = Math.round(v); setArmouryAttr("nv_temp_target", nvTempTarget) }

    visible: asusctlAvailable
    implicitWidth: asusctlAvailable ? button.implicitWidth : 0
    implicitHeight: asusctlAvailable ? button.implicitHeight : 0

    BarIconButton {
        id: button; anchors.fill: parent; bar: root.bar
        text: Model.profileIcon(currentProfile); slotSize: Style.bar.iconSlot
        tooltipText: "ASUS — " + Model.profileLabel(currentProfile)
        onPressed: function(b) { root.toggle() }
    }

    KeyboardPanel {
        id: panel; anchorItem: button; owner: root; bar: root.bar
        open: root.opened && root.asusctlAvailable; focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(360))
        contentHeight: panel.fittedContentHeight(scrollCol.implicitHeight)

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: Style.space(12)
            contentHeight: scrollCol.implicitHeight
            clip: true
            flickableDirection: Flickable.VerticalFlick

            Column {
                id: scrollCol
                width: parent.width
                spacing: Style.space(12)

                // HERO
                Item { width: parent.width; implicitHeight: Math.max(hIcon.implicitHeight, hLabels.implicitHeight)
                    Text { id: hIcon; text: "\u{F14C0}"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.display; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
                    Column { id: hLabels; anchors.left: hIcon.right; anchors.leftMargin: Style.space(14); anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(2)
                        Text { text: "ASUS Control"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.title; font.bold: true; elide: Text.ElideRight; width: parent.width }
                        Text { text: Model.profileLabel(root.currentProfile).toUpperCase(); color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.2 }
                    }
                }

                PanelSeparator { foreground: root.bar.foreground }

                // TABS
                Row {
                    id: tabRow
                    width: parent.width
                    spacing: Style.space(4)
                    readonly property real cellWidth: root.tabs.length > 0 ? (width - spacing * (root.tabs.length - 1)) / root.tabs.length : 0
                    Repeater {
                        model: root.tabs
                        Button {
                            required property var modelData
                            required property int index
                            width: tabRow.cellWidth
                            text: modelData.label
                            fontSize: Style.font.bodySmall
                            foreground: root.bar.foreground
                            fontFamily: root.bar.fontFamily
                            horizontalPadding: Style.spacing.controlPaddingX
                            verticalPadding: Style.spacing.controlPaddingY
                            bordered: true
                            active: root.tabIndex === index
                            onClicked: root.selectTab(index)
                        }
                    }
                }

                Loader { width: parent.width; active: root.tabKey === "main"; visible: active; sourceComponent: mainTab }
                Loader { width: parent.width; active: root.tabKey === "rgb"; visible: active; sourceComponent: rgbTab }
                Loader { width: parent.width; active: root.tabKey === "fan"; visible: active; sourceComponent: fanTab }
                Loader { width: parent.width; active: root.tabKey === "advanced"; visible: active; sourceComponent: advancedTab }
            }
        }

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onMoveRequested: function(dx, dy) { if (dy !== 0) flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY - dy * 40)) }
        }
    }

    // ============================================================ MAIN TAB
    Component {
        id: mainTab
        Column { width: parent.width; spacing: Style.space(12)

            Column { width: parent.width; spacing: Style.space(8)
                PanelSectionHeader { text: "POWER PROFILE"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
                Row { id: pRow; width: parent.width; spacing: Style.space(4); readonly property real cw: root.profiles.length > 0 ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length : 0
                    Repeater { model: root.profiles
                        Button { required property var modelData; required property int index; width: pRow.cw; iconText: Model.profileIcon(String(modelData)); iconSize: Style.font.title; text: String(modelData); fontSize: Style.font.bodySmall; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.currentProfile === modelData; hasCursor: root.cursorActive && root.profileIndex === index; onClicked: root.setProfile(modelData); onHovered: function(h) { if (h) { root.cursorActive = true; root.profileIndex = index } } }
                    }
                }
            }

            Column { visible: root.supported.hasBattery && root.showBatteryLimit; width: parent.width; spacing: Style.space(8)
                PanelSeparator { foreground: root.bar.foreground }
                PanelSectionHeader { text: "BATTERY CHARGE LIMIT"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
                Row { width: parent.width; spacing: Style.space(4)
                    PanelSlider { width: parent.width - Style.space(32); bar: root.bar; minimum: 20; maximum: 100; step: 5; integer: true; value: root.batteryLimit; tickCount: 9; onReleased: function(v) { root.setBatteryLimit(Math.round(v)) } }
                    Text { text: root.batteryLimit + "%"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body; font.bold: true; width: Style.space(32); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                }
                Row { width: parent.width; spacing: Style.space(4)
                    Repeater { model: [20, 40, 60, 80, 100]
                        Button { required property var modelData; width: (parent.width - Style.space(4) * 4) / 5; text: modelData + "%"; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.batteryLimit === modelData; onClicked: root.setBatteryLimit(modelData) }
                    }
                }
            }
        }
    }

    // ============================================================= RGB TAB
    Component {
        id: rgbTab
        Column { width: parent.width; spacing: Style.space(8)
            // Header with LED toggle
            Row { width: parent.width
                Text { text: "KEYBOARD RGB"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true; anchors.verticalCenter: parent.verticalCenter; width: parent.width - ledSw.width - Style.space(8) }
                Row { id: ledSw; spacing: Style.space(4); anchors.verticalCenter: parent.verticalCenter
                    Rectangle { width: Style.space(14); height: Style.space(14); radius: Style.space(7); color: root.ledAwake ? "#44cc44" : "#cc4444"; anchors.verticalCenter: parent.verticalCenter
                        SequentialAnimation on opacity { running: root.ledAwake; loops: Animation.Infinite; NumberAnimation { from: 1; to: 0.5; duration: 800 } NumberAnimation { from: 0.5; to: 1; duration: 800 } }
                    }
                    Text { text: root.ledAwake ? "ON" : "OFF"; color: root.ledAwake ? "#44cc44" : "#cc4444"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                    MouseArea { width: Style.space(40); height: Style.space(20); anchors.verticalCenter: parent.verticalCenter; cursorShape: Qt.PointingHandCursor; onClicked: root.setLedPower(!root.ledAwake) }
                }
            }
            // Effect grid — only modes this laptop's asusctl actually reports supporting.
            Grid { width: parent.width; columns: 3; spacing: Style.space(3)
                Repeater { model: root.auraSupportedEffects
                    Rectangle { required property var modelData; width: (parent.width - Style.space(3) * 2) / 3; height: Style.space(40); radius: Style.cornerRadius; color: root.currentEffect === modelData.id ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.2) : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.06); border.width: root.currentEffect === modelData.id ? 2 : 1; border.color: root.currentEffect === modelData.id ? root.bar.foreground : "transparent"
                        Row { anchors.centerIn: parent; spacing: Style.space(4)
                            Text { text: modelData.icon; color: root.currentEffect === modelData.id ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
                            Text { text: modelData.name; color: root.currentEffect === modelData.id ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.selectEffect(modelData.id) }
                    }
                }
            }
            // Effect params
            Column { visible: root.needsColor || root.needsColor2 || root.needsSpeed || root.needsDirection; width: parent.width; spacing: Style.space(6)
                Column { visible: root.needsColor; width: parent.width; spacing: Style.space(4)
                    Row { width: parent.width; spacing: Style.space(6)
                        Rectangle { width: Style.space(20); height: Style.space(20); radius: Style.space(10); color: root.liveColor; border.width: 1; border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.3); anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Color  #" + root.colorHex.toUpperCase(); color: root.bar.foreground; font.family: "monospace"; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                        Item { width: parent.width - Style.space(20) - Style.space(60) - Style.space(6) * 2; height: 1 }
                        Button { text: "Set"; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: true; anchors.verticalCenter: parent.verticalCenter; onClicked: root.applyEffect() }
                    }
                    Row { width: parent.width; spacing: Style.space(4)
                        Text { text: "R"; color: "#ff4444"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                        PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.colorR; fillColor: Qt.rgba(1, 0.2, 0.2, 1); knobColor: Qt.rgba(1, 0.3, 0.3, 1); onReleased: function(v) { root.colorR = Math.round(v) } }
                        Text { text: root.colorR; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Row { width: parent.width; spacing: Style.space(4)
                        Text { text: "G"; color: "#44cc44"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                        PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.colorG; fillColor: Qt.rgba(0.2, 1, 0.2, 1); knobColor: Qt.rgba(0.3, 1, 0.3, 1); onReleased: function(v) { root.colorG = Math.round(v) } }
                        Text { text: root.colorG; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Row { width: parent.width; spacing: Style.space(4)
                        Text { text: "B"; color: "#4488ff"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                        PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.colorB; fillColor: Qt.rgba(0.2, 0.2, 1, 1); knobColor: Qt.rgba(0.3, 0.3, 1, 1); onReleased: function(v) { root.colorB = Math.round(v) } }
                        Text { text: root.colorB; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                Column { visible: root.needsColor2; width: parent.width; spacing: Style.space(4)
                    Row { width: parent.width; spacing: Style.space(6)
                        Rectangle { width: Style.space(20); height: Style.space(20); radius: Style.space(10); color: root.liveColor2; border.width: 1; border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.3); anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Color 2  #" + root.color2Hex.toUpperCase(); color: root.bar.foreground; font.family: "monospace"; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Row { width: parent.width; spacing: Style.space(4)
                        Text { text: "R"; color: "#ff4444"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                        PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.color2R; fillColor: Qt.rgba(1, 0.2, 0.2, 1); knobColor: Qt.rgba(1, 0.3, 0.3, 1); onReleased: function(v) { root.color2R = Math.round(v) } }
                        Text { text: root.color2R; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Row { width: parent.width; spacing: Style.space(4)
                        Text { text: "G"; color: "#44cc44"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                        PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.color2G; fillColor: Qt.rgba(0.2, 1, 0.2, 1); knobColor: Qt.rgba(0.3, 1, 0.3, 1); onReleased: function(v) { root.color2G = Math.round(v) } }
                        Text { text: root.color2G; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Row { width: parent.width; spacing: Style.space(4)
                        Text { text: "B"; color: "#4488ff"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                        PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.color2B; fillColor: Qt.rgba(0.2, 0.2, 1, 1); knobColor: Qt.rgba(0.3, 0.3, 1, 1); onReleased: function(v) { root.color2B = Math.round(v) } }
                        Text { text: root.color2B; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                Row { visible: root.needsSpeed; width: parent.width; spacing: Style.space(4)
                    Text { text: "Speed"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter; width: Style.space(40) }
                    Repeater { model: Model.speeds
                        Button { required property var modelData; width: (parent.width - Style.space(40) - Style.space(4) * 2) / 3; text: Model.speedLabels[modelData]; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.currentSpeed === modelData; onClicked: { root.currentSpeed = modelData; root.applyEffect() } }
                    }
                }
                Row { visible: root.needsDirection; width: parent.width; spacing: Style.space(4)
                    Text { text: "Dir"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter; width: Style.space(40) }
                    Repeater { model: Model.directions
                        Button { required property var modelData; width: (parent.width - Style.space(40) - Style.space(4) * 3) / 4; text: modelData.charAt(0).toUpperCase() + modelData.slice(1); fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.currentDirection === modelData; onClicked: { root.currentDirection = modelData; root.applyEffect() } }
                    }
                }
                Grid { visible: root.needsColor; width: parent.width; columns: 6; spacing: Style.space(3)
                    Repeater {
                        model: ["ff0000", "ff8800", "ffff00", "00ff00", "00ffff", "0088ff", "aa00ff", "ff00ff", "ffffff", "ffaa44", "44ccff", "88ff00"]
                        Rectangle {
                            required property string modelData
                            property color swatchColor: Qt.rgba(
                                parseInt(modelData.substring(0, 2), 16) / 255,
                                parseInt(modelData.substring(2, 4), 16) / 255,
                                parseInt(modelData.substring(4, 6), 16) / 255,
                                1
                            )
                            width: (parent.width - Style.space(3) * 5) / 6
                            height: Style.space(22)
                            radius: Style.space(4)
                            color: swatchColor
                            border.width: root.colorHex === modelData ? 2 : 1
                            border.color: root.colorHex === modelData ? root.bar.foreground : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.15)
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setPresetColor(modelData) }
                        }
                    }
                }
            }
            // LED Brightness
            Column { width: parent.width; spacing: Style.space(4)
                Text { text: "LED Brightness"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                Row { width: parent.width; spacing: Style.space(4)
                    Repeater { model: ["off", "low", "med", "high"]
                        Button { required property var modelData; width: (parent.width - Style.space(4) * 3) / 4; text: modelData.charAt(0).toUpperCase() + modelData.slice(1); fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.ledBrightness === modelData; onClicked: root.setLedBrightness(modelData) }
                    }
                }
            }
        }
    }

    // ============================================================= FAN TAB
    Component {
        id: fanTab
        Column { width: parent.width; spacing: Style.space(10)

            Row { width: parent.width
                Text { text: "CUSTOM FAN CURVES"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true; anchors.verticalCenter: parent.verticalCenter; width: parent.width - masterSw.width - resetAllBtn.width - Style.space(16) }
                Rectangle { id: masterSw; width: Style.space(48); height: Style.space(20); radius: Style.space(10); anchors.verticalCenter: parent.verticalCenter; color: root.fanCurveEnabled ? Qt.rgba(0.27, 0.8, 0.27, 0.3) : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08)
                    MouseArea { anchors.fill: parent; enabled: root.profileLoaded; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleFanCurves() }
                    Text { text: root.fanCurveEnabled ? "ON" : "OFF"; color: root.fanCurveEnabled ? "#44cc44" : Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.centerIn: parent }
                }
                Button { id: resetAllBtn; text: "Reset all"; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: Style.space(6); onClicked: root.resetFanCurves() }
            }
            Text { visible: !root.fanCurveEnabled; width: parent.width; text: "Turn this on to enable per-fan custom curves below."; wrapMode: Text.WordWrap; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }

            // CPU Fan
            Column { width: parent.width; spacing: Style.space(4); opacity: root.fanCurveEnabled ? 1 : 0.5
                Row { width: parent.width; spacing: Style.space(8)
                    Rectangle { width: Style.space(12); height: Style.space(12); radius: Style.space(6); color: root.cpuFanEnabled ? "#44cc44" : "#666"; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "CPU Fan"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; anchors.verticalCenter: parent.verticalCenter; width: parent.width - Style.space(60) }
                    Rectangle { width: Style.space(48); height: Style.space(20); radius: Style.space(10); color: root.cpuFanEnabled ? Qt.rgba(0.27, 0.8, 0.27, 0.3) : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08); anchors.verticalCenter: parent.verticalCenter
                        MouseArea { anchors.fill: parent; enabled: root.fanCurveEnabled; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleCpuFan() }
                        Text { text: root.cpuFanEnabled ? "ON" : "OFF"; color: root.cpuFanEnabled ? "#44cc44" : Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.centerIn: parent }
                    }
                }
                FanCurveEditor {
                    width: parent.width
                    points: root.cpuFanPoints
                    enabledState: root.cpuFanEnabled
                    interactive: root.fanCurveEnabled
                    accent: "#44cc44"
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    onCommit: function(pts) { root.cpuFanPoints = pts; root.applyFanCurve("cpu", pts) }
                    onReset: root.resetFanCurves()
                }
            }
            // GPU Fan
            Column { width: parent.width; spacing: Style.space(4); opacity: root.fanCurveEnabled ? 1 : 0.5
                Row { width: parent.width; spacing: Style.space(8)
                    Rectangle { width: Style.space(12); height: Style.space(12); radius: Style.space(6); color: root.gpuFanEnabled ? "#4488ff" : "#666"; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "GPU Fan"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; anchors.verticalCenter: parent.verticalCenter; width: parent.width - Style.space(60) }
                    Rectangle { width: Style.space(48); height: Style.space(20); radius: Style.space(10); color: root.gpuFanEnabled ? Qt.rgba(0.27, 0.53, 1, 0.3) : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08); anchors.verticalCenter: parent.verticalCenter
                        MouseArea { anchors.fill: parent; enabled: root.fanCurveEnabled; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleGpuFan() }
                        Text { text: root.gpuFanEnabled ? "ON" : "OFF"; color: root.gpuFanEnabled ? "#4488ff" : Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.centerIn: parent }
                    }
                }
                FanCurveEditor {
                    width: parent.width
                    points: root.gpuFanPoints
                    enabledState: root.gpuFanEnabled
                    interactive: root.fanCurveEnabled
                    accent: "#4488ff"
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    onCommit: function(pts) { root.gpuFanPoints = pts; root.applyFanCurve("gpu", pts) }
                    onReset: root.resetFanCurves()
                }
            }
            // Mid Fan — only laptops with a third fan report this.
            Column { visible: root.hasMidFan; width: parent.width; spacing: Style.space(4); opacity: root.fanCurveEnabled ? 1 : 0.5
                Row { width: parent.width; spacing: Style.space(8)
                    Rectangle { width: Style.space(12); height: Style.space(12); radius: Style.space(6); color: root.midFanEnabled ? "#cc9944" : "#666"; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Mid Fan"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; anchors.verticalCenter: parent.verticalCenter; width: parent.width - Style.space(60) }
                    Rectangle { width: Style.space(48); height: Style.space(20); radius: Style.space(10); color: root.midFanEnabled ? Qt.rgba(0.8, 0.6, 0.27, 0.3) : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08); anchors.verticalCenter: parent.verticalCenter
                        MouseArea { anchors.fill: parent; enabled: root.fanCurveEnabled; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleMidFan() }
                        Text { text: root.midFanEnabled ? "ON" : "OFF"; color: root.midFanEnabled ? "#cc9944" : Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.centerIn: parent }
                    }
                }
                FanCurveEditor {
                    width: parent.width
                    points: root.midFanPoints
                    enabledState: root.midFanEnabled
                    interactive: root.fanCurveEnabled
                    accent: "#cc9944"
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    onCommit: function(pts) { root.midFanPoints = pts; root.applyFanCurve("mid", pts) }
                    onReset: root.resetFanCurves()
                }
            }
        }
    }

    // ======================================================== ADVANCED TAB
    Component {
        id: advancedTab
        Column { width: parent.width; spacing: Style.space(8)
            Text { width: parent.width; text: "Firmware limits. Only the controls this laptop actually reports are shown."; wrapMode: Text.WordWrap; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
            Toggle { visible: root.armourySupported.panelOverdrive; width: parent.width; label: "Panel Overdrive"; description: "Faster display response"; checked: root.panelOverdrive; foreground: root.bar.foreground; accent: Color.accent; fontFamily: root.bar.fontFamily; onClicked: root.togglePanelOverdrive() }
            Toggle { visible: root.armourySupported.gpuMux; width: parent.width; label: "GPU MUX Switch"; description: root.gpuMux ? "dGPU only" : "Hybrid (Optimus)"; checked: root.gpuMux; foreground: root.bar.foreground; accent: Color.accent; fontFamily: root.bar.fontFamily; onClicked: root.toggleGpuMux() }
            Toggle { visible: root.armourySupported.dgpuDisable; width: parent.width; label: "Disable dGPU"; description: "Turn off discrete GPU"; checked: root.dgpuDisable; foreground: root.bar.foreground; accent: Color.accent; fontFamily: root.bar.fontFamily; onClicked: root.toggleDgpuDisable() }
            Column { visible: root.armourySupported.pptPl1 || root.armourySupported.pptPl2; width: parent.width; spacing: Style.space(4)
                Text { text: "CPU Power"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                Row { visible: root.armourySupported.pptPl1; width: parent.width; spacing: Style.space(4)
                    Text { text: "PL1"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); anchors.verticalCenter: parent.verticalCenter }
                    PanelSlider { width: parent.width - Style.space(24) - Style.space(32) - Style.space(4) * 2; bar: root.bar; minimum: root.pptPl1Min; maximum: root.pptPl1Max; step: 1; integer: true; value: root.pptPl1; onReleased: function(v) { root.setPptPl1(v) } }
                    Text { text: root.pptPl1 + "W"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(32); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                }
                Row { visible: root.armourySupported.pptPl2; width: parent.width; spacing: Style.space(4)
                    Text { text: "PL2"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); anchors.verticalCenter: parent.verticalCenter }
                    PanelSlider { width: parent.width - Style.space(24) - Style.space(32) - Style.space(4) * 2; bar: root.bar; minimum: root.pptPl2Min; maximum: root.pptPl2Max; step: 1; integer: true; value: root.pptPl2; onReleased: function(v) { root.setPptPl2(v) } }
                    Text { text: root.pptPl2 + "W"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(32); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            Column { visible: root.armourySupported.nvDynBoost || root.armourySupported.nvTempTarget; width: parent.width; spacing: Style.space(4)
                Text { text: "GPU Power"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                Row { visible: root.armourySupported.nvDynBoost; width: parent.width; spacing: Style.space(4)
                    Text { text: "Boost"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); anchors.verticalCenter: parent.verticalCenter }
                    PanelSlider { width: parent.width - Style.space(24) - Style.space(32) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 25; step: 1; integer: true; value: root.nvDynBoost; onReleased: function(v) { root.setNvDynBoost(v) } }
                    Text { text: root.nvDynBoost + "W"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(32); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                }
                Row { visible: root.armourySupported.nvTempTarget; width: parent.width; spacing: Style.space(4)
                    Text { text: "Temp"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); anchors.verticalCenter: parent.verticalCenter }
                    PanelSlider { width: parent.width - Style.space(24) - Style.space(32) - Style.space(4) * 2; bar: root.bar; minimum: 75; maximum: 87; step: 1; integer: true; value: root.nvTempTarget; onReleased: function(v) { root.setNvTempTarget(v) } }
                    Text { text: root.nvTempTarget + "°C"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(32); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }
    }

    IpcHandler { target: "io.github.moneytosms.asus"; function open() { root.open() } function close() { root.close() } function show() { root.open() } function hide() { root.close() } function toggle() { root.toggle() } function refresh() { root.refresh() } }
    onOpenedChanged: { if (opened) { Qt.callLater(refresh); cursorActive = false } }
    Component.onCompleted: { checkAsusctl.running = true }

    Process { id: checkAsusctl; command: ["which", "asusctl"]; onExited: function(ec) { root.asusctlAvailable = ec === 0; if (root.asusctlAvailable) refresh() } }
    Process { id: profileProc; command: ["asusctl", "profile", "get"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { var p = Model.parseCurrentProfile(text); if (p) { root.currentProfile = p; var i = root.profiles.indexOf(p); if (i >= 0) root.profileIndex = i }; root.acProfile = Model.parseProfiles(text); root.profileLoaded = true } } }
    Process { id: infoProc; command: ["asusctl", "info", "--show-supported"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { root.supported = Model.parseSupportedFeatures(text); root.infoLoaded = true } } }
    Process { id: batteryProc; command: ["asusctl", "battery", "info"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { root.batteryLimit = Model.parseBatteryInfo(text).limit } } }
    Process { id: ledProc; command: ["asusctl", "leds", "get"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { root.ledBrightness = Model.parseLedBrightness(text) } } }
    Process {
        id: fanDetailProc
        command: ["asusctl", "fan-curve", "--get-enabled"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var info = Model.parseFanCurves(text)
                root.cpuFanEnabled = info.cpuEnabled
                root.gpuFanEnabled = info.gpuEnabled
                root.hasMidFan = info.hasMid
                root.midFanEnabled = info.midEnabled
                root.cpuFanPoints = info.cpuPoints
                root.gpuFanPoints = info.gpuPoints
                root.midFanPoints = info.midPoints
                root.fanCurveEnabled = info.cpuEnabled || info.gpuEnabled || (info.hasMid && info.midEnabled)
                // Also fetch detailed curve data
                if (!fanModProc.running) fanModProc.running = true
            }
        }
    }
    Process {
        id: fanModProc
        command: ["asusctl", "fan-curve", "--mod-profile", root.currentProfile || "Balanced"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var info = Model.parseFanCurves(text)
                if (info.cpuPoints.length > 0) root.cpuFanPoints = info.cpuPoints
                if (info.gpuPoints.length > 0) root.gpuFanPoints = info.gpuPoints
                if (info.midPoints.length > 0) { root.midFanPoints = info.midPoints; root.hasMidFan = true }
            }
        }
    }
    Process { id: armouryProc; command: ["asusctl", "armoury", "list"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
        root.armourySupported = Model.parseArmourySupported(text)
        var lines = text.split("\n"), cur = ""
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i].trim()
            if (l.indexOf(":") >= 0 && l.indexOf("current") < 0 && l.indexOf("default") < 0 && l.indexOf("Multiple") < 0 && l.indexOf("devices") < 0) cur = l.replace(":", "").trim()
            if (l.indexOf("current:") >= 0 && cur) {
                var v = l.substring(l.indexOf("current:") + 8).trim()
                if (cur === "panel_overdrive") { var t = Model.parseArmouryValue(v); if (t) root.panelOverdrive = t.value === (t.on || 1) }
                else if (cur === "gpu_mux_mode") { var t2 = Model.parseArmouryValue(v); if (t2) root.gpuMux = t2.value === (t2.on || 1) }
                else if (cur === "dgpu_disable") { var t3 = Model.parseArmouryValue(v); if (t3) root.dgpuDisable = t3.value === (t3.on || 1) }
                else if (cur === "ppt_pl1_spl") { var t4 = Model.parseArmouryValue(v); if (t4 && t4.type === "range") { root.pptPl1 = t4.value; root.pptPl1Min = t4.min; root.pptPl1Max = t4.max } }
                else if (cur === "ppt_pl2_sppt") { var t5 = Model.parseArmouryValue(v); if (t5 && t5.type === "range") { root.pptPl2 = t5.value; root.pptPl2Min = t5.min; root.pptPl2Max = t5.max } }
                else if (cur === "nv_dynamic_boost") { var t6 = Model.parseArmouryValue(v); if (t6 && t6.type === "range") root.nvDynBoost = t6.value }
                else if (cur === "nv_temp_target") { var t7 = Model.parseArmouryValue(v); if (t7 && t7.type === "range") root.nvTempTarget = t7.value }
                cur = ""
            }
        }
    } } }
    Process { id: actionProc; onExited: function() { if (!profileProc.running) profileProc.running = true; if (!batteryProc.running) batteryProc.running = true; if (!ledProc.running) ledProc.running = true; if (!armouryProc.running) armouryProc.running = true; if (!fanDetailProc.running) fanDetailProc.running = true } }
    Timer { interval: root.refreshInterval; running: root.opened && root.asusctlAvailable; repeat: true; onTriggered: root.refresh() }
}

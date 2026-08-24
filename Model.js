// Model.js — asusctl v6.x command wrappers and data parsing

// ============================================================
// Effect definitions
// ============================================================
// `auraName` matches the strings asusctl reports under "Supported Aura
// Modes:" (from `asusctl info --show-supported`) — used to hide effects the
// current hardware doesn't actually support, instead of listing all twelve
// regardless of model.
var effects = [
    { id: "static",        name: "Static",        auraName: "Static",       icon: "\u{F05A8}", params: ["color"] },
    { id: "breathe",       name: "Breathe",       auraName: "Breathe",      icon: "\u{F01C8}", params: ["color", "color2", "speed"] },
    { id: "pulse",         name: "Pulse",         auraName: "Pulse",        icon: "\u{F04DA}", params: ["color"] },
    { id: "rainbow-cycle", name: "Rainbow Cycle", auraName: "RainbowCycle", icon: "\u{F0764}", params: ["speed"] },
    { id: "rainbow-wave",  name: "Rainbow Wave",  auraName: "RainbowWave",  icon: "\u{F053E}", params: ["speed", "direction"] },
    { id: "stars",         name: "Stars",         auraName: "Stars",        icon: "\u{F0165}", params: ["color", "color2", "speed"] },
    { id: "rain",          name: "Rain",          auraName: "Rain",         icon: "\u{F0276}", params: ["speed"] },
    { id: "highlight",     name: "Highlight",     auraName: "Highlight",    icon: "\u{F030D}", params: ["color", "speed"] },
    { id: "laser",         name: "Laser",         auraName: "Laser",        icon: "\u{F0330}", params: ["color", "speed"] },
    { id: "ripple",        name: "Ripple",        auraName: "Ripple",       icon: "\u{F053E}", params: ["color", "speed"] },
    { id: "comet",         name: "Comet",         auraName: "Comet",        icon: "\u{F0361}", params: ["color"] },
    { id: "flash",         name: "Flash",         auraName: "Flash",        icon: "\u{F0192}", params: ["color"] }
]

function supportedEffects(auraModes) {
    if (!auraModes || auraModes.length === 0) return effects
    return effects.filter(function(e) { return auraModes.indexOf(e.auraName) >= 0 })
}

var speeds = ["low", "med", "high"]
var speedLabels = { low: "Slow", med: "Medium", high: "Fast" }
var directions = ["up", "down", "left", "right"]

function buildAuraCommand(effectId, params) {
    var cmd = ["asusctl", "aura", "effect", effectId]
    var effect = null
    for (var i = 0; i < effects.length; i++) { if (effects[i].id === effectId) { effect = effects[i]; break } }
    if (!effect) return cmd
    for (var j = 0; j < effect.params.length; j++) {
        var p = effect.params[j], val = params[p]
        if (val === undefined || val === null || val === "") continue
        if (p === "color")  { cmd.push("--colour"); cmd.push(String(val)) }
        if (p === "color2") { cmd.push("--colour2"); cmd.push(String(val)) }
        if (p === "speed")  { cmd.push("--speed"); cmd.push(String(val)) }
        if (p === "direction") { cmd.push("--direction"); cmd.push(String(val)) }
    }
    return cmd
}

// ============================================================
// Profile
// ============================================================
function profileIcon(name) {
    var n = String(name || "").toLowerCase()
    if (n.indexOf("quiet") >= 0 || n.indexOf("silent") >= 0) return "\u{F032A}"
    if (n.indexOf("balanced") >= 0) return "\u{F029A}"
    if (n.indexOf("performance") >= 0 || n.indexOf("turbo") >= 0) return "\u{F04C5}"
    return "\u{F0244}"
}

function profileLabel(name) {
    var n = String(name || "").toLowerCase()
    if (n.indexOf("quiet") >= 0 || n.indexOf("silent") >= 0) return "Quiet"
    if (n.indexOf("balanced") >= 0) return "Balanced"
    if (n.indexOf("performance") >= 0 || n.indexOf("turbo") >= 0) return "Performance"
    return name || "\u2014"
}

function parseCurrentProfile(raw) {
    var text = String(raw || "").trim()
    var idx = text.indexOf("Active profile:")
    if (idx >= 0) { var fl = text.substring(idx + 16).trim().split("\n")[0].trim(); if (fl) return fl }
    var lines = text.split("\n")
    if (lines.length > 0) { var parts = lines[0].trim().split(/\s+/); if (parts.length > 0) return parts[0] }
    return ""
}

function parseProfiles(raw) {
    var text = String(raw || "").trim()
    var r = { ac: "", battery: "" }
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
        var l = lines[i].trim()
        if (l.indexOf("AC profile") >= 0) r.ac = l.replace("AC profile", "").trim()
        if (l.indexOf("Battery profile") >= 0) r.battery = l.replace("Battery profile", "").trim()
    }
    return r
}

// ============================================================
// Feature detection
// ============================================================
function parseSupportedFeatures(raw) {
    var text = String(raw || "")
    return {
        hasAura: text.indexOf("Aura") >= 0,
        hasFanCurve: text.indexOf("FanCurves") >= 0,
        hasBattery: text.indexOf("battery") >= 0 || text.indexOf("Battery") >= 0,
        hasProfile: text.indexOf("Platform") >= 0,
        hasAniMe: text.indexOf("anime") >= 0,
        auraModes: parseListSection(text, "Supported Aura Modes:")
    }
}

// Pulls a bracketed list section out of `asusctl info --show-supported`, e.g.
//   Supported Aura Modes:
//   [
//       Static,
//       Breathe,
//   ]
// -> ["Static", "Breathe"]
function parseListSection(text, header) {
    var idx = text.indexOf(header)
    if (idx < 0) return []
    var rest = text.substring(idx + header.length)
    var open = rest.indexOf("[")
    var close = rest.indexOf("]")
    if (open < 0 || close < 0 || close < open) return []
    return rest.substring(open + 1, close).split(",")
        .map(function(s) { return s.trim() })
        .filter(function(s) { return s.length > 0 })
}

// Attribute names present in `asusctl armoury list` output — presence means
// this model actually exposes the control, independent of its current value.
// Mirrors the name-line detection in the armoury Process handler in Panel.qml.
function parseArmourySupported(raw) {
    var text = String(raw || "")
    var lines = text.split("\n")
    var names = {}
    for (var i = 0; i < lines.length; i++) {
        var l = lines[i].trim()
        if (l.length === 0 || l.indexOf(":") < 0) continue
        if (l.indexOf("current") >= 0 || l.indexOf("default") >= 0) continue
        if (l.indexOf("Multiple") >= 0 || l.indexOf("devices") >= 0) continue
        names[l.replace(":", "").trim()] = true
    }
    return {
        panelOverdrive: !!names["panel_overdrive"],
        gpuMux: !!names["gpu_mux_mode"],
        dgpuDisable: !!names["dgpu_disable"],
        pptPl1: !!names["ppt_pl1_spl"],
        pptPl2: !!names["ppt_pl2_sppt"],
        nvDynBoost: !!names["nv_dynamic_boost"],
        nvTempTarget: !!names["nv_temp_target"]
    }
}

// ============================================================
// Battery
// ============================================================
function parseBatteryInfo(raw) {
    var text = String(raw || "").trim()
    var r = { limit: 100 }
    var m = text.match(/(\d+)%/)
    if (m) r.limit = parseInt(m[1])
    return r
}

// ============================================================
// Fan curves — parse per-fan data from `asusctl fan-curve --get-enabled`
// and `asusctl fan-curve --mod-profile <name>`
// ============================================================
function parseFanCurves(raw) {
    var text = String(raw || "")
    var result = { cpuEnabled: false, gpuEnabled: false, midEnabled: false, hasMid: false, cpuPoints: [], gpuPoints: [], midPoints: [] }

    // Parse enabled state: "CPU: enabled: false, 40c:6%,..."
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (line.indexOf("CPU:") >= 0) {
            result.cpuEnabled = line.indexOf("enabled: true") >= 0
            // Extract curve points after the comma
            var idx = line.indexOf(",")
            if (idx >= 0) {
                var curveStr = line.substring(idx + 1).trim()
                result.cpuPoints = parseFanPoints(curveStr)
            }
        }
        if (line.indexOf("GPU:") >= 0) {
            result.gpuEnabled = line.indexOf("enabled: true") >= 0
            var idx2 = line.indexOf(",")
            if (idx2 >= 0) {
                var curveStr2 = line.substring(idx2 + 1).trim()
                result.gpuPoints = parseFanPoints(curveStr2)
            }
        }
        if (line.indexOf("MID:") >= 0) {
            result.hasMid = true
            result.midEnabled = line.indexOf("enabled: true") >= 0
            var idx3 = line.indexOf(",")
            if (idx3 >= 0) {
                var curveStr3 = line.substring(idx3 + 1).trim()
                result.midPoints = parseFanPoints(curveStr3)
            }
        }
    }

    // Also parse detailed curve from `fan-curve --mod-profile` output
    // Format: pwm: (2, 17, 30, ...), temp: (50, 65, 69, ...)
    for (var j = 0; j < lines.length; j++) {
        var ln = lines[j].trim()
        if (ln.indexOf("fan: CPU") >= 0) {
            // Look ahead for pwm and temp lines
            for (var k = j + 1; k < Math.min(j + 5, lines.length); k++) {
                var pline = lines[k].trim()
                if (pline.indexOf("pwm:") >= 0) {
                    var pwms = pline.replace("pwm:", "").replace(/[()]/g, "").split(",").map(function(s) { return parseInt(s.trim()) }).filter(function(n) { return !isNaN(n) })
                    // Find matching temp line
                    for (var t = k + 1; t < Math.min(k + 3, lines.length); t++) {
                        var tline = lines[t].trim()
                        if (tline.indexOf("temp:") >= 0) {
                            var temps = tline.replace("temp:", "").replace(/[()]/g, "").split(",").map(function(s) { return parseInt(s.trim()) }).filter(function(n) { return !isNaN(n) })
                            result.cpuPoints = []
                            for (var m = 0; m < Math.min(pwms.length, temps.length); m++) {
                                result.cpuPoints.push({ temp: temps[m], speed: Math.round(pwms[m] / 255 * 100) })
                            }
                            break
                        }
                    }
                    break
                }
            }
        }
        if (ln.indexOf("fan: GPU") >= 0) {
            for (var k2 = j + 1; k2 < Math.min(j + 5, lines.length); k2++) {
                var pline2 = lines[k2].trim()
                if (pline2.indexOf("pwm:") >= 0) {
                    var pwms2 = pline2.replace("pwm:", "").replace(/[()]/g, "").split(",").map(function(s) { return parseInt(s.trim()) }).filter(function(n) { return !isNaN(n) })
                    for (var t2 = k2 + 1; t2 < Math.min(k2 + 3, lines.length); t2++) {
                        var tline2 = lines[t2].trim()
                        if (tline2.indexOf("temp:") >= 0) {
                            var temps2 = tline2.replace("temp:", "").replace(/[()]/g, "").split(",").map(function(s) { return parseInt(s.trim()) }).filter(function(n) { return !isNaN(n) })
                            result.gpuPoints = []
                            for (var m2 = 0; m2 < Math.min(pwms2.length, temps2.length); m2++) {
                                result.gpuPoints.push({ temp: temps2[m2], speed: Math.round(pwms2[m2] / 255 * 100) })
                            }
                            break
                        }
                    }
                    break
                }
            }
        }
        if (ln.indexOf("fan: MID") >= 0) {
            result.hasMid = true
            for (var k3 = j + 1; k3 < Math.min(j + 5, lines.length); k3++) {
                var pline3 = lines[k3].trim()
                if (pline3.indexOf("pwm:") >= 0) {
                    var pwms3 = pline3.replace("pwm:", "").replace(/[()]/g, "").split(",").map(function(s) { return parseInt(s.trim()) }).filter(function(n) { return !isNaN(n) })
                    for (var t3 = k3 + 1; t3 < Math.min(k3 + 3, lines.length); t3++) {
                        var tline3 = lines[t3].trim()
                        if (tline3.indexOf("temp:") >= 0) {
                            var temps3 = tline3.replace("temp:", "").replace(/[()]/g, "").split(",").map(function(s) { return parseInt(s.trim()) }).filter(function(n) { return !isNaN(n) })
                            result.midPoints = []
                            for (var m3 = 0; m3 < Math.min(pwms3.length, temps3.length); m3++) {
                                result.midPoints.push({ temp: temps3[m3], speed: Math.round(pwms3[m3] / 255 * 100) })
                            }
                            break
                        }
                    }
                    break
                }
            }
        }
    }

    return result
}

// Serializes curve points back into asusctl's --data format: "30c:1%,49c:2%,...".
function serializeFanPoints(points) {
    return points.map(function(p) { return Math.round(p.temp) + "c:" + Math.round(p.speed) + "%" }).join(",")
}

// Moves point[index] to a new temp/speed, clamped to bounds and kept sorted
// by temp (dragging past a neighbor swaps order rather than crossing it).
function moveFanPoint(points, index, temp, speed) {
    var pts = points.map(function(p) { return { temp: p.temp, speed: p.speed } })
    if (index < 0 || index >= pts.length) return pts
    pts[index].temp = clamp(Math.round(temp), 30, 100)
    pts[index].speed = clamp(Math.round(speed), 0, 100)
    pts.sort(function(a, b) { return a.temp - b.temp })
    return pts
}

function parseFanPoints(str) {
    var points = []
    var parts = str.split(/[,;\s]+/)
    for (var i = 0; i < parts.length; i++) {
        var p = parts[i].replace(/[c%]/g, "").trim()
        var kv = p.split(/[:\s]+/)
        if (kv.length >= 2) {
            var temp = parseInt(kv[0]), speed = parseInt(kv[1])
            if (!isNaN(temp) && !isNaN(speed)) points.push({ temp: temp, speed: speed })
        }
    }
    return points
}

// ============================================================
// Armoury / Firmware
// ============================================================
function parseArmouryValue(raw) {
    var text = String(raw || "").trim()
    // Toggle: "[(0),1]"
    var tm = text.match(/\[\((\d+)\),(\d+)\]/)
    if (tm) return { type: "toggle", value: parseInt(tm[1]), off: parseInt(tm[1]), on: parseInt(tm[2]) }
    // Range: "25..[115]..45"
    var rm = text.match(/(\d+)\.\.\[(\d+)\]\.\.(\d+)/)
    if (rm) return { type: "range", value: parseInt(rm[2]), min: parseInt(rm[1]), max: parseInt(rm[3]) }
    return null
}

// ============================================================
// LED brightness
// ============================================================
function parseLedBrightness(raw) {
    var text = String(raw || "").trim().toLowerCase()
    if (text.indexOf("off") >= 0) return "off"
    if (text.indexOf("high") >= 0) return "high"
    if (text.indexOf("med") >= 0) return "med"
    if (text.indexOf("low") >= 0) return "low"
    return "off"
}

// ============================================================
// Color helpers
// ============================================================
function rgbToHex(r, g, b) {
    var rh = Math.max(0, Math.min(255, Math.round(r))).toString(16)
    var gh = Math.max(0, Math.min(255, Math.round(g))).toString(16)
    var bh = Math.max(0, Math.min(255, Math.round(b))).toString(16)
    if (rh.length < 2) rh = "0" + rh
    if (gh.length < 2) gh = "0" + gh
    if (bh.length < 2) bh = "0" + bh
    return rh + gh + bh
}

function hexToRgb(hex) {
    var h = String(hex).replace("#", "")
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
    if (h.length !== 6) return { r: 255, g: 255, b: 255 }
    return { r: parseInt(h.substring(0, 2), 16) || 0, g: parseInt(h.substring(2, 4), 16) || 0, b: parseInt(h.substring(4, 6), 16) || 0 }
}

var presetColors = [
    { name: "Red",    hex: "ff0000" }, { name: "Orange", hex: "ff8800" },
    { name: "Yellow", hex: "ffff00" }, { name: "Green",  hex: "00ff00" },
    { name: "Cyan",   hex: "00ffff" }, { name: "Blue",   hex: "0088ff" },
    { name: "Purple", hex: "aa00ff" }, { name: "Pink",   hex: "ff00ff" },
    { name: "White",  hex: "ffffff" }, { name: "Warm",   hex: "ffaa44" },
    { name: "Ice",    hex: "44ccff" }, { name: "Lime",   hex: "88ff00" }
]

// ============================================================
// Index helpers
// ============================================================
function clampIndex(i, l) { return l <= 0 ? 0 : Math.max(0, Math.min(l - 1, i)) }
function selectProfileIndex(i, d, p) { var v = Array.isArray(p) ? p : []; return v.length === 0 ? 0 : clampIndex(i + d, v.length) }
function clamp(v, mn, mx) { return Math.max(mn, Math.min(mx, v)) }

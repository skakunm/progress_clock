import AppKit
import Foundation

// MARK: - NSColor ↔ Hex

extension NSColor {
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent   * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent  * 255)))
    }

    static func fromHex(_ s: String) -> NSColor? {
        var h = s.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >>  8) & 0xFF) / 255
        let b = CGFloat( v        & 0xFF) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Modes (top-level so callers don't need AppConfig. prefix)

enum LayoutMode: String, Codable { case single, sideBySide, stacked }
enum LabelMode:  String, Codable { case none, time, percentage, both }

// MARK: - AppConfig

struct AppConfig: Codable {
    // Times
    var wakeHour: Int = 8;       var wakeMinute: Int = 30
    var sleepHour: Int = 0;      var sleepMinute: Int = 30
    var workStartHour: Int = 9;  var workStartMinute: Int = 0
    var workEndHour: Int = 17;   var workEndMinute: Int = 0
    var freeStartHour: Int = 18; var freeStartMinute: Int = 0
    var freeEndHour: Int = 23;   var freeEndMinute: Int = 30

    // Enabled flags
    var workEnabled: Bool = true
    var freeEnabled: Bool = true

    // Per-interval direction (▶ vs ◀) and fill anchor (left vs right)
    var dayForward:   Bool = true;  var dayFillLeft:   Bool = true
    var workForward:  Bool = true;  var workFillLeft:  Bool = true
    var freeForward:  Bool = true;  var freeFillLeft:  Bool = true
    var sleepForward: Bool = false; var sleepFillLeft: Bool = true

    // Display
    var barWidthLevel: Int = 3       // 1–5; stored raw, access via safeBarWidthLevel
    var layoutMode: LayoutMode = .stacked
    var labelMode:  LabelMode  = .both
    var swapBars:   Bool       = false

    // Colors (sRGB hex strings, e.g. "#2E54B3")
    var colorMain:        String = "#2E54B3"
    var colorUnscheduled: String = "#F29130"
    var colorWork:        String = "#33AB70"
    var colorFree:        String = "#9945D1"
    var colorSleep:       String = "#D12B3D"
}

extension AppConfig {
    var wakeTotal:      Int { wakeHour      * 60 + wakeMinute      }
    var sleepTotal:     Int {
        let raw = sleepHour * 60 + sleepMinute
        return raw < wakeTotal ? raw + 1440 : raw   // sleep past midnight → +1440
    }
    var workStartTotal: Int { workStartHour * 60 + workStartMinute }
    var workEndTotal:   Int { workEndHour   * 60 + workEndMinute   }
    var freeStartTotal: Int { freeStartHour * 60 + freeStartMinute }
    var freeEndTotal:   Int { freeEndHour   * 60 + freeEndMinute   }

    // barWidthLevel clamped to valid range — use everywhere instead of raw field
    var safeBarWidthLevel: Int { max(1, min(5, barWidthLevel)) }

    // Derived NSColors (fall back to hardcoded defaults if stored hex is corrupt)
    var clrMain:        NSColor { NSColor.fromHex(colorMain)        ?? NSColor(srgbRed: 0.18, green: 0.33, blue: 0.70, alpha: 1) }
    var clrUnscheduled: NSColor { NSColor.fromHex(colorUnscheduled) ?? NSColor(srgbRed: 0.95, green: 0.57, blue: 0.17, alpha: 1) }
    var clrWork:        NSColor { NSColor.fromHex(colorWork)        ?? NSColor(srgbRed: 0.20, green: 0.67, blue: 0.44, alpha: 1) }
    var clrFree:        NSColor { NSColor.fromHex(colorFree)        ?? NSColor(srgbRed: 0.60, green: 0.27, blue: 0.82, alpha: 1) }
    var clrSleep:       NSColor { NSColor.fromHex(colorSleep)       ?? NSColor(srgbRed: 0.82, green: 0.17, blue: 0.24, alpha: 1) }
}

// MARK: - ConfigManager

class ConfigManager {
    static let shared = ConfigManager()
    private let key = "ProgressClockConfigV7"
    private var _cache: AppConfig?

    private init() {
        // Remove orphaned keys left by earlier config versions
        (1...6).forEach { UserDefaults.standard.removeObject(forKey: "ProgressClockConfigV\($0)") }
    }

    var config: AppConfig {
        get {
            if let c = _cache { return c }
            guard let data = UserDefaults.standard.data(forKey: key),
                  let d    = try? JSONDecoder().decode(AppConfig.self, from: data)
            else { _cache = AppConfig(); return _cache! }
            _cache = d; return d
        }
        set {
            _cache = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
}

// MARK: - Helpers

func formatTime(_ h: Int, _ m: Int) -> String { String(format: "%02d:%02d", h, m) }

func normCur(_ cur: Int, wake: Int, sleep: Int) -> Int {
    if sleep > 1440 && cur < wake { return cur + 1440 }
    return cur
}

// MARK: - Day intervals

struct DayInterval {
    let start: Int; let end: Int
    let label: String; let color: NSColor
    let forward: Bool; let fillLeft: Bool
}

func buildWakingIntervals(config c: AppConfig) -> [DayInterval] {
    let wake = c.wakeTotal; let sleep = c.sleepTotal

    typealias N = (start: Int, end: Int, label: String, color: NSColor, fwd: Bool, left: Bool)
    var named: [N] = []
    if c.workEnabled && c.workStartTotal < c.workEndTotal {
        let cs = max(c.workStartTotal, wake); let ce = min(c.workEndTotal, sleep)
        if ce > cs { named.append((cs, ce, "work", c.clrWork, c.workForward, c.workFillLeft)) }
    }
    if c.freeEnabled && c.freeStartTotal < c.freeEndTotal {
        let cs = max(c.freeStartTotal, wake); let ce = min(c.freeEndTotal, sleep)
        if ce > cs { named.append((cs, ce, "free", c.clrFree, c.freeForward, c.freeFillLeft)) }
    }
    named.sort { $0.start < $1.start }

    // Label a gap by its position relative to named intervals
    func gapLabel(start: Int, end: Int) -> String {
        if named.isEmpty { return "day" }
        let before = named.contains { $0.end   <= start }
        let after  = named.contains { $0.start >= end   }
        if !before { return "morning"   }
        if !after  { return "evening"   }
        return "afternoon"
    }

    var result: [DayInterval] = []; var ptr = wake
    for ni in named {
        if ni.start > ptr {
            result.append(DayInterval(start: ptr, end: ni.start,
                                      label: gapLabel(start: ptr, end: ni.start),
                                      color: c.clrUnscheduled,
                                      forward: c.dayForward, fillLeft: c.dayFillLeft))
        }
        result.append(DayInterval(start: ni.start, end: ni.end, label: ni.label,
                                  color: ni.color, forward: ni.fwd, fillLeft: ni.left))
        ptr = max(ptr, ni.end)
    }
    if ptr < sleep {
        result.append(DayInterval(start: ptr, end: sleep,
                                  label: gapLabel(start: ptr, end: sleep),
                                  color: c.clrUnscheduled,
                                  forward: c.dayForward, fillLeft: c.dayFillLeft))
    }
    return result
}

// MARK: - Render state

struct RenderData {
    // Day bar
    let dayProg: Double; let dayFwd: Bool; let dayLeft: Bool
    // Activity bar
    let actProg: Double; let actColor: NSColor; let actFwd: Bool; let actLeft: Bool
    // Labels
    let timeStr: String; let actLabel: String
}

func computeRenderData(config c: AppConfig) -> RenderData {
    let cal = Calendar.current; let now = Date()
    let h = cal.component(.hour, from: now); let m = cal.component(.minute, from: now)
    let cur = h * 60 + m; let timeStr = formatTime(h, m)

    let wake = c.wakeTotal; let sleep = c.sleepTotal
    let nc   = normCur(cur, wake: wake, sleep: sleep)

    func nightElapsed() -> Int { nc >= sleep ? nc - sleep : nc + 1440 - sleep }
    let nightTotal = max(1, wake + 1440 - sleep)

    if nc >= wake && nc < sleep {
        let wakeDur = max(1, sleep - wake)
        let dayProg = Double(nc - wake) / Double(wakeDur)

        let ivs   = buildWakingIntervals(config: c)
        let curIv = ivs.first { nc >= $0.start && nc < $0.end }

        let actProg: Double; let actColor: NSColor
        let actFwd: Bool;    let actLeft: Bool; let actLabel: String
        if let iv = curIv {
            let raw = Double(nc - iv.start) / Double(max(1, iv.end - iv.start))
            actProg  = iv.forward ? raw : (1.0 - raw)
            actColor = iv.color; actFwd = iv.forward; actLeft = iv.fillLeft; actLabel = iv.label
        } else {
            actProg = dayProg; actColor = c.clrUnscheduled
            actFwd = c.dayForward; actLeft = c.dayFillLeft; actLabel = "day"
        }

        return RenderData(
            dayProg: min(1, max(0, dayProg)), dayFwd: c.dayForward,  dayLeft: c.dayFillLeft,
            actProg: min(1, max(0, actProg)), actColor: actColor,
            actFwd: actFwd, actLeft: actLeft, timeStr: timeStr, actLabel: actLabel)
    } else {
        let np      = Double(nightElapsed()) / Double(nightTotal)
        // Day bar resets in the opposite direction so it's full at wake time
        let dayProg = c.dayForward ? (1.0 - np) : np
        let actProg = c.sleepForward ? np : (1.0 - np)
        return RenderData(
            dayProg: min(1, max(0, dayProg)), dayFwd: !c.dayForward, dayLeft: c.dayFillLeft,
            actProg: min(1, max(0, actProg)), actColor: c.clrSleep,
            actFwd: c.sleepForward, actLeft: c.sleepFillLeft, timeStr: timeStr, actLabel: "sleep")
    }
}

// MARK: - Drawing

// Four shapes (fill anchor × direction):
//   A  fillLeft + forward  : [████▶]  convex right tip
//   B  fillLeft + backward : [████◁]  concave notch at right
//   C !fillLeft + forward  : [▷████]  concave notch at left
//   D !fillLeft + backward : [◀████]  convex left tip
func drawBar(progress p: Double, color: NSColor, forward: Bool, fillLeft: Bool,
             rect: NSRect, label: String?, maxFont: CGFloat = 13) {
    NSColor.white.withAlphaComponent(0.18).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()

    let fillW = rect.width * CGFloat(max(0, min(1, p)))
    guard fillW > 0.5 else {
        if let label { drawLabel(label, fillW: fillW, fillLeft: fillLeft, rect: rect) }
        return
    }

    let aw   = max(3.0, rect.height * 0.55)
    let half = aw / 2
    let ymid = rect.minY + rect.height / 2

    NSGraphicsContext.current?.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).setClip()
    color.setFill()

    let path = NSBezierPath()
    if fillLeft {
        let ctr  = rect.minX + fillW
        let base = ctr - half   // toward left anchor
        let tip  = ctr + half   // away from anchor

        if forward {
            // A: convex right tip
            path.move(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: base,      y: rect.minY))
            path.line(to: NSPoint(x: tip,       y: ymid))
            path.line(to: NSPoint(x: base,      y: rect.maxY))
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        } else {
            // B: concave notch on right
            path.move(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: tip,       y: rect.minY))
            path.line(to: NSPoint(x: base,      y: ymid))
            path.line(to: NSPoint(x: tip,       y: rect.maxY))
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        }
    } else {
        let ctr  = rect.maxX - fillW
        let base = ctr + half   // toward right anchor
        let tip  = ctr - half   // away from anchor (leftward)

        if forward {
            // C: concave notch on left (mirror of B)
            path.move(to: NSPoint(x: rect.maxX, y: rect.minY))
            path.line(to: NSPoint(x: tip,       y: rect.minY))
            path.line(to: NSPoint(x: base,      y: ymid))
            path.line(to: NSPoint(x: tip,       y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        } else {
            // D: convex left tip (mirror of A)
            path.move(to: NSPoint(x: rect.maxX, y: rect.minY))
            path.line(to: NSPoint(x: base,      y: rect.minY))
            path.line(to: NSPoint(x: tip,       y: ymid))
            path.line(to: NSPoint(x: base,      y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        }
    }
    path.close()
    path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    if let label { drawLabel(label, fillW: fillW, fillLeft: fillLeft, rect: rect, maxFont: maxFont) }
}

func drawLabel(_ label: String, fillW: CGFloat, fillLeft: Bool, rect: NSRect, maxFont: CGFloat = 13) {
    let aw       = max(3.0, rect.height * 0.55)
    let half     = aw / 2
    let fontSize = min(maxFont, rect.height * 0.95)
    let font     = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
    let shadow   = NSShadow()
    shadow.shadowColor      = NSColor.black.withAlphaComponent(0.55)
    shadow.shadowOffset     = NSSize(width: 0, height: -0.5)
    shadow.shadowBlurRadius = 2.5
    let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white, .font: font, .shadow: shadow]
    let astr = NSAttributedString(string: label, attributes: attrs)
    let tsz  = astr.size()
    let mg: CGFloat = 3

    let textX: CGFloat
    if fillLeft {
        let arrowBase = rect.minX + fillW - half
        let arrowTip  = rect.minX + fillW + half
        textX = fillW - half >= tsz.width + mg * 2
            ? arrowBase - mg - tsz.width
            : min(arrowTip + mg, rect.maxX - tsz.width - mg)
    } else {
        let arrowBase = rect.maxX - fillW + half
        let arrowTip  = rect.maxX - fillW - half
        textX = fillW - half >= tsz.width + mg * 2
            ? arrowBase + mg
            : max(rect.minX + mg, arrowTip - tsz.width - mg)
    }

    let textY = rect.midY - font.capHeight / 2 + font.descender
    astr.draw(at: NSPoint(x: max(rect.minX + mg, textX), y: textY))
}

func modeCode(_ label: String) -> String {
    switch label {
    case "morning":   return "MORN"
    case "afternoon": return "AFTN"
    case "evening":   return "EVNG"
    case "work":      return "WORK"
    case "free":      return "FREE"
    case "sleep":     return "SLEP"
    default:          return String(label.prefix(4).uppercased())
    }
}

func drawBars(data: RenderData, clrMain: NSColor,
              dayLabel: String?, actLabel: String?,
              layout: LayoutMode, swapBars: Bool, smallFont: Bool, in rect: NSRect) {
    let h = rect.height; let w = rect.width
    let mf: CGFloat = smallFont ? 9 : 13

    switch layout {
    case .single:
        if swapBars {
            drawBar(progress: data.actProg, color: data.actColor,
                    forward: data.actFwd, fillLeft: data.actLeft,
                    rect: rect, label: actLabel, maxFont: mf)
        } else {
            drawBar(progress: data.dayProg, color: clrMain,
                    forward: data.dayFwd, fillLeft: data.dayLeft,
                    rect: rect, label: dayLabel, maxFont: mf)
        }
    case .sideBySide:
        let gap: CGFloat = 6; let half = (w - gap) / 2
        let (lProg, lColor, lFwd, lLeft, lLbl, rProg, rColor, rFwd, rLeft, rLbl): (Double, NSColor, Bool, Bool, String?, Double, NSColor, Bool, Bool, String?)
        if swapBars {
            (lProg, lColor, lFwd, lLeft, lLbl) = (data.actProg, data.actColor, data.actFwd, data.actLeft, actLabel)
            (rProg, rColor, rFwd, rLeft, rLbl) = (data.dayProg, clrMain,       data.dayFwd, data.dayLeft, dayLabel)
        } else {
            (lProg, lColor, lFwd, lLeft, lLbl) = (data.dayProg, clrMain,       data.dayFwd, data.dayLeft, dayLabel)
            (rProg, rColor, rFwd, rLeft, rLbl) = (data.actProg, data.actColor, data.actFwd, data.actLeft, actLabel)
        }
        drawBar(progress: lProg, color: lColor, forward: lFwd, fillLeft: lLeft,
                rect: NSRect(x: 0,          y: 0, width: half, height: h), label: lLbl, maxFont: mf)
        drawBar(progress: rProg, color: rColor, forward: rFwd, fillLeft: rLeft,
                rect: NSRect(x: half + gap, y: 0, width: half, height: h), label: rLbl, maxFont: mf)
    case .stacked:
        let bigH  = (h - 3) * 0.74
        let thinH = max(3, (h - 3) * 0.18)
        if swapBars {
            drawBar(progress: data.actProg, color: data.actColor,
                    forward: data.actFwd, fillLeft: data.actLeft,
                    rect: NSRect(x: 0, y: h - bigH, width: w, height: bigH),
                    label: actLabel, maxFont: mf)
            drawBar(progress: data.dayProg, color: clrMain,
                    forward: data.dayFwd, fillLeft: data.dayLeft,
                    rect: NSRect(x: 0, y: 0, width: w, height: thinH), label: nil)
        } else {
            drawBar(progress: data.dayProg, color: clrMain,
                    forward: data.dayFwd, fillLeft: data.dayLeft,
                    rect: NSRect(x: 0, y: h - bigH, width: w, height: bigH),
                    label: dayLabel, maxFont: mf)
            drawBar(progress: data.actProg, color: data.actColor,
                    forward: data.actFwd, fillLeft: data.actLeft,
                    rect: NSRect(x: 0, y: 0, width: w, height: thinH), label: nil)
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var updateTimer: Timer?

    static let barWidths:     [CGFloat] = [60, 95, 140, 195, 320]
    static let barWidthNames: [String]  = ["XS", "S", "M", "L", "XL"]

    var barWidth: CGFloat { AppDelegate.barWidths[ConfigManager.shared.config.safeBarWidthLevel - 1] }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let savedLevel = ConfigManager.shared.config.safeBarWidthLevel
        // Create at XS first: a small item always gets a visible slot, which gives
        // a trustworthy occlusion signal. We then grow to the saved width and let
        // the notch correction shrink it back if it doesn't fit. (Born directly at
        // a large width, macOS reports occlusion unreliably.)
        var c = ConfigManager.shared.config; c.barWidthLevel = 1
        ConfigManager.shared.config = c
        statusItem = NSStatusBar.system.statusItem(withLength: barWidth)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling  = .scaleNone
        updateBar(); rebuildMenu()
        scheduleMinuteTimer()
        restoreWidth(to: savedLevel)
    }

    // MARK: - Notch-aware width
    //
    // On a notched screen macOS lets a too-wide status item slide behind the
    // notch, where it still reports a normal on-screen frame — so coordinates
    // can't tell it's hidden. occlusionState can: it drops `.visible` when the
    // item is off behind the notch. So after applying a width we check occlusion
    // and, if hidden, step down a level at a time until the item is visible.

    // Screen-space frame of the status item, or nil before it's placed.
    private func itemScreenFrame() -> NSRect? {
        guard let button = statusItem.button, let win = button.window else { return nil }
        return win.convertToScreen(button.convert(button.bounds, to: nil))
    }

    // Right edge of the notch, or nil on screens without one.
    private var notchRightEdge: CGFloat? {
        guard #available(macOS 12.0, *),
              let screen = NSScreen.main,
              screen.safeAreaInsets.top > 0 else { return nil }
        return screen.auxiliaryTopRightArea?.minX
    }

    private var itemIsVisible: Bool {
        statusItem.button?.window?.occlusionState.contains(.visible) ?? false
    }

    // Apply a width level (persisted), then shrink it if it lands behind the notch.
    private func setWidth(level: Int) {
        var c = ConfigManager.shared.config; c.barWidthLevel = level
        ConfigManager.shared.config = c
        updateBar(); rebuildMenu()
        correctForNotch(from: level)
    }

    private func correctForNotch(from level: Int) {
        guard notchRightEdge != nil, level > 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, !self.itemIsVisible else { return }   // visible: done
            self.setWidth(level: level - 1)
        }
    }

    // Wait until the XS item has a real menu-bar position, then grow to the saved
    // width. On screens without a notch, apply it straight away.
    private func restoreWidth(to savedLevel: Int, attempt: Int = 0) {
        guard let notchX = notchRightEdge else { setWidth(level: savedLevel); return }
        guard let frame = itemScreenFrame(), frame.maxX > notchX else {
            if attempt < 40 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.restoreWidth(to: savedLevel, attempt: attempt + 1)
                }
            } else {
                setWidth(level: savedLevel)
            }
            return
        }
        setWidth(level: savedLevel)
    }

    // Fires on the next full minute then repeats every 60 s, keeping HH:MM current.
    private func scheduleMinuteTimer() {
        updateTimer?.invalidate()
        let secondsUntilNextMinute = TimeInterval(60 - Calendar.current.component(.second, from: Date()))
        updateTimer = Timer.scheduledTimer(withTimeInterval: secondsUntilNextMinute, repeats: false) { [weak self] _ in
            self?.updateBar()
            self?.updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                self?.updateBar()
            }
        }
    }

    // MARK: Bar rendering

    func barLabels(data: RenderData, config c: AppConfig) -> (day: String?, act: String?) {
        let m = c.labelMode
        guard m != .none else { return (nil, nil) }

        let isSmall = c.safeBarWidthLevel < 3
        let dayPct  = "\(Int(data.dayProg * 100))%"
        let actPct  = "\(Int(data.actProg * 100))%"

        func dayLbl() -> String {
            switch m {
            case .none:       return ""
            case .time:       return data.timeStr
            case .percentage: return dayPct
            case .both:       return "\(data.timeStr) · \(dayPct)"
            }
        }
        func actLbl() -> String {
            switch m {
            case .none:       return ""
            case .time:       return data.timeStr
            case .percentage: return actPct
            case .both:       return "\(data.timeStr) · \(actPct)"
            }
        }

        if isSmall {
            // XS/S: .both falls back to time; only one label visible per bar
            let pct = m == .percentage
            let dl  = pct ? dayPct : data.timeStr
            let al  = pct ? actPct : data.timeStr
            switch c.layoutMode {
            case .single, .stacked:
                return c.swapBars ? (nil, al) : (dl, nil)
            case .sideBySide:
                let rightLbl: String? = m != .time ? (pct ? actPct : al) : nil
                return (dl, rightLbl)
            }
        }

        switch c.layoutMode {
        case .single, .stacked:
            return c.swapBars ? (nil, actLbl()) : (dayLbl(), nil)
        case .sideBySide:
            let al: String? = m == .time ? nil : (m == .percentage ? actPct : "\(data.actLabel) \(actPct)")
            return (dayLbl(), al)
        }
    }

    func updateBar() {
        let config    = ConfigManager.shared.config
        let w         = barWidth
        let h         = NSStatusBar.system.thickness
        let data      = computeRenderData(config: config)
        let labels    = barLabels(data: data, config: config)
        let isSBS     = config.layoutMode == .sideBySide
        let smallFont = config.safeBarWidthLevel < 3
        let totalW    = isSBS ? w * 2 + 6 : w
        statusItem.length = totalW
        let image = NSImage(size: NSSize(width: totalW, height: h), flipped: false) { rect in
            drawBars(data: data, clrMain: config.clrMain,
                     dayLabel: labels.day, actLabel: labels.act,
                     layout: config.layoutMode, swapBars: config.swapBars,
                     smallFont: smallFont, in: rect)
            return true
        }
        image.isTemplate = false
        statusItem.button?.image   = image
        statusItem.button?.toolTip = "\(data.timeStr)  Day \(Int(data.dayProg * 100))%  ·  \(data.actLabel) \(Int(data.actProg * 100))%"
    }

    // MARK: - Menu

    func rebuildMenu() {
        let menu = NSMenu()
        let c    = ConfigManager.shared.config
        let data = computeRenderData(config: c)

        let header = NSMenuItem(title: "Progress Clock", action: nil, keyEquivalent: "")
        header.isEnabled = false; menu.addItem(header)
        let info = NSMenuItem(
            title: "\(data.timeStr)  Day \(Int(data.dayProg * 100))%  ·  \(data.actLabel) \(Int(data.actProg * 100))%",
            action: nil, keyEquivalent: "")
        info.isEnabled = false; menu.addItem(info)
        menu.addItem(.separator())

        menu.addItem(section(
            title:   "Day   \(formatTime(c.wakeHour, c.wakeMinute)) – \(formatTime(c.sleepHour, c.sleepMinute))",
            forward: c.dayForward,   fillLeft: c.dayFillLeft,
            dirSel: #selector(toggleDayDir), fillSel: #selector(toggleDayFill),
            editSel: #selector(editDayBounds)))
        menu.addItem(.separator())

        menu.addItem(section(
            title:   "Work   \(formatTime(c.workStartHour, c.workStartMinute))–\(formatTime(c.workEndHour, c.workEndMinute))",
            forward: c.workForward,  fillLeft: c.workFillLeft,
            dirSel: #selector(toggleWorkDir), fillSel: #selector(toggleWorkFill),
            enable: (c.workEnabled, #selector(toggleWork)),
            editSel: #selector(editWorkTimes)))

        menu.addItem(section(
            title:   "Free   \(formatTime(c.freeStartHour, c.freeStartMinute))–\(formatTime(c.freeEndHour, c.freeEndMinute))",
            forward: c.freeForward,  fillLeft: c.freeFillLeft,
            dirSel: #selector(toggleFreeDir), fillSel: #selector(toggleFreeFill),
            enable: (c.freeEnabled, #selector(toggleFree)),
            editSel: #selector(editFreeTimes)))

        menu.addItem(section(
            title:   "Sleep  \(formatTime(c.sleepHour, c.sleepMinute)) – \(formatTime(c.wakeHour, c.wakeMinute))",
            forward: c.sleepForward, fillLeft: c.sleepFillLeft,
            dirSel: #selector(toggleSleepDir), fillSel: #selector(toggleSleepFill)))

        menu.addItem(.separator())
        let legend = NSMenuItem(title: "🟠 unscheduled   🟢 work   🟣 free   🔴 sleep", action: nil, keyEquivalent: "")
        legend.isEnabled = false; menu.addItem(legend)
        menu.addItem(.separator())

        // Width submenu
        let safeLevel   = c.safeBarWidthLevel
        let widthParent = NSMenuItem(title: "Width: \(AppDelegate.barWidthNames[safeLevel - 1])", action: nil, keyEquivalent: "")
        let widthSub    = NSMenu()
        for (i, name) in AppDelegate.barWidthNames.enumerated() {
            let item = NSMenuItem(title: name, action: #selector(setBarWidth(_:)), keyEquivalent: "")
            item.tag = i + 1; item.target = self
            item.state = safeLevel == i + 1 ? .on : .off
            widthSub.addItem(item)
        }
        widthParent.submenu = widthSub; menu.addItem(widthParent)

        // Layout submenu
        let layoutDefs: [(LayoutMode, String)] = [(.single, "Single"), (.sideBySide, "Side by side"), (.stacked, "Stacked")]
        let layoutParent = NSMenuItem(title: "Layout: \(layoutDefs.first { $0.0 == c.layoutMode }?.1 ?? "")", action: nil, keyEquivalent: "")
        let layoutSub = NSMenu()
        for (mode, name) in layoutDefs {
            let item = NSMenuItem(title: name, action: #selector(setLayoutMode(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue; item.target = self
            item.state = c.layoutMode == mode ? .on : .off
            layoutSub.addItem(item)
        }
        layoutParent.submenu = layoutSub; menu.addItem(layoutParent)

        let swapItem = NSMenuItem(title: "Swap bars", action: #selector(toggleSwapBars), keyEquivalent: "")
        swapItem.target = self; swapItem.state = c.swapBars ? .on : .off
        menu.addItem(swapItem)

        // Show (label mode) submenu
        let showDefs: [(LabelMode, String)] = [(.none, "None"), (.time, "Time"), (.percentage, "Percentage"), (.both, "Both")]
        let showParent = NSMenuItem(title: "Show: \(showDefs.first { $0.0 == c.labelMode }?.1 ?? "")", action: nil, keyEquivalent: "")
        let showSub = NSMenu()
        for (mode, name) in showDefs {
            let item = NSMenuItem(title: name, action: #selector(setLabelMode(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue; item.target = self
            item.state = c.labelMode == mode ? .on : .off
            if mode == .both { item.isEnabled = safeLevel >= 3 }
            showSub.addItem(item)
        }
        showParent.submenu = showSub; menu.addItem(showParent)

        menu.addItem(.separator())
        let colorsItem = NSMenuItem(title: "Edit colors…", action: #selector(editColors), keyEquivalent: "")
        colorsItem.target = self; menu.addItem(colorsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func section(title: String,
                          forward: Bool, fillLeft: Bool,
                          dirSel: Selector, fillSel: Selector,
                          enable: (isOn: Bool, action: Selector)? = nil,
                          editSel: Selector? = nil) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub    = NSMenu()

        let dirItem = NSMenuItem(title: forward ? "→ Direction: forward" : "← Direction: backward",
                                  action: dirSel, keyEquivalent: "")
        dirItem.target = self; sub.addItem(dirItem)

        let fillItem = NSMenuItem(title: fillLeft ? "⬤ Fill from: left" : "⬤ Fill from: right",
                                   action: fillSel, keyEquivalent: "")
        fillItem.target = self; sub.addItem(fillItem)

        if let en = enable {
            let ei = NSMenuItem(title: "Enabled", action: en.action, keyEquivalent: "")
            ei.target = self; ei.state = en.isOn ? .on : .off; sub.addItem(ei)
        }
        if let es = editSel {
            let ei = NSMenuItem(title: "Edit times…", action: es, keyEquivalent: "")
            ei.target = self; sub.addItem(ei)
        }

        parent.submenu = sub
        return parent
    }

    // MARK: - Time input (single alert, NSDatePicker per field)

    private func askTimes(title: String,
                          fields: [(label: String, h: Int, m: Int)]) -> [(Int, Int)]? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let rowH:    CGFloat = 36
        let labelW:  CGFloat = 90
        let pickerW: CGFloat = 120
        let totalW           = labelW + pickerW + 8
        let totalH           = CGFloat(fields.count) * rowH + 4

        let container = NSView(frame: NSRect(x: 0, y: 0, width: totalW, height: totalH))
        var pickers: [NSDatePicker] = []

        for (i, field) in fields.enumerated() {
            // NSView is bottom-up; first field sits at the top
            let y = totalH - CGFloat(i + 1) * rowH + 2

            let lbl = NSTextField(labelWithString: field.label)
            lbl.frame = NSRect(x: 0, y: y + 9, width: labelW - 6, height: 20)
            lbl.alignment = .right
            container.addSubview(lbl)

            let picker = NSDatePicker()
            picker.datePickerStyle    = .textFieldAndStepper
            picker.datePickerElements = .hourMinute
            var comps  = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            comps.hour = field.h; comps.minute = field.m
            if let d = Calendar.current.date(from: comps) { picker.dateValue = d }
            picker.frame = NSRect(x: labelW, y: y + 4, width: pickerW, height: 28)
            container.addSubview(picker)
            pickers.append(picker)
        }

        alert.accessoryView = container
        alert.window.initialFirstResponder = pickers.first
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        return pickers.map { p in
            let comps = Calendar.current.dateComponents([.hour, .minute], from: p.dateValue)
            return (comps.hour ?? 0, comps.minute ?? 0)
        }
    }

    // MARK: - Color editor

    @objc func editColors() {
        let alert = NSAlert()
        alert.messageText     = "Edit Colors"
        alert.informativeText = "Click a swatch to open the color picker, or type a hex value (#RRGGBB)."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")

        let c = ConfigManager.shared.config
        // WritableKeyPath allows both reading (initial values) and writing (on apply)
        let entries: [(label: String, key: WritableKeyPath<AppConfig, String>)] = [
            ("Day bar:",      \.colorMain),
            ("Unscheduled:", \.colorUnscheduled),
            ("Work:",        \.colorWork),
            ("Free:",        \.colorFree),
            ("Sleep:",       \.colorSleep),
        ]

        let rowH:   CGFloat = 34
        let labelW: CGFloat = 92
        let wellW:  CGFloat = 36
        let hexW:   CGFloat = 90
        let gap:    CGFloat = 8
        let totalW          = labelW + wellW + gap + hexW
        let totalH          = CGFloat(entries.count) * rowH + 4

        let container  = NSView(frame: NSRect(x: 0, y: 0, width: totalW, height: totalH))
        var wells:     [NSColorWell] = []
        var hexFields: [NSTextField] = []

        for (i, entry) in entries.enumerated() {
            let y = totalH - CGFloat(i + 1) * rowH + 2

            let lbl = NSTextField(labelWithString: entry.label)
            lbl.frame = NSRect(x: 0, y: y + 7, width: labelW - 4, height: 20)
            lbl.alignment = .right
            container.addSubview(lbl)

            let well = NSColorWell(frame: NSRect(x: labelW, y: y + 2, width: wellW, height: 28))
            well.color = NSColor.fromHex(c[keyPath: entry.key]) ?? .white
            container.addSubview(well)
            wells.append(well)

            let hexField = NSTextField(frame: NSRect(x: labelW + wellW + gap, y: y + 5, width: hexW, height: 24))
            hexField.stringValue      = c[keyPath: entry.key].uppercased()
            hexField.font             = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            hexField.placeholderString = "#RRGGBB"
            container.addSubview(hexField)
            hexFields.append(hexField)
        }

        alert.accessoryView = container
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Apply: hex field takes priority if valid, otherwise use color well
        var c2 = ConfigManager.shared.config
        for (i, entry) in entries.enumerated() {
            let raw = hexFields[i].stringValue.trimmingCharacters(in: .whitespaces)
            if NSColor.fromHex(raw) != nil {
                c2[keyPath: entry.key] = raw.hasPrefix("#") ? raw.uppercased() : "#\(raw.uppercased())"
            } else {
                c2[keyPath: entry.key] = wells[i].color.hexString
            }
        }
        ConfigManager.shared.config = c2
        updateBar(); rebuildMenu()
    }

    // MARK: - Toggles: direction

    @objc func toggleDayDir()   { mut { $0.dayForward   = !$0.dayForward   } }
    @objc func toggleWorkDir()  { mut { $0.workForward  = !$0.workForward  } }
    @objc func toggleFreeDir()  { mut { $0.freeForward  = !$0.freeForward  } }
    @objc func toggleSleepDir() { mut { $0.sleepForward = !$0.sleepForward } }

    // MARK: - Toggles: fill side

    @objc func toggleDayFill()   { mut { $0.dayFillLeft   = !$0.dayFillLeft   } }
    @objc func toggleWorkFill()  { mut { $0.workFillLeft  = !$0.workFillLeft  } }
    @objc func toggleFreeFill()  { mut { $0.freeFillLeft  = !$0.freeFillLeft  } }
    @objc func toggleSleepFill() { mut { $0.sleepFillLeft = !$0.sleepFillLeft } }

    // MARK: - Toggles: enabled

    @objc func toggleWork() { mut { $0.workEnabled = !$0.workEnabled } }
    @objc func toggleFree() { mut { $0.freeEnabled = !$0.freeEnabled } }

    // MARK: - Width / layout / label

    @objc func setBarWidth(_ sender: NSMenuItem) {
        setWidth(level: sender.tag)
    }

    @objc func toggleSwapBars()                    { mut { $0.swapBars = !$0.swapBars } }
    @objc func setLayoutMode(_ sender: NSMenuItem) {
        guard let raw  = sender.representedObject as? String,
              let mode = LayoutMode(rawValue: raw) else { return }
        mut { $0.layoutMode = mode }
    }
    @objc func setLabelMode(_ sender: NSMenuItem) {
        guard let raw  = sender.representedObject as? String,
              let mode = LabelMode(rawValue: raw) else { return }
        mut { $0.labelMode = mode }
    }

    // MARK: - Edit times

    @objc func editDayBounds() {
        let c = ConfigManager.shared.config
        guard let times = askTimes(title: "Day Bounds",
                                   fields: [("Wake:",  c.wakeHour,  c.wakeMinute),
                                            ("Sleep:", c.sleepHour, c.sleepMinute)]) else { return }
        mut {
            $0.wakeHour   = times[0].0; $0.wakeMinute  = times[0].1
            $0.sleepHour  = times[1].0; $0.sleepMinute = times[1].1
        }
    }

    @objc func editWorkTimes() {
        let c = ConfigManager.shared.config
        guard let times = askTimes(title: "Work Hours",
                                   fields: [("Start:", c.workStartHour, c.workStartMinute),
                                            ("End:",   c.workEndHour,   c.workEndMinute)]) else { return }
        mut {
            $0.workStartHour   = times[0].0; $0.workStartMinute = times[0].1
            $0.workEndHour     = times[1].0; $0.workEndMinute   = times[1].1
            $0.workEnabled     = true
        }
    }

    @objc func editFreeTimes() {
        let c = ConfigManager.shared.config
        guard let times = askTimes(title: "Free Hours",
                                   fields: [("Start:", c.freeStartHour, c.freeStartMinute),
                                            ("End:",   c.freeEndHour,   c.freeEndMinute)]) else { return }
        mut {
            $0.freeStartHour   = times[0].0; $0.freeStartMinute = times[0].1
            $0.freeEndHour     = times[1].0; $0.freeEndMinute   = times[1].1
            $0.freeEnabled     = true
        }
    }

    // Mutate config, persist, refresh bar and menu
    private func mut(_ block: (inout AppConfig) -> Void) {
        var c = ConfigManager.shared.config; block(&c)
        ConfigManager.shared.config = c; updateBar(); rebuildMenu()
    }
}

// MARK: - Entry point

let app = NSApplication.shared; let delegate = AppDelegate()
app.delegate = delegate; app.run()

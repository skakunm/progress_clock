import AppKit
import Foundation

// MARK: - AppConfig

struct AppConfig: Codable {
    // Times
    var wakeHour: Int = 8;       var wakeMinute: Int = 30   // 08:30
    var sleepHour: Int = 0;      var sleepMinute: Int = 30  // 00:30 (past midnight)
    var workStartHour: Int = 9;  var workStartMinute: Int = 0   // 09:00
    var workEndHour: Int = 17;   var workEndMinute: Int = 0     // 17:00
    var freeStartHour: Int = 18; var freeStartMinute: Int = 0   // 18:00
    var freeEndHour: Int = 23;   var freeEndMinute: Int = 30    // 23:30

    // Enabled flags
    var workEnabled: Bool = true
    var freeEnabled: Bool = true

    // Per-interval direction (▶ vs ◀) and fill anchor (left vs right).
    // These are fully independent — any combination is valid.
    var dayForward:    Bool = true;  var dayFillLeft:   Bool = true
    var workForward:   Bool = true;  var workFillLeft:  Bool = true
    var freeForward:   Bool = true;  var freeFillLeft:  Bool = true
    var sleepForward:  Bool = false; var sleepFillLeft: Bool = true
}

extension AppConfig {
    var wakeTotal: Int { wakeHour * 60 + wakeMinute }
    var sleepTotal: Int {
        let raw = sleepHour * 60 + sleepMinute
        return raw < wakeTotal ? raw + 1440 : raw   // sleep past midnight → add 1440
    }
    var workStartTotal: Int { workStartHour * 60 + workStartMinute }
    var workEndTotal:   Int { workEndHour   * 60 + workEndMinute   }
    var freeStartTotal: Int { freeStartHour * 60 + freeStartMinute }
    var freeEndTotal:   Int { freeEndHour   * 60 + freeEndMinute   }
}

// MARK: - ConfigManager

class ConfigManager {
    static let shared = ConfigManager()
    private let key = "ProgressClockConfigV6"

    var config: AppConfig {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let d    = try? JSONDecoder().decode(AppConfig.self, from: data)
            else { return AppConfig() }
            return d
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
}

// MARK: - Midnight normalisation

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
        if ce > cs { named.append((cs, ce, "work", .systemGreen, c.workForward, c.workFillLeft)) }
    }
    if c.freeEnabled && c.freeStartTotal < c.freeEndTotal {
        let cs = max(c.freeStartTotal, wake); let ce = min(c.freeEndTotal, sleep)
        if ce > cs { named.append((cs, ce, "free", .systemBlue, c.freeForward, c.freeFillLeft)) }
    }
    named.sort { $0.start < $1.start }

    // Name a gap by its position relative to named intervals:
    //   no named before it  → "morning"
    //   no named after it   → "evening"
    //   named on both sides → "afternoon"
    //   no named at all     → "day"
    func gapLabel(start: Int, end: Int) -> String {
        if named.isEmpty { return "day" }
        let before = named.contains { $0.end <= start }
        let after  = named.contains { $0.start >= end }
        if !before { return "morning" }
        if !after  { return "evening" }
        return "afternoon"
    }

    var result: [DayInterval] = []; var ptr = wake
    for ni in named {
        if ni.start > ptr {
            result.append(DayInterval(start: ptr, end: ni.start,
                                       label: gapLabel(start: ptr, end: ni.start),
                                       color: .systemYellow,
                                       forward: c.dayForward, fillLeft: c.dayFillLeft))
        }
        result.append(DayInterval(start: ni.start, end: ni.end, label: ni.label,
                                   color: ni.color, forward: ni.fwd, fillLeft: ni.left))
        ptr = max(ptr, ni.end)
    }
    if ptr < sleep {
        result.append(DayInterval(start: ptr, end: sleep,
                                   label: gapLabel(start: ptr, end: sleep),
                                   color: .systemYellow,
                                   forward: c.dayForward, fillLeft: c.dayFillLeft))
    }
    return result
}

// MARK: - Render state

struct RenderData {
    let dayProg: Double; let dayColor: NSColor; let dayFwd: Bool; let dayLeft: Bool
    let actProg: Double; let actColor: NSColor; let actFwd: Bool; let actLeft: Bool
    let timeStr: String; let actLabel: String
}

func computeRenderData(config c: AppConfig) -> RenderData {
    let cal = Calendar.current; let now = Date()
    let h = cal.component(.hour, from: now); let m = cal.component(.minute, from: now)
    let cur = h * 60 + m; let timeStr = String(format: "%02d:%02d", h, m)

    let wake = c.wakeTotal; let sleep = c.sleepTotal
    let nc = normCur(cur, wake: wake, sleep: sleep)
    let isWaking = nc >= wake && nc < sleep

    func nightElapsed() -> Int { nc >= sleep ? nc - sleep : nc + 1440 - sleep }
    let nightTotal = max(1, wake + 1440 - sleep)

    if isWaking {
        let wakeDur = max(1, sleep - wake)
        let rawDay  = Double(nc - wake) / Double(wakeDur)
        let dayProg = c.dayForward ? rawDay : (1.0 - rawDay)

        let ivs    = buildWakingIntervals(config: c)
        let cur_iv = ivs.first { nc >= $0.start && nc < $0.end }

        let dayColor: NSColor = cur_iv?.color ?? .systemYellow

        let actProg: Double; let actColor: NSColor; let actFwd: Bool; let actLeft: Bool; let actLabel: String
        if let iv = cur_iv {
            let raw = Double(nc - iv.start) / Double(max(1, iv.end - iv.start))
            actProg  = iv.forward ? raw : (1.0 - raw)
            actColor = iv.color; actFwd = iv.forward; actLeft = iv.fillLeft; actLabel = iv.label
        } else {
            actProg = dayProg; actColor = dayColor
            actFwd = c.dayForward; actLeft = c.dayFillLeft; actLabel = "day"
        }

        return RenderData(
            dayProg: min(1, max(0, dayProg)), dayColor: dayColor,
            dayFwd: c.dayForward, dayLeft: c.dayFillLeft,
            actProg: min(1, max(0, actProg)), actColor: actColor,
            actFwd: actFwd, actLeft: actLeft, timeStr: timeStr, actLabel: actLabel)
    } else {
        let np = Double(nightElapsed()) / Double(nightTotal)
        // Day bar resets opposite to dayForward so it's full again at wake time
        let dayProg = c.dayForward ? (1.0 - np) : np
        let actProg = c.sleepForward ? np : (1.0 - np)
        return RenderData(
            dayProg: min(1, max(0, dayProg)), dayColor: .systemRed,
            dayFwd: !c.dayForward, dayLeft: c.dayFillLeft,
            actProg: min(1, max(0, actProg)), actColor: .systemRed,
            actFwd: c.sleepForward, actLeft: c.sleepFillLeft, timeStr: timeStr, actLabel: "sleep")
    }
}

// MARK: - Drawing

// Draws a progress bar whose fill is anchored to `fillLeft` side and whose
// active end is shaped as a ▶ (forward) or ◀ (backward) arrowhead.
//
// Four shapes:
//   A  fillLeft+forward  : flat-left, ▶ tip at right end         [████▶  ]
//   B  fillLeft+backward : flat-left, ◀ notch at right end       [████◁  ]
//   C !fillLeft+forward  : ▷ notch at left end, flat-right       [  ▷████]
//   D !fillLeft+backward : ◀ tip at left end, flat-right         [  ◀████]
func drawBar(progress p: Double, color: NSColor, forward: Bool, fillLeft: Bool,
             rect: NSRect, label: String?) {
    // Background track
    NSColor.white.withAlphaComponent(0.18).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()

    let fillW  = rect.width * CGFloat(max(0, min(1, p)))
    guard fillW > 0.5 else {
        if let label = label { drawLabel(label, fillW: fillW, fillLeft: fillLeft, rect: rect) }
        return
    }

    let aw  = max(4.0, rect.height * 0.80)   // arrow width
    let mid = rect.minY + rect.height / 2

    // Clip fill to rounded background so corners stay clean
    NSGraphicsContext.current?.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).setClip()

    color.setFill()
    let path = NSBezierPath()

    if fillLeft {
        let r = rect.minX + fillW    // right edge of fill
        if forward {
            // A: [████▶] — convex right tip
            let base = max(rect.minX, r - aw)
            path.move(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: base,      y: rect.minY))
            path.line(to: NSPoint(x: r,          y: mid))
            path.line(to: NSPoint(x: base,      y: rect.maxY))
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        } else {
            // B: [████◁] — concave notch pointing left at right edge
            let notch = max(rect.minX, r - aw)
            path.move(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: r,          y: rect.minY))
            path.line(to: NSPoint(x: notch,     y: mid))
            path.line(to: NSPoint(x: r,          y: rect.maxY))
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        }
    } else {
        let l = rect.maxX - fillW   // left edge of fill
        if forward {
            // C: [▷████] — concave notch pointing right at left edge
            let notch = min(rect.maxX, l + aw)
            path.move(to: NSPoint(x: rect.maxX, y: rect.minY))
            path.line(to: NSPoint(x: l,          y: rect.minY))
            path.line(to: NSPoint(x: notch,     y: mid))
            path.line(to: NSPoint(x: l,          y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        } else {
            // D: [◀████] — convex left tip
            let base = min(rect.maxX, l + aw)
            path.move(to: NSPoint(x: rect.maxX, y: rect.minY))
            path.line(to: NSPoint(x: base,      y: rect.minY))
            path.line(to: NSPoint(x: l,          y: mid))
            path.line(to: NSPoint(x: base,      y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        }
    }
    path.close()
    path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    if let label = label { drawLabel(label, fillW: fillW, fillLeft: fillLeft, rect: rect) }
}

func drawLabel(_ label: String, fillW: CGFloat, fillLeft: Bool, rect: NSRect) {
    let aw  = max(4.0, rect.height * 0.80)
    let fontSize: CGFloat = min(13, rect.height * 0.95)
    let font  = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
    let shadow = NSShadow()
    shadow.shadowColor  = NSColor.black.withAlphaComponent(0.55)
    shadow.shadowOffset = NSSize(width: 0, height: -0.5)
    shadow.shadowBlurRadius = 2.5
    let attrs: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.white,
        .font: font,
        .shadow: shadow
    ]
    let astr  = NSAttributedString(string: label, attributes: attrs)
    let tsz   = astr.size()
    let mg: CGFloat = 3

    let textX: CGFloat
    if fillLeft {
        let r = rect.minX + fillW
        if fillW >= tsz.width + aw + mg * 2 {
            textX = r - aw - mg - tsz.width   // inside fill, left of arrow
        } else {
            textX = min(r + mg, rect.maxX - tsz.width - mg)  // after fill
        }
    } else {
        let l = rect.maxX - fillW
        if fillW >= tsz.width + aw + mg * 2 {
            textX = l + aw + mg                // inside fill, right of arrow
        } else {
            textX = max(rect.minX + mg, l - tsz.width - mg)  // before fill
        }
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

func drawBars(data: RenderData, in rect: NSRect) {
    let h = rect.height
    let w = rect.width

    // Day bar (tall — time text lives here)
    let dayH = (h - 3) * 0.74
    // Activity bar (thin stripe — just shows interval colour + arrow)
    let actH = max(3, (h - 3) * 0.18)

    drawBar(progress: data.dayProg, color: data.dayColor,
            forward: data.dayFwd, fillLeft: data.dayLeft,
            rect: NSRect(x: 0, y: h - dayH, width: w, height: dayH),
            label: data.timeStr)
    drawBar(progress: data.actProg, color: data.actColor,
            forward: data.actFwd, fillLeft: data.actLeft,
            rect: NSRect(x: 0, y: 0, width: w, height: actH),
            label: nil)
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var updateTimer: Timer?
    let barWidth: CGFloat = 250

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: barWidth)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling  = .scaleNone
        updateBar(); rebuildMenu()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateBar()
        }
    }

    func updateBar() {
        let config = ConfigManager.shared.config
        let h      = NSStatusBar.system.thickness
        let data   = computeRenderData(config: config)
        let image  = NSImage(size: NSSize(width: barWidth, height: h), flipped: false) { rect in
            drawBars(data: data, in: rect)
            return true
        }
        image.isTemplate = false
        statusItem.button?.image = image
    }

    // MARK: - Menu

    func rebuildMenu() {
        let menu = NSMenu()
        let c    = ConfigManager.shared.config
        let fmt  = { (hh: Int, mm: Int) in String(format: "%02d:%02d", hh, mm) }

        let header = NSMenuItem(title: "Progress Clock", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(section(
            title:    "Day   \(fmt(c.wakeHour, c.wakeMinute)) – \(fmt(c.sleepHour, c.sleepMinute))",
            forward:  c.dayForward,  fillLeft: c.dayFillLeft,
            dirSel:   #selector(toggleDayDir),  fillSel: #selector(toggleDayFill),
            enabled:  nil,           enableSel: nil,
            editSel:  #selector(editDayBounds)))
        menu.addItem(.separator())

        menu.addItem(section(
            title:    "Work   \(fmt(c.workStartHour, c.workStartMinute))–\(fmt(c.workEndHour, c.workEndMinute))",
            forward:  c.workForward, fillLeft: c.workFillLeft,
            dirSel:   #selector(toggleWorkDir), fillSel: #selector(toggleWorkFill),
            enabled:  c.workEnabled, enableSel: #selector(toggleWork),
            editSel:  #selector(editWorkTimes)))

        menu.addItem(section(
            title:    "Free   \(fmt(c.freeStartHour, c.freeStartMinute))–\(fmt(c.freeEndHour, c.freeEndMinute))",
            forward:  c.freeForward, fillLeft: c.freeFillLeft,
            dirSel:   #selector(toggleFreeDir), fillSel: #selector(toggleFreeFill),
            enabled:  c.freeEnabled, enableSel: #selector(toggleFree),
            editSel:  #selector(editFreeTimes)))

        menu.addItem(section(
            title:    "Sleep  \(fmt(c.sleepHour, c.sleepMinute)) – \(fmt(c.wakeHour, c.wakeMinute))",
            forward:  c.sleepForward, fillLeft: c.sleepFillLeft,
            dirSel:   #selector(toggleSleepDir), fillSel: #selector(toggleSleepFill),
            enabled:  nil,            enableSel: nil,
            editSel:  nil))

        menu.addItem(.separator())
        let legend = NSMenuItem(title: "🟡 unscheduled   🟢 work   🔵 free   🔴 sleep", action: nil, keyEquivalent: "")
        legend.isEnabled = false
        menu.addItem(legend)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func section(title: String,
                          forward: Bool, fillLeft: Bool,
                          dirSel: Selector, fillSel: Selector,
                          enabled: Bool?, enableSel: Selector?,
                          editSel: Selector?) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub    = NSMenu()

        let dirItem = NSMenuItem(title: forward ? "→ Direction: forward" : "← Direction: backward",
                                  action: dirSel, keyEquivalent: "")
        dirItem.target = self; sub.addItem(dirItem)

        let fillItem = NSMenuItem(title: fillLeft ? "⬤ Fill from: left" : "⬤ Fill from: right",
                                   action: fillSel, keyEquivalent: "")
        fillItem.target = self; sub.addItem(fillItem)

        if let en = enabled, let enSel = enableSel {
            let ei = NSMenuItem(title: "Enabled", action: enSel, keyEquivalent: "")
            ei.target = self; ei.state = en ? .on : .off; sub.addItem(ei)
        }
        if let es = editSel {
            let ei = NSMenuItem(title: "Edit times…", action: es, keyEquivalent: "")
            ei.target = self; sub.addItem(ei)
        }

        parent.submenu = sub
        return parent
    }

    // MARK: - Time input

    func askTime(title: String, h: Int, m: Int) -> (Int, Int)? {
        let alert = NSAlert()
        alert.messageText     = title
        alert.informativeText = "Enter time as HH:MM (e.g. 09:30 or 01:00)"
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 110, height: 24))
        field.stringValue = String(format: "%02d:%02d", h, m)
        field.placeholderString = "HH:MM"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let raw = field.stringValue.trimmingCharacters(in: .whitespaces)
        let pts = raw.split(separator: ":", maxSplits: 1)
        if pts.count == 2,
           let ph = Int(pts[0]), (0...23).contains(ph),
           let pm = Int(pts[1]), (0...59).contains(pm) { return (ph, pm) }
        if pts.count == 1, let ph = Int(String(pts[0])), (0...23).contains(ph) { return (ph, 0) }
        return nil
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

    // MARK: - Edit times

    @objc func editDayBounds() {
        var c = ConfigManager.shared.config
        guard let (wh, wm) = askTime(title: "Wake time",  h: c.wakeHour,  m: c.wakeMinute),
              let (sh, sm) = askTime(title: "Sleep time (past midnight OK, e.g. 01:00)",
                                      h: c.sleepHour, m: c.sleepMinute) else { return }
        c.wakeHour = wh; c.wakeMinute = wm; c.sleepHour = sh; c.sleepMinute = sm
        ConfigManager.shared.config = c; updateBar(); rebuildMenu()
    }
    @objc func editWorkTimes() {
        var c = ConfigManager.shared.config
        guard let (sh, sm) = askTime(title: "Work start", h: c.workStartHour, m: c.workStartMinute),
              let (eh, em) = askTime(title: "Work end",   h: c.workEndHour,   m: c.workEndMinute) else { return }
        c.workStartHour = sh; c.workStartMinute = sm
        c.workEndHour   = eh; c.workEndMinute   = em; c.workEnabled = true
        ConfigManager.shared.config = c; updateBar(); rebuildMenu()
    }
    @objc func editFreeTimes() {
        var c = ConfigManager.shared.config
        guard let (sh, sm) = askTime(title: "Free start", h: c.freeStartHour, m: c.freeStartMinute),
              let (eh, em) = askTime(title: "Free end",   h: c.freeEndHour,   m: c.freeEndMinute) else { return }
        c.freeStartHour = sh; c.freeStartMinute = sm
        c.freeEndHour   = eh; c.freeEndMinute   = em; c.freeEnabled = true
        ConfigManager.shared.config = c; updateBar(); rebuildMenu()
    }

    // Helper: mutate config, save, refresh
    private func mut(_ block: (inout AppConfig) -> Void) {
        var c = ConfigManager.shared.config; block(&c)
        ConfigManager.shared.config = c; updateBar(); rebuildMenu()
    }
}

// MARK: - Entry point

let app = NSApplication.shared; let delegate = AppDelegate()
app.delegate = delegate; app.run()

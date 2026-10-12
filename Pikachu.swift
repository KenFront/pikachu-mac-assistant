// 桌面皮卡丘：初代 Game Boy 像素風、會在 Mac 螢幕底部走來走去的桌寵
// 執行：swiftc -O Pikachu.swift -o pikachu && ./pikachu
// 互動：點牠會有反應、拖曳可以把牠甩出去、選單列的 ⚡ 或在牠身上按右鍵可以指定動作／結束
import AppKit

// MARK: - 可調參數

let scale: CGFloat = 0.9                          // 整體大小
let baseW: CGFloat = 200, baseH: CGFloat = 150    // 畫布大小（繪圖單位，含閃電與對話框的空間）
let footY: CGFloat = 6                            // 腳底離畫布底部的距離
let pixW = 72                                     // 像素畫解析度：畫布橫向幾個像素，越小顆粒越粗
let fps = 12.0                                    // 動畫格數：低一點比較有 Game Boy 味也省電（移動固定 60fps）
let dot = baseW / CGFloat(pixW)                   // 一個像素等於幾個繪圖單位
var watchDir = NSHomeDirectory() + "/.pikachu"    // Claude Code／Grok Build 的 hooks 把狀態寫在這（selftest 會換成暫存資料夾）
let awayAfter = 60.0                              // 幾秒沒碰鍵盤滑鼠算「不在」：不在時做完的，皮卡丘會一直慶祝到你回來

// MARK: - 顏色與形狀

func rgb(_ hex: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}
// Game Boy 四階灰，由亮到暗；想要初代綠螢幕就換成 [0x9BBC0F, 0x8BAC0F, 0x306230, 0x0F380F]
let palette = [0xF4F4EC, 0xB8B8B0, 0x606060, 0x202020]
let light = rgb(palette[0]), mid = rgb(palette[1]), dark = rgb(palette[2]), darkest = rgb(palette[3])
let cheekMark = rgb(0xFF00FF)                     // 臉頰先塗這個記號色，畫完再換成網點

func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2), transform: nil)
}

func poly(_ xy: [CGFloat]) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: stride(from: 0, to: xy.count, by: 2).map { CGPoint(x: xy[$0], y: xy[$0 + 1]) })
    p.closeSubpath()
    return p
}

// 皮卡丘自己的座標系：原點在兩腳中間的地面、y 朝上、預設面向右（3/4 側臉）
// 初代 Game Boy 造型：肚子圓滾滾、頭和身體幾乎連成一團、四肢短短的、後耳往側邊倒
let bodyPath = ellipse(0, 22, 32, 22), headPath = ellipse(1, 42, 29, 21)
let tailPath = poly([3, 2, -5, 12, 1, 13, -9, 27, -2, 29, -22, 55, -36, 44, -20, 30, -25, 27, -12, 13, -16, 11, -2, -2])
let earPath: CGPath = {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: -7, y: 0))
    p.addCurve(to: CGPoint(x: 0, y: 32), control1: CGPoint(x: -9.5, y: 14), control2: CGPoint(x: -3, y: 27))
    p.addCurve(to: CGPoint(x: 7, y: 0), control1: CGPoint(x: 3, y: 27), control2: CGPoint(x: 9.5, y: 14))
    p.closeSubpath()
    return p
}()

// 像素圖：每列由上到下、用空白分隔；K/D/M/W 是調色盤由深到淺，其他字元透明
let inks: [Character: CGColor] = ["K": darkest, "D": dark, "M": mid, "W": light]

// 3×5 像素字型（只收對話框用到的字）
let glyphs: [Character: String] = [
    "P": "KKK K.K KKK K.. K..", "I": "KKK .K. .K. .K. KKK", "K": "K.K K.K KK. K.K K.K", "A": ".K. K.K KKK K.K K.K",
    "C": ".KK K.. K.. K.. .KK", "H": "K.K K.K KKK K.K K.K", "U": "K.K K.K K.K K.K KKK", "Z": "KKK ..K .K. K.. KKK",
    "!": ".K. .K. .K. ... .K.", "?": "KK. ..K .K. ... .K.", ".": "... ... ... ... .K.", "-": "... ... KKK ... ...",
]

extension CGContext {
    func fill(_ p: CGPath, _ c: CGColor) { addPath(p); setFillColor(c); fillPath() }
    func shape(_ p: CGPath, _ c: CGColor) { fill(p, c); addPath(p); strokePath() }   // 填色＋描邊
    func clipped(to p: CGPath, _ draw: () -> Void) { saveGState(); addPath(p); clip(); draw(); restoreGState() }
}

// MARK: - 動作與姿勢

enum Act { case idle, walk, run, sit, sleep, jump, wave, happy, thunder, chase, drag, fall }
enum Eyes { case open, closed, happy, squint }

struct Pose {
    var bob: CGFloat = 0, sx: CGFloat = 1, sy: CGFloat = 1, lean: CGFloat = 0   // 身體上下、壓扁、前傾
    var footL = CGPoint.zero, footR = CGPoint.zero
    var armL: CGFloat = -0.2, armR: CGFloat = -0.2      // 手臂角度：0 朝下、正值往外往上舉、負值往內收
    var earL: CGFloat = 1.1, earR: CGFloat = -0.45      // 耳朵角度（逆時針為正）：後耳往側邊倒，像初代的圖
    var tail: CGFloat = 0
    var eyes = Eyes.open, mouthOpen = false, spark = false, sitting = false
    var look = CGPoint.zero                              // 眼睛跟著滑鼠的偏移
}

final class Pikachu: NSView {
    var pos = CGPoint.zero, vel = CGVector.zero        // pos：腳底中心的螢幕座標
    var face: CGFloat = 1                               // 1 面向右、-1 面向左
    var act = Act.fall, actT = 0.0, actLen = 0.0
    var t = 0.0, landT = -1.0, last = CACurrentMediaTime()
    var ground: CGFloat = 0
    var bubble = "", bubbleUntil = 0.0
    var bolts: [[CGPoint]] = [], boltsT = 0.0
    var grab: CGPoint?, dragged = false, trail: [(CGPoint, Double)] = []
    var agents: [String: String] = [:], nagT = -99.0  // 每個 claude／grok 程序（PID）的狀態、上次提醒的時間
    var labels: [String: String] = [:], doneAway = false   // 選單上的「工具 · 專案」、有沒有你不在時做完的
    var status: NSStatusItem?                          // 選單列的 ⚡

    var onGround: Bool { act != .drag && pos.y <= ground && vel.dy == 0 }
    var busy: Bool { agents.values.contains("busy") }
    var limited: Bool { agents.values.contains("limit") }

    // MARK: 行為

    func start(_ a: Act) {
        act = a; actT = 0
        switch a {
        case .walk: actLen = .random(in: 3...7); if Bool.random() { face = -face }
        case .run: actLen = .random(in: 1.5...3); if Bool.random() { face = -face }
        case .idle: actLen = .random(in: 2...5)
        case .sit: actLen = .random(in: 4...9)
        case .sleep: actLen = .random(in: 10...20)
        case .wave: actLen = 2; say("PIKA PIKA!")
        case .happy: actLen = 1.5; say("PIKACHU!")
        case .thunder: actLen = 2.4; say("PIKA...")
        case .chase: actLen = 6; say("PI?")
        case .jump: actLen = 0; say("PIKA!")
        case .fall, .drag: actLen = 0                   // 落地或放開滑鼠才結束
        }
    }

    func next() {
        if limited { start(.sleep); return }                                         // 額度用完：一直睡到恢復
        // 隨機只挑沒有意義的動作：揮手、坐下、睡覺、開心、十萬伏特（會放電）都留給監控用，看到就代表真的有事
        let odds: [(Act, Double)] = [(.walk, 30), (.run, 8), (.idle, 22), (.jump, 7), (.chase, 8)]
        var r = Double.random(in: 0..<odds.reduce(0) { $0 + $1.1 })
        for (a, w) in odds { r -= w; if r < 0 { start(a); return } }
    }

    func say(_ s: String) { bubble = s; bubbleUntil = t + 1.8 }

    @objc func tick() {
        let now = CACurrentMediaTime(), dt = min(now - last, 0.05)     // 卡頓時不要瞬移
        last = now; t += dt; actT += dt
        let vf = (NSScreen.screens.first { $0.frame.contains(CGPoint(x: pos.x, y: pos.y + 20)) } ?? NSScreen.main)?.visibleFrame ?? .zero
        let lo = vf.minX + 30 * scale, hi = vf.maxX - 30 * scale, top = vf.maxY - baseH * scale, step = CGFloat(dt)
        ground = vf.minY
        switch act {
        case .walk, .run:
            pos.x += face * (act == .walk ? 45 : 150) * step
            if pos.x < lo || pos.x > hi { face = -face }              // 碰到螢幕邊緣就回頭
        case .chase:
            let target = min(max(NSEvent.mouseLocation.x, lo), hi)
            face = target > pos.x ? 1 : -1
            pos.x += face * 170 * step
            if abs(target - pos.x) < 10 { start(.jump) }              // 追到了就跳起來
        case .jump where onGround && actT > 0.15:
            vel.dy = 480                                                // 蹲完起跳
        case .thunder:
            if actT >= 0.7 && actT - dt < 0.7 { say("PIKAAA-CHUUU!!") }
            if actT > 0.7 && actT < 2 && t - boltsT > 0.06 { bolts = makeBolts(); boltsT = t }
        default: break
        }
        if act != .drag {
            if pos.y > ground || vel.dy > 0 {                           // 空中：重力、撞牆反彈、落地
                vel.dy -= 1600 * step
                pos.x += vel.dx * step; pos.y += vel.dy * step
                if pos.x < lo || pos.x > hi { vel.dx *= -0.6 }
                if pos.y > top { pos.y = top; vel.dy = min(vel.dy, 0) }
                if pos.y <= ground { vel = .zero; landT = t; if act == .jump { start(.idle) } }
            }
            pos.x = min(max(pos.x, lo), hi); pos.y = max(pos.y, ground)
            if act == .fall && onGround { start(.idle) }                // 落地，或被直接放在地上
        }
        if Int(t) != Int(t - dt) { watch() }                            // 每秒看一次 Claude Code／Grok 的狀態
        if actLen > 0 && actT > actLen { next() }
        place()
        if Int(t * fps) != Int((t - dt) * fps) { needsDisplay = true }
    }

    func place() {                                                    // 對齊像素格一格一格移動：有像素感，也少搬視窗省 CPU
        let q = baseW * scale / CGFloat(pixW)
        let o = CGPoint(x: ((pos.x - baseW * scale / 2) / q).rounded() * q, y: ((pos.y - footY * scale) / q).rounded() * q)
        if let w = window, w.frame.origin != o { w.setFrameOrigin(o) }
    }

    func makeBolts() -> [[CGPoint]] {
        (0..<4).map { _ in                                                            // 4 道鋸齒狀閃電
            let a = CGFloat.random(in: -0.3...3.45), len = CGFloat.random(in: 50...80)
            return (0...4).map { i in
                let r = len * CGFloat(i) / 4, j: CGFloat = i % 4 == 0 ? 0 : (i % 2 == 0 ? -8 : 8)
                return CGPoint(x: cos(a) * r - sin(a) * j, y: 32 + sin(a) * r + cos(a) * j)
            }
        }
    }

    // MARK: 監控 Claude Code／Grok Build

    // hooks 把每個 claude／grok 程序寫成 watchDir/<pid>：第一行是狀態，第二行是選單上的「工具 · 專案」
    // 狀態：busy 工作中、wait 等你授權、done 完成、fail 出錯、limit 額度用完、idle 閒置
    // away：你多久沒碰鍵盤滑鼠（selftest 會直接指定）
    func watch(away: Bool = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) > awayAfter) {
        let fm = FileManager.default
        var now: [String: String] = [:], names: [String: String] = [:]
        for pid in (try? fm.contentsOfDirectory(atPath: watchDir)) ?? [] {
            guard let n = Int32(pid) else { continue }                                // 寫檔用的暫存檔之類，跳過
            let path = watchDir + "/" + pid
            if kill(n, 0) != 0 { try? fm.removeItem(atPath: path); continue }        // 程序已經結束（關掉、當掉、被 kill）
            let lines = (try? String(contentsOfFile: path, encoding: .utf8))?.components(separatedBy: "\n") ?? []
            guard let s = lines.first else { continue }
            now[pid] = s; names[pid] = lines.count > 1 ? lines[1] : "?"
        }
        let wasLimited = limited
        for (pid, s) in now where s != agents[pid] {
            let working = agents[pid] == "busy" || agents[pid] == "wait"              // 只認剛做完的：開機時的舊狀態、Grok 關掉時多送的 Stop 都不算
            if working && s == "done" { react(.happy); if away { doneAway = true; nagT = t } }   // 你不在：記著，等你回來
            if working && s == "fail" { react(.sit, "PIKA...") }
            if s == "limit" { react(.sleep) }
        }
        if now != agents || names != labels { agents = now; labels = names; refreshMenus() }
        if wasLimited && !limited && act == .sleep { start(.idle) }                  // 額度恢復就醒來
        if doneAway && !away { doneAway = false; react(.happy) }                     // 你回來了：再慶祝一次給你看
        if agents.values.contains("wait") && t - nagT >= 8 { nagT = t; react(.wave, "PIKA?!") }   // 等你授權：每 8 秒揮手一次
        else if doneAway && t - nagT >= 8 { nagT = t; react(.happy) }                // 你不在時做完的：每 8 秒慶祝一次
    }

    func react(_ a: Act, _ s: String? = nil) {
        guard act != .drag && act != .fall else { return }                          // 被抓著或還在空中就先不理
        start(a); if let s { say(s) }
    }

    // 右鍵選單和選單列 ⚡ 的選單都重做；⚡ 後面的記號：! 等你、z 額度用完、… 工作中
    func refreshMenus() {
        menu = makeMenu(); status?.menu = makeMenu()
        let s = agents.values
        status?.button?.title = s.contains("wait") ? "⚡!" : s.contains("limit") ? "⚡z" : s.contains("busy") ? "⚡…" : "⚡"
    }

    // MARK: 滑鼠

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with e: NSEvent) {
        let m = NSEvent.mouseLocation
        grab = CGPoint(x: pos.x - m.x, y: pos.y - m.y); dragged = false; trail = [(m, e.timestamp)]
    }

    override func mouseDragged(with e: NSEvent) {
        guard let g = grab, let first = trail.first else { return }
        let m = NSEvent.mouseLocation
        if !dragged {
            if hypot(m.x - first.0.x, m.y - first.0.y) < 4 { return }    // 手抖不算拖曳
            dragged = true; start(.drag); say("PIKA?!")
        }
        pos = CGPoint(x: m.x + g.x, y: m.y + g.y)
        trail.append((m, e.timestamp)); vel = recentVel(e.timestamp)
        place()
    }

    override func mouseUp(with e: NSEvent) {
        grab = nil
        guard dragged else { clicked(); return }
        dragged = false
        trail.append((NSEvent.mouseLocation, e.timestamp))
        let v = recentVel(e.timestamp)                                   // 用放開前 0.1 秒的速度把牠甩出去
        vel = CGVector(dx: max(-1500, min(1500, v.dx)), dy: max(-1500, min(1500, v.dy)))
        start(.fall)
    }

    func recentVel(_ now: Double) -> CGVector {
        trail.removeAll { now - $0.1 > 0.1 }
        guard let a = trail.first, let b = trail.last, b.1 - a.1 > 0.01 else { return .zero }
        let dt = CGFloat(b.1 - a.1)
        return CGVector(dx: (b.0.x - a.0.x) / dt, dy: (b.0.y - a.0.y) / dt)
    }

    func clicked() {
        if act == .sleep { start(.jump); say("PIKA?!"); return }        // 把牠吵醒
        start([Act.thunder, .wave, .happy, .jump].randomElement()!)
    }

    // MARK: 選單

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let names = ["busy": "工作中", "wait": "等你授權", "done": "完成", "fail": "出錯", "limit": "額度用完", "idle": "閒置"]
        for (pid, s) in agents.sorted(by: { $0.key < $1.key }) {                      // 每個 session 一行（沒有 action，灰字只看不能點）
            menu.addItem(withTitle: "\(labels[pid] ?? "?")：\(names[s] ?? s)", action: nil, keyEquivalent: "")
        }
        if agents.isEmpty { menu.addItem(withTitle: "沒有 Claude Code／Grok 在跑", action: nil, keyEquivalent: "") }
        menu.addItem(.separator())
        let items: [(String, Act)] = [("走路", .walk), ("跑步", .run), ("坐下", .sit), ("睡覺", .sleep), ("跳躍", .jump),
                                      ("揮手", .wave), ("開心", .happy), ("十萬伏特", .thunder), ("追滑鼠", .chase)]
        for (title, a) in items {
            let item = NSMenuItem(title: title, action: #selector(pick), keyEquivalent: "")
            item.target = self; item.representedObject = a
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "結束", action: #selector(NSApplication.terminate), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    @objc func pick(_ item: NSMenuItem) { if let a = item.representedObject as? Act { start(a) } }

    // MARK: 姿勢

    func pose() -> Pose {
        var p = Pose()
        let k = CGFloat(actT), tt = CGFloat(t)
        p.sy = 1 + 0.015 * sin(tt * 2.4); p.sx = 1 - 0.01 * sin(tt * 2.4)          // 呼吸
        p.tail = 0.06 * sin(tt * 1.7)
        if fmod(t, 3.7) < 0.12 { p.eyes = .closed }                                // 眨眼
        if fmod(t, 6.1) < 0.2 { p.earR -= 0.25 }                                   // 耳朵抖一下
        let m = NSEvent.mouseLocation, dx = m.x - pos.x, dy = m.y - (pos.y + 44 * scale), d = max(hypot(dx, dy), 1)
        p.look = CGPoint(x: dx / d * 1.6 * face, y: dy / d * 1.4)
        p.spark = busy                                                               // Claude Code／Grok 工作中：臉頰一直放電
        switch act {
        case .walk, .run, .chase:
            let fast = act != .walk, ph = k * (fast ? 17 : 8), amp: CGFloat = fast ? 5 : 3
            p.bob = abs(sin(ph)) * (fast ? 4 : 2)
            p.footR = CGPoint(x: cos(ph) * amp, y: max(0, sin(ph)) * amp)
            p.footL = CGPoint(x: -cos(ph) * amp, y: max(0, -sin(ph)) * amp)
            p.armR = -0.2 + sin(ph) * 0.35; p.armL = -0.2 - sin(ph) * 0.35
            p.tail = sin(ph) * 0.12
            if fast { p.lean = 0.16; p.earL = 1.3; p.earR = 0.05; p.mouthOpen = act == .chase }
        case .sit, .sleep:
            p.sy *= 0.86; p.sx *= 1.06; p.sitting = true; p.footL.x = -2; p.footR.x = 1
            p.tail = 0.15 * sin(tt * 3)
            if act == .sleep { p.eyes = .closed; p.look = .zero; p.lean = 0.08; p.earL = 1.5; p.earR = -1.2; p.tail = 0 }
        case .jump, .fall:
            if onGround { p.sy = 0.85; p.sx = 1.1; break }                            // 起跳前先蹲
            p.sy *= 1.08; p.sx *= 0.94; p.armL = 2.5; p.armR = 2.5; p.earL = 0.25; p.earR = -0.2
            p.mouthOpen = true; p.eyes = act == .jump ? .happy : .open; p.footL.y = -2; p.footR.y = 1
        case .wave:
            p.armR = 2.6 + 0.4 * sin(k * 14); p.eyes = .happy; p.mouthOpen = true
        case .happy:
            p.bob = abs(sin(k * 9)) * 6; p.eyes = .happy; p.mouthOpen = true; p.armL = 2.2; p.armR = 2.2; p.spark = true
        case .thunder:
            if k < 0.7 { p.sy = 0.88; p.sx = 1.07; p.eyes = .squint; p.spark = true }   // 蓄電
            else if k < 2 { p.sy = 1.07; p.sx = 0.95; p.lean = 0.1; p.eyes = .squint; p.mouthOpen = true; p.spark = true; p.earL = 0.3; p.earR = -0.25 }
        case .drag:
            p.footL.y = -1.5; p.footR.y = -1.5; p.armL = 2.7; p.armR = 2.7; p.mouthOpen = true
            p.lean = max(-0.5, min(0.5, vel.dx * 0.0004 * face))                     // 被拖著晃
            p.tail = 0.2 * sin(tt * 8)
        case .idle: break
        }
        let q = CGFloat(1 - (t - landT) / 0.18)                                      // 落地壓扁
        if q > 0 && q <= 1 { p.sy *= 1 - 0.22 * q; p.sx *= 1 + 0.14 * q }
        return p
    }

    // MARK: 繪圖

    // 先畫在低解析度畫布上（關掉反鋸齒），再用最近鄰放大，就是 Game Boy 的方塊像素
    override func draw(_ dirtyRect: NSRect) {
        guard let out = NSGraphicsContext.current?.cgContext,
              let g = CGContext(data: nil, width: pixW, height: Int((baseH / dot).rounded()), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        g.setShouldAntialias(false)
        let p = pose()
        g.saveGState()
        g.scaleBy(x: 1 / dot, y: 1 / dot); g.translateBy(x: baseW / 2, y: footY)
        if act == .thunder && actT > 0.7 && actT < 2 { drawBolts(g) }
        if onGround { g.fill(ellipse(3 * face, 0.5, 31, 3.4), rgb(0, 0.15)) }       // 影子
        g.scaleBy(x: face, y: 1)
        let faceAt = drawPikachu(g, p)                                                // 裝置座標
        g.restoreGState()                                                             // 回到像素座標
        dither(g)
        drawFace(g, p, at: g.convertToUserSpace(faceAt))
        if act == .sleep { drawZzz(g) }
        if t < bubbleUntil { drawBubble(g) }
        guard let img = g.makeImage() else { return }
        out.interpolationQuality = .none
        out.draw(img, in: bounds)
    }

    // 身體用向量畫在低解析度畫布上，回傳臉的中心（裝置座標）給手點的臉對位
    func drawPikachu(_ g: CGContext, _ p: Pose) -> CGPoint {
        g.setStrokeColor(dark); g.setLineWidth(dot * 1.1)
        let feet = { (rx: CGFloat, ry: CGFloat) in
            g.shape(ellipse(-10 + p.footL.x, 3 + p.footL.y, rx, ry), light)
            g.shape(ellipse(16 + p.footR.x, 3 + p.footR.y, rx, ry), light)
        }
        if !p.sitting { feet(9, 4.5) }                                               // 站著：腳在身體後面、不跟著晃
        g.translateBy(x: 0, y: p.bob); g.rotate(by: -p.lean); g.scaleBy(x: p.sx, y: p.sy)

        g.saveGState(); g.translateBy(x: -24, y: 14); g.rotate(by: p.tail + 0.25); g.scaleBy(x: 0.85, y: 0.85)   // 尾巴稍微往下，才不會跟後耳疊在一起
        g.fill(tailPath, mid)
        g.clipped(to: tailPath) { g.fill(ellipse(-3, 4, 9, 9), dark) }
        g.addPath(tailPath); g.strokePath()
        g.restoreGState()

        for (x, a) in [(CGFloat(-13), p.earL), (15, p.earR)] {                     // 耳朵，尖端最深色
            g.saveGState(); g.translateBy(x: x, y: 58); g.rotate(by: a)
            g.fill(earPath, light)
            g.clipped(to: earPath) { g.fill(CGPath(rect: CGRect(x: -10, y: 21, width: 20, height: 20), transform: nil), darkest) }
            g.addPath(earPath); g.strokePath()
            g.restoreGState()
        }

        g.setLineWidth(dot * 2.2)                                                     // 身體＋頭：先描粗邊再填色，交界就不會有線
        g.addPath(bodyPath); g.addPath(headPath); g.strokePath()
        g.setLineWidth(dot * 1.1)
        g.fill(bodyPath, light); g.fill(headPath, light)
        g.clipped(to: bodyPath) { g.fill(ellipse(-30, 28, 9, 3.4), dark); g.fill(ellipse(-30, 17, 9, 3.4), dark) }   // 背上條紋
        g.clipped(to: headPath) { g.fill(ellipse(-22, 36, 6, 6), cheekMark); g.fill(ellipse(27, 35.5, 6.6, 6.6), cheekMark) }   // 臉頰

        if p.sitting { feet(6.8, 5.6) }                                              // 坐著：腳伸到前面
        g.setLineWidth(dot)
        for (x, a, side) in [(CGFloat(-13), p.armL, CGFloat(-1)), (16, p.armR, 1)] {    // 手：往下再往內彎的短線
            g.saveGState(); g.translateBy(x: x, y: 28); g.rotate(by: a * side)
            g.addLines(between: [.zero, CGPoint(x: 0, y: -8), CGPoint(x: -5 * side, y: -10)]); g.strokePath()
            g.restoreGState()
        }
        return g.convertToDeviceSpace(CGPoint(x: 2.5, y: 39))
    }

    func drawBolts(_ g: CGContext) {
        g.saveGState()
        g.setLineJoin(.miter); g.setLineCap(.square)
        for (w, c) in [(dot * 3, darkest), (dot, light)] {                            // 深色粗線包住亮色細線
            g.setLineWidth(w); g.setStrokeColor(c)
            bolts.forEach { g.addLines(between: $0) }
            g.strokePath()
        }
        g.restoreGState()
    }

    // Game Boy 沒有紅色：把臉頰的記號色換成棋盤格網點
    func dither(_ g: CGContext) {
        guard let d = g.data?.assumingMemoryBound(to: UInt8.self) else { return }
        for y in 0..<g.height {
            for x in 0..<g.width {
                let i = y * g.bytesPerRow + x * 4
                guard d[i] == 255, d[i + 1] == 0, d[i + 2] == 255 else { continue }
                let c = palette[(x + y) % 2 == 0 ? 2 : 0]
                (d[i], d[i + 1], d[i + 2]) = (UInt8(c >> 16 & 255), UInt8(c >> 8 & 255), UInt8(c & 255))
            }
        }
    }

    // 以下都在像素座標：1 單位 = 1 像素、原點在畫布左下角
    // 點一張小圖，(x, y) 是左上角那格；flip 時往左畫（鏡像）
    func plot(_ g: CGContext, _ rows: String, x: Int, y: Int, flip: Bool = false) {
        for (r, row) in rows.split(separator: " ").enumerated() {
            for (c, ch) in row.enumerated() {
                guard let color = inks[ch] else { continue }
                g.setFillColor(color)
                g.fill(CGRect(x: flip ? x - c : x + c, y: y - r, width: 1, height: 1))
            }
        }
    }

    // 臉是手點的像素圖：座標以面向右為準、原點在鼻子下方，面向左時整張鏡像
    func drawFace(_ g: CGContext, _ p: Pose, at c: CGPoint) {
        let f = Int(face), x = Int(c.x.rounded()), y = Int(c.y.rounded())
        let part = { (rows: String, dx: Int, dy: Int) in self.plot(g, rows, x: x + dx * f, y: y + dy, flip: f < 0) }
        let lx = Int((p.look.x / 1.6).rounded()), ly = Int((p.look.y / 1.4).rounded())   // 眼睛跟著滑鼠最多偏一格
        switch p.eyes {
        case .open: for ex in [-7, 3] { part(".KK. KWKK KKKK KKKK .KK.", ex + lx, 6 + ly) }
        case .closed: for ex in [-7, 3] { part("K..K .KK.", ex, 4) }
        case .happy: for ex in [-7, 3] { part(".KK. K..K", ex, 4) }
        case .squint: part("K.. .K. ..K .K. K..", -6, 6); part("..K .K. K.. .K. ..K", 3, 6)   // > <
        }
        part("K", 0, 1)                                                               // 鼻子
        part(p.mouthOpen ? "KKKKK KDDDK .KKK." : "K.K.K .K.K.", -2, -1)              // 嘴
        if p.spark {                                                                  // 臉頰放電
            part(".K K. .K K.", -13, 2 + .random(in: -1...1)); part("K. .K K. .K", 12, 2 + .random(in: -1...1))
        }
    }

    func pixelText(_ g: CGContext, _ s: String, x: Int, y: Int) {                    // (x, y) 是第一個字的左下角
        for (n, ch) in s.enumerated() { plot(g, glyphs[ch] ?? "", x: x + n * 4, y: y + 4) }
    }

    func drawZzz(_ g: CGContext) {
        for i in 0..<3 {
            let k = (t * 0.45 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            g.setAlpha(1 - k)
            pixelText(g, "Z", x: pixW / 2 + Int(face * (4 + 9 * k)) - 1, y: 34 + Int(11 * k))
        }
        g.setAlpha(1)
    }

    func drawBubble(_ g: CGContext) {
        let w = bubble.count * 4 - 1, x = (pixW - w) / 2, y = 42
        let box = CGRect(x: x - 2, y: y - 2, width: w + 4, height: 9)
        g.setFillColor(darkest)
        g.fill(box.insetBy(dx: -1, dy: 0)); g.fill(box.insetBy(dx: 0, dy: -1))       // 外框，四角各缺一格看起來像圓角
        g.fill(CGRect(x: pixW / 2 - 1, y: y - 5, width: 3, height: 1)); g.fill(CGRect(x: pixW / 2, y: y - 6, width: 1, height: 1))   // 往下的尖角
        g.setFillColor(light); g.fill(box)
        pixelText(g, bubble, x: x, y: y)
    }
}

// MARK: - 啟動

// 給 Claude Code／Grok Build 的 hooks 呼叫：exec .../pikachu --hook <狀態>
// 要用 exec，getppid() 才會是 claude／grok 本身；command 裡不能放 $PPID，Grok 會先自己展開、找不到就不執行
if let i = CommandLine.arguments.firstIndex(of: "--hook"), i + 1 < CommandLine.arguments.count {
    // 一定要把事件的 JSON 讀完，對方才不會寫到一半斷掉；Claude Code 和 Grok 都有 error（StopFailure）和 cwd 欄位
    let event = (try? JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile())) as? [String: Any] ?? [:]
    var state = CommandLine.arguments[i + 1]
    if state == "fail" && event["error"] as? String == "rate_limit" { state = "limit" }   // 額度／流量限制：皮卡丘去睡覺
    let tool = ProcessInfo.processInfo.environment["GROK_HOOK_EVENT"] == nil ? "Claude Code" : "Grok"
    let project = URL(fileURLWithPath: event["cwd"] as? String ?? FileManager.default.currentDirectoryPath).lastPathComponent
    try? FileManager.default.createDirectory(atPath: watchDir, withIntermediateDirectories: true)
    try? "\(state)\n\(tool) · \(project)".write(toFile: "\(watchDir)/\(getppid())", atomically: true, encoding: .utf8)
    exit(0)
}

// 自我檢查（不開視窗，模擬幾分鐘的行為）：./pikachu --selftest
if CommandLine.arguments.contains("--selftest") {
    watchDir = NSTemporaryDirectory() + "pikachu-selftest-\(getpid())"     // 不要讀到真的 ~/.pikachu
    try? FileManager.default.createDirectory(atPath: watchDir, withIntermediateDirectories: true)
    let p = Pikachu(frame: .zero), vf = NSScreen.main!.visibleFrame
    func step() { p.last -= 1.0 / 60; p.tick() }
    p.pos = CGPoint(x: vf.midX, y: vf.maxY - 200); p.vel = CGVector(dx: 1500, dy: 800); p.start(.fall)
    for _ in 0..<600 where p.act == .fall { step() }
    if p.act == .fall || p.pos.y != vf.minY { fatalError("甩出去後 10 秒內要落地") }
    p.pos.y = vf.minY - 30; p.vel = .zero; p.start(.fall); step()             // 拖到 Dock 上直接放開
    if p.act == .fall { fatalError("放在地上要馬上站好") }
    let meaningful: [Act] = [.wave, .sit, .sleep, .happy, .thunder]                // 監控用的動作，隨機行為不能自己跑出來
    for _ in 0..<20_000 {
        step()
        if !vf.contains(p.pos) { fatalError("跑出螢幕了：\(p.pos) \(p.act)") }
        if meaningful.contains(p.act) { fatalError("沒事卻自己做了有意義的動作：\(p.act)") }
    }
    // 監控：拿自己的 PID 假裝是一個 claude 程序，Int32.max 當作已經結束的程序
    func agent(_ s: String, _ pid: Int32 = getpid(), away: Bool = false) {
        try? s.write(toFile: "\(watchDir)/\(pid)", atomically: true, encoding: .utf8); p.watch(away: away)
    }
    p.start(.idle)
    agent("fail"); if p.act != .idle { fatalError("開機時看到的舊狀態不要反應") }
    agent("busy"); if !p.pose().spark { fatalError("工作中臉頰要放電") }
    if p.menu?.items.first?.title != "?：工作中" { fatalError("選單要列出每個 session") }
    agent("wait"); if p.act != .wave { fatalError("等授權要揮手") }
    agent("done", away: true); if p.act != .happy || !p.doneAway { fatalError("你不在時做完要記著") }
    p.start(.idle); p.watch(away: false); if p.act != .happy || p.doneAway { fatalError("你回來要再慶祝一次") }
    agent("busy"); agent("limit"); if p.act != .sleep { fatalError("額度用完要睡覺") }
    p.next(); if p.act != .sleep { fatalError("額度還沒恢復要繼續睡") }
    agent("busy"); if p.act == .sleep { fatalError("額度恢復要醒來") }
    agent("busy", .max); if FileManager.default.fileExists(atPath: "\(watchDir)/\(Int32.max)") { fatalError("程序結束了，狀態檔要清掉") }
    try? FileManager.default.removeItem(atPath: watchDir)
    print("selftest ok"); exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)                     // 不出現在 Dock

let size = NSSize(width: baseW * scale, height: baseH * scale)
let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
panel.level = .floating; panel.hidesOnDeactivate = false
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
// 不設定 ignoresMouseEvents：透明的地方點擊會穿透到下面的視窗，只有皮卡丘本身接得到滑鼠

let pikachu = Pikachu(frame: NSRect(origin: .zero, size: size))
panel.contentView = pikachu
pikachu.status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
pikachu.refreshMenus()                                   // 右鍵選單、選單列的 ⚡ 和它的選單

let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
pikachu.pos = CGPoint(x: .random(in: screen.minX + 100...screen.maxX - 100), y: screen.maxY - size.height)   // 從天而降
pikachu.start(.fall); pikachu.say("PIKA!")
pikachu.place()
panel.orderFrontRegardless()

let timer = Timer(timeInterval: 1 / 60, target: pikachu, selector: #selector(Pikachu.tick), userInfo: nil, repeats: true)
RunLoop.main.add(timer, forMode: .common)
app.run()

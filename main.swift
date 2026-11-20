import SwiftUI
import AppKit

let root = "/Library/Application Support/FocusLock"
let statePath = root + "/state.json"
let listPath = root + "/blocklist.txt"
let blockedURL = "file:///Library/Application%20Support/FocusLock/blocked.html"
let reqDir = "/Users/Shared/FocusLock"
let reqPath = reqDir + "/request"
let agentLabel = "com.focuslock.agent"
let agentPlist = "/Library/LaunchAgents/\(agentLabel).plist"

struct LockState: Codable, Equatable {
    var on = false
    var lockedUntil: Double = 0
    var since: Double = 0
    var heartbeat: Double = 0
}
func now() -> Double { Date().timeIntervalSince1970 }
func readState() -> LockState? {
    guard let d = FileManager.default.contents(atPath: statePath) else { return nil }
    return try? JSONDecoder().decode(LockState.self, from: d)
}
struct BlockList { var domains: [String] = []; var hosts: [String] = []; var apps: [String] = [] }
func readList() -> BlockList {
    var b = BlockList()
    guard let s = try? String(contentsOfFile: listPath, encoding: .utf8) else { return b }
    let ok = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
    for line in s.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") || t.isEmpty { continue }
        let p = t.split(separator: " ", maxSplits: 1).map(String.init)
        guard p.count == 2 else { continue }
        let v = p[1].trimmingCharacters(in: .whitespaces)
        switch p[0] {
        case "domain", "host":
            let l = v.lowercased()
            guard l.unicodeScalars.allSatisfy({ ok.contains($0) }) else { continue }
            if p[0] == "domain" { b.domains.append(l) } else { b.hosts.append(l) }
        case "app": b.apps.append(v)
        default: break
        }
    }
    return b
}
@discardableResult func sh(_ path: String, _ args: [String]) -> Int32 {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return -1 }
    p.waitUntilExit(); return p.terminationStatus
}

func shOut(_ path: String, _ args: [String]) -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return "" }
    let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    return String(data: d, encoding: .utf8) ?? ""
}
func isNewer(_ a: String, than b: String) -> Bool {
    let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(x.count, y.count) {
        let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
        if l != r { return l > r }
    }
    return false
}
// Installs the newest GitHub release over this copy. Lock state and blocklist are kept.
func selfUpdate() {
    let repo = "https://github.com/Senekw/focus-lock/releases"
    let cur = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    let latest = shOut("/usr/bin/curl", ["-fsSL", "-m", "20", "-o", "/dev/null", "-w", "%{url_effective}", repo + "/latest"])
    guard let r = latest.range(of: "/tag/v") else { return }
    let tag = String(latest[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !tag.isEmpty, tag.allSatisfy({ $0.isNumber || $0 == "." }), isNewer(tag, than: cur) else { return }
    let tmp = root + "/update", app = tmp + "/Focus Lock.app"
    sh("/bin/rm", ["-rf", tmp]); sh("/bin/mkdir", ["-p", tmp])
    defer { sh("/bin/rm", ["-rf", tmp]) }
    guard sh("/usr/bin/curl", ["-fsSL", "-m", "180", "-o", tmp + "/f.zip", "\(repo)/download/v\(tag)/FocusLock-Mac.zip"]) == 0,
          sh("/usr/bin/ditto", ["-x", "-k", tmp + "/f.zip", tmp]) == 0,
          sh("/usr/bin/codesign", ["-v", app]) == 0,
          let info = NSDictionary(contentsOfFile: app + "/Contents/Info.plist"),
          info["CFBundleIdentifier"] as? String == "com.focuslock.app",
          info["CFBundleShortVersionString"] as? String == tag else { return }
    var sb = stat(); let uid = stat("/dev/console", &sb) == 0 ? sb.st_uid : 0
    let mine = root + "/Focus Lock.app", userApp = "/Applications/Focus Lock.app"
    if FileManager.default.fileExists(atPath: userApp) {
        sh("/bin/rm", ["-rf", userApp]); sh("/bin/cp", ["-R", app, userApp])
        if uid != 0 { sh("/usr/sbin/chown", ["-R", "\(uid):staff", userApp]) }
    }
    sh("/bin/rm", ["-rf", mine]); sh("/bin/cp", ["-R", app, mine])
    sh("/usr/sbin/chown", ["-R", "root:wheel", mine]); sh("/bin/chmod", ["-R", "go-w", mine])
    sh("/bin/rm", ["-rf", tmp])
    if uid != 0 { sh("/bin/launchctl", ["kickstart", "-k", "gui/\(uid)/\(agentLabel)"]) }
    exit(0)   // launchd restarts the daemon from the new copy
}

// MARK: root daemon: owns state and /etc/hosts
func runDaemon() {
    let begin = "# >>> FocusLock (managed, do not edit)", end = "# <<< FocusLock"
    var st = readState() ?? LockState()
    var tick = 0
    func save() {
        if let d = try? JSONEncoder().encode(st) {
            try? d.write(to: URL(fileURLWithPath: statePath), options: .atomic)
            chmod(statePath, 0o644)
        }
    }
    func enforceHosts() {
        guard let cur = try? String(contentsOfFile: "/etc/hosts", encoding: .utf8) else { return }
        var keep: [String] = []; var skipping = false
        for l in cur.components(separatedBy: "\n") {
            if l.hasPrefix("# >>> FocusLock") { skipping = true; continue }
            if l.hasPrefix("# <<< FocusLock") { skipping = false; continue }
            if !skipping { keep.append(l) }
        }
        while let l = keep.last, l.isEmpty { keep.removeLast() }
        var out = keep.joined(separator: "\n") + "\n"
        if st.on {
            let b = readList()
            var names: [String] = []
            for d in b.domains { names.append(d); names.append("www." + d) }
            names.append(contentsOf: b.hosts)
            var seen = Set<String>(); names = names.filter { seen.insert($0).inserted }
            out += begin + "\n" + names.map { "0.0.0.0 \($0)\n:: \($0)" }.joined(separator: "\n") + "\n" + end + "\n"
        }
        if out != cur {
            try? out.write(toFile: "/etc/hosts", atomically: true, encoding: .utf8)
            chmod("/etc/hosts", 0o644)
            sh("/usr/bin/dscacheutil", ["-flushcache"])
            sh("/usr/bin/killall", ["-HUP", "mDNSResponder"])
        }
    }
    func ensureAgent() {
        var sb = stat()
        guard stat("/dev/console", &sb) == 0, sb.st_uid != 0 else { return }
        let uid = sb.st_uid
        if sh("/bin/launchctl", ["print", "gui/\(uid)/\(agentLabel)"]) != 0 {
            sh("/bin/launchctl", ["enable", "gui/\(uid)/\(agentLabel)"])
            sh("/bin/launchctl", ["bootstrap", "gui/\(uid)", agentPlist])
        }
    }
    while true {
        if let d = FileManager.default.contents(atPath: reqPath), d.count < 64,
           let r = String(data: d, encoding: .utf8) {
            try? FileManager.default.removeItem(atPath: reqPath)
            let p = r.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
            if p.first == "on" {
                let secs = min(max(p.count > 1 ? (Double(p[1]) ?? 0) : 0, 0), 12 * 3600)
                if !st.on { st.on = true; st.since = now() }
                if secs > 0 { st.lockedUntil = max(st.lockedUntil, now() + secs) }
            } else if p.first == "off", now() >= st.lockedUntil {
                st.on = false; st.lockedUntil = 0
            }
        }
        st.heartbeat = now(); save(); enforceHosts()
        if tick % 5 == 0 { ensureAgent() }
        if tick % 10800 == 5 { selfUpdate() }   // shortly after start, then about every 6 hours
        tick += 1
        Thread.sleep(forTimeInterval: 2)
    }
}

// MARK: user agent: redirects blocked tabs, quits blocked apps, clears logins
func flatten(_ d: NSAppleEventDescriptor, _ out: inout [String]) {
    if d.numberOfItems > 0 { for i in 1...d.numberOfItems { if let c = d.atIndex(i) { flatten(c, &out) } } }
    else if let s = d.stringValue { out.append(s) }
}
func isBlocked(_ url: String, _ domains: [String]) -> Bool {
    guard let h = URL(string: url)?.host?.lowercased() else { return false }
    return domains.contains { h == $0 || h.hasSuffix("." + $0) }
}
func runAgent() {
    let browsers = ["com.google.Chrome", "com.operasoftware.Opera", "com.apple.Safari", "com.brave.Browser",
                    "com.microsoft.edgemac", "company.thebrowser.Browser", "com.google.Chrome.canary"]
    var purged: [String: Double] = [:]
    func osa(_ src: String) -> NSAppleEventDescriptor? {
        var err: NSDictionary?
        let r = NSAppleScript(source: src)?.executeAndReturnError(&err)
        return err == nil ? r : nil
    }
    func sweepTabs(_ id: String, _ domains: [String]) {
        guard let r = osa("tell application id \"\(id)\" to get URL of every tab of every window") else { return }
        var urls: [String] = []; flatten(r, &urls)
        guard urls.contains(where: { isBlocked($0, domains) }) else { return }
        let list = domains.map { "\"\($0)\"" }.joined(separator: ",")
        _ = osa("""
        set doms to {\(list)}
        tell application id "\(id)"
          repeat with w in windows
            repeat with i from (count of tabs of w) to 1 by -1
              try
                set u to URL of tab i of w
                set AppleScript's text item delimiters to "/"
                set h to text item 3 of u
                set AppleScript's text item delimiters to ":"
                set h to text item 1 of h
                set hit to false
                repeat with d in doms
                  if h is (d as text) or h ends with ("." & d) then set hit to true
                end repeat
                if hit then
                  try
                    set URL of tab i of w to "\(blockedURL)"
                  on error
                    close tab i of w
                  end try
                end if
              end try
            end repeat
          end repeat
        end tell
        """)
    }
    func purgeCookies(_ domains: [String], _ since: Double) {
        let fm = FileManager.default
        let support = NSHomeDirectory() + "/Library/Application Support/"
        let ids = ["Google/Chrome": "com.google.Chrome", "com.operasoftware.Opera": "com.operasoftware.Opera",
                   "BraveSoftware/Brave-Browser": "com.brave.Browser", "Microsoft Edge": "com.microsoft.edgemac"]
        let whereSQL = domains.map { "host_key='\($0)' OR host_key LIKE '%.\($0)'" }.joined(separator: " OR ")
        for (dir, id) in ids {
            if (purged[id] ?? 0) >= since { continue }
            if !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty { continue }
            let base = support + dir
            for sub in (try? fm.contentsOfDirectory(atPath: base)) ?? [] {
                for rel in ["/Cookies", "/Network/Cookies"] {
                    let db = base + "/" + sub + rel
                    if fm.fileExists(atPath: db) { sh("/usr/bin/sqlite3", [db, "DELETE FROM cookies WHERE \(whereSQL);"]) }
                }
            }
            for rel in ["/Cookies", "/Network/Cookies"] where fm.fileExists(atPath: base + rel) {
                sh("/usr/bin/sqlite3", [base + rel, "DELETE FROM cookies WHERE \(whereSQL);"])
            }
            purged[id] = now()
        }
    }
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
        guard let st = readState(), st.on else { return }
        let b = readList()
        for app in NSWorkspace.shared.runningApplications {
            let id = app.bundleIdentifier ?? "", name = app.localizedName ?? ""
            if b.apps.contains(id) || b.apps.contains(name) { if !app.terminate() { app.forceTerminate() } }
            else if browsers.contains(id) { sweepTabs(id, b.domains) }
        }
        purgeCookies(b.domains, st.since)
    }
    RunLoop.main.run()
}

// MARK: UI
final class Model: ObservableObject {
    @Published var state: LockState?
    @Published var t = now()
    @Published var minutes = 60
    @Published var pending = false
    var timer: Timer?
    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func refresh() {
        let s = readState()
        if s?.on != state?.on { pending = false }
        state = s; t = now()
    }
    var installed: Bool { if let s = state { return t - s.heartbeat < 15 } else { return false } }
    var remaining: Double { max(0, (state?.lockedUntil ?? 0) - t) }
    func send(_ s: String) {
        try? FileManager.default.createDirectory(atPath: reqDir, withIntermediateDirectories: true)
        try? s.write(toFile: reqPath, atomically: true, encoding: .utf8)
    }
    func lock() { pending = true; send("on \(minutes * 60)") }
    func extend(_ m: Int) { send("on \(Int(remaining) + m * 60)") }
    func unlock() { pending = true; send("off") }
    func install() {
        guard let script = Bundle.main.path(forResource: "install", ofType: "sh") else { return }
        let src = "do shell script \"/bin/bash \" & quoted form of \"\(script)\" with administrator privileges"
        DispatchQueue.global().async { var e: NSDictionary?; NSAppleScript(source: src)?.executeAndReturnError(&e) }
    }
}
let cream = Color(red: 0.965, green: 0.945, blue: 0.906)
let ink = Color(red: 0.17, green: 0.15, blue: 0.125)
let muted = Color(red: 0.27, green: 0.24, blue: 0.20)   // dark enough to stay readable over a wallpaper
let clay = Color(red: 0.76, green: 0.34, blue: 0.2)
let moss = Color(red: 0.25, green: 0.42, blue: 0.3)

// Makes the window itself see-through so the desktop wallpaper shows behind the tan tint.
struct ClearWindow: NSViewRepresentable {
    final class V: NSView {
        override func viewDidMoveToWindow() {
            // SwiftUI configures the window after this call, so apply on the next runloop turns too.
            for delay in [0.0, 0.1, 0.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let w = self?.window else { return }
                    w.isOpaque = false; w.backgroundColor = .clear
                    w.titlebarAppearsTransparent = true; w.styleMask.insert(.fullSizeContentView)
                    w.appearance = NSAppearance(named: .aqua)
                    w.invalidateShadow()
                }
            }
        }
    }
    func makeNSView(context: Context) -> V { V() }
    func updateNSView(_ v: V, context: Context) {}
}
struct Pill: ButtonStyle {
    var fill: Color; var fg: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 15, weight: .semibold)).foregroundColor(fg)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Capsule().fill(fill)).opacity(configuration.isPressed ? 0.8 : 1)
    }
}
struct ContentView: View {
    @StateObject var m = Model()
    let sites: String = {
        var d = readList().domains
        if d.isEmpty, let p = Bundle.main.path(forResource: "blocklist", ofType: "txt"),
           let s = try? String(contentsOfFile: p, encoding: .utf8) {
            d = s.split(separator: "\n").filter { $0.hasPrefix("domain ") }.map { String($0.dropFirst(7)) }
        }
        let head = d.prefix(5).joined(separator: " · ")
        return d.count > 5 ? head + " and \(d.count - 5) more" : head
    }()
    func endText(_ t: Double) -> String {
        // local time zone and the user's own 12/24-hour setting
        let d = Date(timeIntervalSince1970: t)
        let time = d.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(d) { return time }
        if Calendar.current.isDateInTomorrow(d) { return time + " tomorrow" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }
    func clock(_ s: Double) -> String {
        let i = Int(s.rounded(.up)); return String(format: "%d:%02d:%02d", i / 3600, (i / 60) % 60, i % 60)
    }
    var body: some View {
        let on = m.state?.on ?? false
        VStack(spacing: 18) {
            Text("FOCUS LOCK").font(.system(size: 11, weight: .semibold)).tracking(2.5).foregroundColor(muted)
            ZStack {
                Circle().fill(on ? clay : Color.white).frame(width: 132, height: 132)
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
                Image(systemName: on ? "lock.fill" : "lock.open").font(.system(size: 46, weight: .medium))
                    .foregroundColor(on ? .white : ink)
            }.padding(.top, 4)
            if !m.installed {
                Text("One step left").font(.custom("Georgia", size: 30)).foregroundColor(ink)
                Text("Focus Lock needs your Mac password once to install its blocker.")
                    .font(.system(size: 13, weight: .medium)).foregroundColor(muted).multilineTextAlignment(.center)
                Button("Finish setup") { m.install() }.buttonStyle(Pill(fill: ink))
            } else if on {
                Text("Locked in").font(.custom("Georgia", size: 34)).foregroundColor(ink)
                if m.remaining > 0 {
                    Text(clock(m.remaining)).font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit().foregroundColor(clay)
                    Text("Ends at \(endText(m.state?.lockedUntil ?? 0)). No turning it off until then.").font(.system(size: 13, weight: .medium)).foregroundColor(muted)
                    HStack(spacing: 8) {
                        Text("Add time").font(.system(size: 13, weight: .medium)).foregroundColor(muted)
                        ForEach([(15, "+15m"), (30, "+30m"), (60, "+1h"), (120, "+2h")], id: \.0) { v, label in
                            Button(label) { m.extend(v) }.buttonStyle(.plain)
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(ink)
                                .padding(.horizontal, 13).padding(.vertical, 9)
                                .background(Capsule().fill(Color.white))
                        }
                    }
                } else {
                    Text("Timer done. Blocking stays on until you turn it off.")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(muted).multilineTextAlignment(.center)
                    Button(m.pending ? "Unlocking…" : "Turn off") { m.unlock() }.buttonStyle(Pill(fill: ink))
                }
            } else {
                Text("Ready to lock in?").font(.custom("Georgia", size: 30)).foregroundColor(ink)
                HStack(spacing: 8) {
                    ForEach([(30, "30m"), (60, "1h"), (120, "2h"), (180, "3h"), (0, "No timer")], id: \.0) { v, label in
                        Button(label) { m.minutes = v }.buttonStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(m.minutes == v ? .white : ink)
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(Capsule().fill(m.minutes == v ? moss : Color.white))
                    }
                }
                Text(m.minutes == 0 ? "You can turn it off any time." : "Ends at \(endText(m.t + Double(m.minutes) * 60)). Once on, it cannot be turned off until then.")
                    .font(.system(size: 13, weight: .medium)).foregroundColor(muted)
                Button(m.pending ? "Locking…" : "Lock in") { m.lock() }.buttonStyle(Pill(fill: clay))
            }
            Spacer(minLength: 0)
            Text("Blocks " + sites).font(.system(size: 11, weight: .medium)).foregroundColor(muted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(28).frame(width: 400, height: 500)
        .background(ZStack { ClearWindow(); Color(red: 0.95, green: 0.90, blue: 0.80).opacity(0.35) }.ignoresSafeArea())
    }
}
struct FocusLockApp: App {
    var body: some Scene {
        WindowGroup("Focus Lock") { ContentView() }.windowResizability(.contentSize).windowStyle(.hiddenTitleBar)
    }
}
@main enum Main {
    static func main() {
        let a = CommandLine.arguments
        if a.contains("--daemon") { runDaemon() }
        else if a.contains("--agent") { runAgent() }
        else { FocusLockApp.main() }
    }
}

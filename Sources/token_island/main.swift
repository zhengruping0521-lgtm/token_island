import SwiftUI
import AppKit
import Foundation

// MARK: - Model Themes (Distinct Colors for each provider)
struct ModelTheme {
    static let chatgpt = Color(red: 0.12, green: 0.78, blue: 0.55)  // OpenAI Emerald Green
    static let gemini  = Color(red: 0.22, green: 0.82, blue: 0.98)  // Google Electric Cyan
    static let claude  = Color(red: 0.98, green: 0.58, blue: 0.25)  // Anthropic Warm Amber
}

func clampPct(_ percent: Int) -> Int { max(0, min(100, percent)) }

struct TimeFormatter {
    static func duration(from seconds: TimeInterval, day: String = "d", hour: String = "h", minute: String = "m") -> String {
        let sec = max(0, seconds)
        if sec < 60 { return "1\(minute)" }
        let totalMins = Int(round(sec / 60.0))
        let days = totalMins / 1440
        let hours = (totalMins % 1440) / 60
        let mins = totalMins % 60
        
        if days > 0 {
            if hours > 0 {
                return "\(days)\(day) \(hours)\(hour)"
            } else {
                return "\(days)\(day)"
            }
        } else if hours > 0 {
            if mins > 0 {
                return "\(hours)\(hour) \(mins)\(minute)"
            } else {
                return "\(hours)\(hour)"
            }
        } else {
            return "\(mins)\(minute)"
        }
    }
}

// MARK: - Service Data
struct MimirServiceData: Identifiable {
    let id = UUID()
    var name: String
    var iconName: String
    var isAvailable: Bool = false
    
    // For ChatGPT / Codex
    var sessionRemaining: Int?
    var weeklyRemaining: Int?
    var sessionResetAt: Date?
    var weeklyResetAt: Date?
    var resetCredits: Int?
    var resetCreditsExpiry: String?
    
    // For Antigravity
    var gemini5h: Int?
    var geminiWeekly: Int?
    var gemini5hResetAt: Date?
    var geminiWeeklyResetAt: Date?
    
    var claude5h: Int?
    var claudeWeekly: Int?
    var claude5hResetAt: Date?
    var claudeWeeklyResetAt: Date?
}

// MARK: - Store (Authoritative Data Engine)
@MainActor
final class QuotaStore: ObservableObject {
    static let shared = QuotaStore()
    
    @Published var codexData = MimirServiceData(
        name: "Codex",
        iconName: "chatgpt",
        isAvailable: true,
        sessionRemaining: 0,
        weeklyRemaining: 68,
        sessionResetAt: Date().addingTimeInterval(3 * 3600 + 40 * 60),
        weeklyResetAt: Date().addingTimeInterval(5 * 86400 + 16 * 3600),
        resetCredits: 1,
        resetCreditsExpiry: "22d 15h"
    )
    
    @Published var antigravityData = MimirServiceData(
        name: "Antigravity",
        iconName: "antigravity",
        isAvailable: true,
        gemini5h: 83,
        geminiWeekly: 85,
        gemini5hResetAt: Date().addingTimeInterval(3 * 3600 + 30 * 60),
        geminiWeeklyResetAt: Date().addingTimeInterval(1 * 86400 + 2 * 3600),
        claude5h: 100,
        claudeWeekly: 23,
        claude5hResetAt: Date().addingTimeInterval(4 * 3600 + 47 * 60),
        claudeWeeklyResetAt: Date().addingTimeInterval(1 * 86400 + 2 * 3600)
    )
    
    @Published var isRefreshing = false
    @Published var lastFetchTime = Date()
    
    private init() {
        refresh()
        Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }
    
    func refresh() {
        Task.detached(priority: .utility) {
            let (agy, cdx) = self.fetchFromSources()
            await MainActor.run {
                self.antigravityData = agy
                self.codexData = cdx
                self.lastFetchTime = Date()
            }
        }
    }
    
    private nonisolated func fetchFromSources() -> (MimirServiceData, MimirServiceData) {
        var agy = MimirServiceData(
            name: "Antigravity", iconName: "antigravity",
            isAvailable: false,
            gemini5h: 83, geminiWeekly: 85,
            gemini5hResetAt: nil, geminiWeeklyResetAt: nil,
            claude5h: 100, claudeWeekly: 23,
            claude5hResetAt: nil, claudeWeeklyResetAt: nil
        )
        
        var cdx = MimirServiceData(
            name: "Codex", iconName: "chatgpt",
            isAvailable: false,
            sessionRemaining: 0, weeklyRemaining: 68,
            sessionResetAt: nil, weeklyResetAt: nil,
            resetCredits: 1, resetCreditsExpiry: "22d 15h"
        )
        
        let isoParser = ISO8601DateFormatter()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        
        // 1. Fetch Official ChatGPT / Codex wham/usage API directly from auth.json
        let authPaths = [
            "\(home)/.codex/auth.json",
            "\(home)/.config/codex/auth.json"
        ]
        for p in authPaths {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: p)),
               let auth = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let tokens = auth["tokens"] as? [String: Any]
                let token = (tokens?["access_token"] as? String) ?? (auth["access_token"] as? String)
                let accountId = (auth["account_id"] as? String) ?? (tokens?["account_id"] as? String)
                
                if let token = token, !token.isEmpty {
                    var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!, timeoutInterval: 4)
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Accept")
                    req.setValue("Mimir", forHTTPHeaderField: "User-Agent")
                    if let accountId = accountId, !accountId.isEmpty {
                        req.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
                    }
                    
                    let semaphore = DispatchSemaphore(value: 0)
                    URLSession.shared.dataTask(with: req) { respData, response, error in
                        defer { semaphore.signal() }
                        guard let respData = respData,
                              let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
                              let rateLimit = json["rate_limit"] as? [String: Any] else { return }
                        
                        if let primary = rateLimit["primary_window"] as? [String: Any] {
                            let used = (primary["used_percent"] as? Double) ?? (primary["used_percent"] as? Int).map(Double.init) ?? 0.0
                            cdx.sessionRemaining = max(0, Int(round(100.0 - used)))
                            if let r = (primary["reset_at"] as? Double) ?? (primary["reset_at"] as? Int).map(Double.init) {
                                cdx.sessionResetAt = Date(timeIntervalSince1970: r)
                            }
                        }
                        if let secondary = rateLimit["secondary_window"] as? [String: Any] {
                            let used = (secondary["used_percent"] as? Double) ?? (secondary["used_percent"] as? Int).map(Double.init) ?? 0.0
                            cdx.weeklyRemaining = max(0, Int(round(100.0 - used)))
                            if let r = (secondary["reset_at"] as? Double) ?? (secondary["reset_at"] as? Int).map(Double.init) {
                                cdx.weeklyResetAt = Date(timeIntervalSince1970: r)
                            }
                        }
                        if let rlc = json["rate_limit_reset_credits"] as? [String: Any],
                           let avail = rlc["available_count"] as? Int {
                            cdx.resetCredits = avail
                        }
                        cdx.isAvailable = true
                    }.resume()
                    _ = semaphore.wait(timeout: .now() + 4)
                    break
                }
            }
        }
        
        // 2. Antigravity Local LanguageServer RPC Probe
        let ps = runShell("ps -ax -o pid=,command= | grep 'bin/language_server' | grep antigravity | grep -v grep")
        if let csrfMatch = ps.range(of: #"(?<=--csrf_token\s)[^\s]+"#, options: .regularExpression),
           let pidMatch = ps.range(of: #"^\s*\d+"#, options: .regularExpression) {
            let csrf = String(ps[csrfMatch])
            let pid = String(ps[pidMatch]).trimmingCharacters(in: .whitespaces)
            let lsof = runShell("lsof -a -nP -iTCP -sTCP:LISTEN -p \(pid)")
            let portMatches = matches(for: #":(\d+)\s+\(LISTEN\)"#, in: lsof)
            
            let body = "{\"metadata\":{\"ideName\":\"antigravity\",\"extensionName\":\"antigravity\",\"locale\":\"en\",\"ideVersion\":\"unknown\"}}"
            for port in Set(portMatches) {
                let out = runCommand("/usr/bin/curl", [
                    "-ks", "--max-time", "2",
                    "-H", "X-Codeium-Csrf-Token: \(csrf)",
                    "-H", "Connect-Protocol-Version: 1",
                    "-H", "Content-Type: application/json",
                    "--data", body,
                    "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
                ])
                if let data = out.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let response = json["response"] as? [String: Any],
                   let groups = response["groups"] as? [[String: Any]], !groups.isEmpty {
                    
                    agy.isAvailable = true
                    for group in groups {
                        let name = (group["displayName"] as? String ?? "").lowercased()
                        let buckets = group["buckets"] as? [[String: Any]] ?? []
                        if name.contains("gemini") {
                            for b in buckets {
                                let frac = (b["remainingFraction"] as? Double) ?? (b["remainingFraction"] as? Int).map(Double.init) ?? 1.0
                                let window = b["window"] as? String ?? ""
                                let reset = (b["resetTime"] as? String).flatMap { isoParser.date(from: $0) }
                                if window == "5h" {
                                    agy.gemini5h = Int(round(frac * 100))
                                    agy.gemini5hResetAt = reset
                                } else if window == "weekly" {
                                    agy.geminiWeekly = Int(round(frac * 100))
                                    agy.geminiWeeklyResetAt = reset
                                }
                            }
                        } else if name.contains("claude") || name.contains("gpt") {
                            for b in buckets {
                                let frac = (b["remainingFraction"] as? Double) ?? (b["remainingFraction"] as? Int).map(Double.init) ?? 1.0
                                let window = b["window"] as? String ?? ""
                                let reset = (b["resetTime"] as? String).flatMap { isoParser.date(from: $0) }
                                if window == "5h" {
                                    agy.claude5h = Int(round(frac * 100))
                                    agy.claude5hResetAt = reset
                                } else if window == "weekly" {
                                    agy.claudeWeekly = Int(round(frac * 100))
                                    agy.claudeWeeklyResetAt = reset
                                }
                            }
                        }
                    }
                    break
                }
            }
        }
        
        return (agy, cdx)
    }
}

// MARK: - Mimir Components
struct MimirQuotaBlock: View {
    let label: String
    let percent: Int
    let resetAt: Date?
    let now: Date
    let modelColor: Color
    var windowFallback: TimeInterval = 5 * 3600

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.95))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("%\(clampPct(percent))")
                    .font(.system(size: 15.5, weight: .bold, design: .monospaced))
                    .foregroundColor(modelColor)
            }

            // Quota Bar
            GeometryReader { proxy in
                let ratio = CGFloat(clampPct(percent)) / 100.0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(modelColor)
                        .frame(width: max(5, proxy.size.width * ratio))
                }
            }
            .frame(height: 5)
            .padding(.top, 6)

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 10.5))
                    Text(relDuration(resetAt, now) ?? TimeFormatter.duration(from: windowFallback))
                }
                Spacer(minLength: 4)
                if let clock = resetClock {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10.5))
                        Text(clock)
                    }
                }
            }
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .foregroundColor(Color.white.opacity(0.55))
            .padding(.top, 6)
        }
    }

    private var resetClock: String? {
        guard let resetAt, resetAt.timeIntervalSince(now) > 0 else { return nil }
        return Self.clockFormatter.string(from: resetAt)
    }

    private func relDuration(_ resetAt: Date?, _ now: Date) -> String? {
        guard let resetAt, resetAt.timeIntervalSince(now) > 0 else { return nil }
        return TimeFormatter.duration(from: resetAt.timeIntervalSince(now))
    }
}

// MARK: - Mimir Service Cards (Pure Black Aesthetic)
struct MimirCardView: View {
    @ObservedObject var store = QuotaStore.shared
    let now = Date()
    
    var body: some View {
        VStack(spacing: 11) {
            // Card 1: CHATGPT (仅当检测到 Codex/ChatGPT 或两者都未检测到时显示)
            if store.codexData.isAvailable || (!store.codexData.isAvailable && !store.antigravityData.isAvailable) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 10.5))
                            .foregroundColor(ModelTheme.chatgpt.opacity(0.85))
                        Text("CHATGPT")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(Color.white.opacity(0.55))
                    }
                    .padding(.bottom, 7)
                    
                    MimirQuotaBlock(
                        label: "Current session",
                        percent: store.codexData.sessionRemaining ?? 0,
                        resetAt: store.codexData.sessionResetAt,
                        now: now,
                        modelColor: ModelTheme.chatgpt,
                        windowFallback: 5 * 3600
                    )
                    
                    // Weekly row
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ModelTheme.chatgpt)
                            .frame(width: 6, height: 6)
                        Text("All models: %\(clampPct(store.codexData.weeklyRemaining ?? 0))")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.85))
                        Spacer()
                        Text(relDuration(store.codexData.weeklyResetAt, now) ?? "5d 16h")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.45))
                    }
                    .padding(.top, 8)
                    
                    Divider()
                        .background(Color.white.opacity(0.12))
                        .padding(.vertical, 7)
                    
                    // Reset credits
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                Text("Reset credits")
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundColor(Color.white.opacity(0.65))
                            Spacer()
                            Text("\(store.codexData.resetCredits ?? 1)")
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.95))
                        }
                        Text("first expires in \(store.codexData.resetCreditsExpiry ?? "22d 15h")")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color(white: 0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
            }
            
            // Card 2: ANTIGRAVITY (仅当检测到 Antigravity 或两者都未检测到时显示)
            if store.antigravityData.isAvailable || (!store.codexData.isAvailable && !store.antigravityData.isAvailable) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.55))
                        Text("ANTIGRAVITY")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(Color.white.opacity(0.55))
                    }
                    .padding(.bottom, 7)
                    
                    // Gemini Section
                    MimirQuotaBlock(
                        label: "Gemini",
                        percent: store.antigravityData.gemini5h ?? 83,
                        resetAt: store.antigravityData.gemini5hResetAt,
                        now: now,
                        modelColor: ModelTheme.gemini,
                        windowFallback: 5 * 3600
                    )
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ModelTheme.gemini)
                            .frame(width: 6, height: 6)
                        Text("Gemini: %\(clampPct(store.antigravityData.geminiWeekly ?? 85))")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.85))
                        Spacer()
                        Text(relDuration(store.antigravityData.geminiWeeklyResetAt, now) ?? "1d 2h")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.45))
                    }
                    .padding(.top, 8)
                    
                    Divider()
                        .background(Color.white.opacity(0.12))
                        .padding(.vertical, 10)
                    
                    // Claude/GPT Section
                    MimirQuotaBlock(
                        label: "Claude/GPT",
                        percent: store.antigravityData.claude5h ?? 100,
                        resetAt: store.antigravityData.claude5hResetAt,
                        now: now,
                        modelColor: ModelTheme.claude,
                        windowFallback: 5 * 3600
                    )
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ModelTheme.claude)
                            .frame(width: 6, height: 6)
                        Text("Claude/GPT: %\(clampPct(store.antigravityData.claudeWeekly ?? 23))")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.85))
                        Spacer()
                        Text(relDuration(store.antigravityData.claudeWeeklyResetAt, now) ?? "1d 2h")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.45))
                    }
                    .padding(.top, 8)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color(white: 0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
            }
            
            // Footer: 居中文本与 yupi 署名（上下左右 11px 完美对称）
            VStack(spacing: 3) {
                Text("Keep going. You’re closer than you think.")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.65))
                
                Text("yupi")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
            .padding(.bottom, 2)
        }
        .padding(11) // 上下左右绝对一致的 11px 边距
    }
    
    private func relDuration(_ resetAt: Date?, _ now: Date) -> String? {
        guard let resetAt, resetAt.timeIntervalSince(now) > 0 else { return nil }
        return TimeFormatter.duration(from: resetAt.timeIntervalSince(now))
    }
}

// MARK: - Dynamic Island View (Pure Black & Pixel-Perfect Symmetry)
struct ScreenIslandView: View {
    @ObservedObject var store = QuotaStore.shared
    @Binding var isExpanded: Bool
    
    var body: some View {
        Group {
            if !isExpanded {
                collapsedPill
                    .frame(width: 92, height: 26)
            } else {
                MimirCardView(store: store)
                    .frame(width: 298)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: isExpanded ? 20 : 13, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: isExpanded ? 20 : 13, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.6), radius: isExpanded ? 20 : 3, y: isExpanded ? 6 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 20 : 13, style: .continuous))
        .padding(.top, isExpanded ? 35 : 0) // 35px 向下安全边距
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                store.refresh()
            } label: {
                Label("立即刷新数据", systemImage: "arrow.clockwise")
            }
            Divider()
            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出 token_island", systemImage: "power")
            }
        }
        .animation(.snappy(duration: 0.20, extraBounce: 0.0), value: isExpanded)
    }
    
    /// 待机状态：仅显示可用模型的 5h% / 1w%（无图标，%在数字后，/为白色）
    private var collapsedPill: some View {
        HStack(spacing: 4) {
            if store.codexData.isAvailable || !store.antigravityData.isAvailable {
                Text("\(clampPct(store.codexData.sessionRemaining ?? 0))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(ModelTheme.chatgpt)
                
                Text("/")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.white)
                
                Text("\(clampPct(store.codexData.weeklyRemaining ?? 68))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(ModelTheme.chatgpt)
            } else {
                Text("\(clampPct(store.antigravityData.gemini5h ?? 83))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(ModelTheme.gemini)
                
                Text("/")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.white)
                
                Text("\(clampPct(store.antigravityData.geminiWeekly ?? 85))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(ModelTheme.gemini)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 26)
    }
}

// MARK: - Multi-Screen Island Controller (Precise Hover Target)
struct ScreenIslandContainer: View {
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            ScreenIslandView(isExpanded: $isExpanded)
                .onHover { hovering in
                    withAnimation(.snappy(duration: 0.20, extraBounce: 0.0)) {
                        isExpanded = hovering
                    }
                }
            Spacer()
        }
        .frame(width: 315, height: 520)
    }
}

@MainActor
final class MultiScreenIslandManager {
    static let shared = MultiScreenIslandManager()
    private var panels: [NSPanel] = []
    
    func setupAllScreens() {
        for p in panels {
            p.orderOut(nil)
        }
        panels.removeAll()
        
        let targetWidth: CGFloat = 315
        let targetHeight: CGFloat = 520
        
        for screen in NSScreen.screens {
            let screenFrame = screen.frame
            let x = screenFrame.midX - (targetWidth / 2)
            let y = screenFrame.maxY - targetHeight
            
            let panel = NSPanel(
                contentRect: NSRect(x: x, y: y, width: targetWidth, height: targetHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.hasShadow = false
            
            let hosting = NSHostingView(rootView: ScreenIslandContainer())
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.clear.cgColor
            
            panel.contentView = hosting
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }
}

// MARK: - App Delegate
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MultiScreenIslandManager.shared.setupAllScreens()
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                MultiScreenIslandManager.shared.setupAllScreens()
            }
        }
    }
}

// MARK: - Main Entry Point
@main
struct TokenIslandApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

// MARK: - Shell Process Runners
func runShell(_ command: String) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func runCommand(_ launchPath: String, _ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func matches(for regex: String, in text: String) -> [String] {
    do {
        let r = try NSRegularExpression(pattern: regex)
        let results = r.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return results.compactMap {
            guard $0.numberOfRanges > 1,
                  let range = Range($0.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    } catch {
        return []
    }
}

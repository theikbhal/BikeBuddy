import SwiftUI
import Charts
import UserNotifications

enum Cat: String, CaseIterable, Codable, Identifiable {
  case petrol = "Petrol", repair = "Repair", puncture = "Puncture", service = "Maintenance", gear = "Accessories"
  var id: String { rawValue }
  var emoji: String {
    switch self {
    case .petrol: return "⛽"
    case .repair: return "🔧"
    case .puncture: return "🛞"
    case .service: return "🧰"
    case .gear: return "🪖"
    }
  }
}
enum Period: String, CaseIterable {
  case week = "Week", month = "Month", year = "Year"
  var comp: Calendar.Component { self == .week ? .weekOfYear : self == .month ? .month : .year }
}
struct Expense: Codable, Identifiable { var id = UUID(); var date = Date(); var cat: Cat; var amount: Double; var note = "" }
struct Ride: Codable, Identifiable { var id = UUID(); var date = Date(); var km: Double; var route: String; var note = "" }

final class Store: ObservableObject {
  struct Saved: Codable { var expenses: [Expense] = []; var rides: [Ride] = []; var xp = 0; var coins = 0; var onboarded = false; var repo = "" }
  @Published var d = Saved() { didSet { save() } }
  let url: URL
  init() {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BikeBuddy")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    url = dir.appendingPathComponent("data.json")
    if let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Saved.self, from: data) { d = s }
  }
  func save() { try? JSONEncoder().encode(d).write(to: url) }
  var level: Int { d.xp / 100 + 1 }
  func total(_ p: Period, _ c: Cat? = nil) -> Double {
    d.expenses.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: p.comp) && (c == nil || $0.cat == c) }.reduce(0) { $0 + $1.amount }
  }
  var streak: Int {
    let cal = Calendar.current
    let days = Set(d.expenses.map { cal.startOfDay(for: $0.date) } + d.rides.map { cal.startOfDay(for: $0.date) })
    var day = cal.startOfDay(for: Date()); if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
    var n = 0; while days.contains(day) { n += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
    return n
  }
  var totalKm: Double { d.rides.reduce(0) { $0 + $1.km } }
  var badges: [(String, String, Bool)] {
    [("🥉", "First entry", !d.expenses.isEmpty), ("🔥", "3-day streak", streak >= 3), ("🏆", "7-day streak", streak >= 7),
     ("🛣️", "100 km", totalKm >= 100), ("⛽", "10 fill-ups", d.expenses.filter { $0.cat == .petrol }.count >= 10), ("🎮", "Level 5", level >= 5)]
  }
  func add(_ e: Expense) { d.expenses.insert(e, at: 0); d.xp += 10; d.coins += 5 }
  func add(_ r: Ride) { d.rides.insert(r, at: 0); d.xp += 5; d.coins += Int(r.km / 5) }
}

struct Dash: View {
  @EnvironmentObject var s: Store
  @State var per = Period.month; @State var amt = ""; @State var cat = Cat.petrol; @State var note = ""; @State var bounce = false
  var nudge: String {
    let cal = Calendar.current
    return s.d.expenses.contains { cal.isDateInToday($0.date) } || s.d.rides.contains { cal.isDateInToday($0.date) }
      ? "✅ Logged today. Streak safe!" : "👉 Nothing logged today. Keep your 🔥 \(s.streak) streak alive!"
  }
  var body: some View {
    ScrollView { VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("🏍️").font(.system(size: 44)).offset(x: bounce ? 8 : -8)
          .animation(.easeInOut(duration: 0.8).repeatForever(), value: bounce).onAppear { bounce = true }
        VStack(alignment: .leading) { Text("Level \(s.level)").font(.title2.bold()); ProgressView(value: Double(s.d.xp % 100), total: 100).frame(width: 160) }
        Spacer(); Text("🔥 \(s.streak)").font(.title); Text("🪙 \(s.d.coins)").font(.title)
      }
      Text(nudge).foregroundStyle(.secondary)
      Picker("", selection: $per) { ForEach(Period.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
      Text("₹\(Int(s.total(per)))").font(.system(size: 44, weight: .bold, design: .rounded))
      Chart(Cat.allCases) { c in BarMark(x: .value("Cat", c.emoji), y: .value("₹", s.total(per, c))).foregroundStyle(.orange) }.frame(height: 160)
      HStack {
        Picker("", selection: $cat) { ForEach(Cat.allCases) { Text("\($0.emoji) \($0.rawValue)").tag($0) } }.frame(width: 170)
        TextField("₹ amount", text: $amt).frame(width: 90); TextField("note", text: $note)
        Button("Add") { if let a = Double(amt) { withAnimation { s.add(Expense(cat: cat, amount: a, note: note)) }; amt = ""; note = "" } }.keyboardShortcut(.return)
      }
      HStack { ForEach(s.badges, id: \.1) { b in VStack { Text(b.0).font(.largeTitle).opacity(b.2 ? 1 : 0.2); Text(b.1).font(.caption2) } } }
      Button("😅 Copy report for wife") {
        let t = "🏍️ Bike spend — week ₹\(Int(s.total(.week))), month ₹\(Int(s.total(.month))), year ₹\(Int(s.total(.year))). Rode \(Int(s.totalKm)) km. Cost/km: ₹\(s.totalKm > 0 ? Int(s.total(.year) / s.totalKm) : 0)"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string)
      }
      ForEach(s.d.expenses.prefix(8)) { e in Text("\(e.cat.emoji) ₹\(Int(e.amount))  \(e.date.formatted(date: .abbreviated, time: .omitted))  \(e.note)") }
    }.padding() }
  }
}

struct Rides: View {
  @EnvironmentObject var s: Store
  @State var km = ""; @State var route = ""; @State var note = ""
  var routes: [(String, Int, Double)] {
    Dictionary(grouping: s.d.rides, by: { $0.route }).map { ($0.key, $0.value.count, $0.value.reduce(0) { $0 + $1.km }) }.sorted { $0.1 > $1.1 }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("🛣️ \(Int(s.totalKm)) km total").font(.title.bold())
      HStack {
        TextField("km", text: $km).frame(width: 70); TextField("route (e.g. Home→Office)", text: $route); TextField("notes", text: $note)
        Button("Add ride") { if let k = Double(km) { s.add(Ride(km: k, route: route.isEmpty ? "Unnamed" : route, note: note)); km = ""; note = "" } }
      }
      Text("🔁 Recurring routes").font(.headline)
      ForEach(routes, id: \.0) { r in Text("📍 \(r.0): \(r.1)× · \(Int(r.2)) km") }
      if let top = routes.first, top.1 >= 3 {
        Text("🧭 Tip: “\(top.0)” is your most repeated route. Chain errands on it, avoid peak traffic, ride at a steady speed, keep tyre pressure right.").padding().background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
      }
      List(s.d.rides) { r in Text("\(r.date.formatted(date: .abbreviated, time: .omitted)) · \(r.km, specifier: "%.1f") km · \(r.route) \(r.note)") }
    }.padding()
  }
}

final class Game {
  var p = CGPoint(x: 240, y: 150); var fuel = 100.0; var cash = 0; var orders = 0; var carrying = false; var keys = Set<KeyEquivalent>(); var last = Date()
  let shop = CGPoint(x: 50, y: 50), home = CGPoint(x: 430, y: 50), pump = CGPoint(x: 240, y: 260)
  func near(_ a: CGPoint) -> Bool { hypot(a.x - p.x, a.y - p.y) < 30 }
  func step() {
    let dt = min(Date().timeIntervalSince(last), 0.05); last = Date()
    if fuel > 0 {
      let v = 150 * dt
      if keys.contains(.leftArrow) { p.x -= v }; if keys.contains(.rightArrow) { p.x += v }
      if keys.contains(.upArrow) { p.y -= v }; if keys.contains(.downArrow) { p.y += v }
      p.x = min(max(p.x, 15), 465); p.y = min(max(p.y, 15), 285); fuel -= dt * 2.5
    }
    if near(pump) { fuel = min(100, fuel + 30 * dt) }          // wait at the shop to fill
    if near(shop) && !carrying { carrying = true }              // pick order
    if near(home) && carrying { carrying = false; cash += 20; orders += 1 } // deliver
  }
}
struct GameView: View {
  @EnvironmentObject var s: Store
  let g = Game(); @FocusState var f: Bool
  var body: some View {
    VStack {
      Text("🎮 Delivery Rider: arrows to move. 🍔 pick → 🏠 deliver → earn ₹. Refuel at ⛽").font(.headline)
      TimelineView(.animation) { _ in
        Canvas { ctx, _ in
          g.step()
          func d(_ e: String, _ p: CGPoint, _ z: CGFloat = 32) { ctx.draw(Text(e).font(.system(size: z)), at: p) }
          d("🍔", g.shop); d("🏠", g.home); d("⛽", g.pump); d(g.carrying ? "🏍️📦" : "🏍️", g.p, 36)
          ctx.draw(Text("⛽ \(Int(g.fuel))%   💰 ₹\(g.cash)   📦 \(g.orders)" + (g.fuel <= 0 ? "   EMPTY! push to ⛽ (cash out & restart)" : "")), at: CGPoint(x: 240, y: 12))
        }
      }.frame(width: 480, height: 300).background(Color.gray.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 12))
        .focusable().focused($f).onAppear { f = true }
        .onKeyPress(phases: [.down, .up]) { k in if k.phase == .down { g.keys.insert(k.key) } else { g.keys.remove(k.key) }; return .handled }
      Button("💸 Cash out to coins") { s.d.coins += g.cash; s.d.xp += g.orders * 5; g.cash = 0; g.orders = 0; if g.fuel <= 0 { g.fuel = 30 } }
    }.padding()
  }
}

struct Help: View {
  @EnvironmentObject var s: Store
  let prompts = ["Analyse my bike expenses (paste data) and tell me where I can save money.", "Plan the most fuel-efficient route for these errands: …", "Create a maintenance schedule for my bike model: …"]
  var body: some View {
    ScrollView { VStack(alignment: .leading, spacing: 10) {
      Text("❓ Help").font(.title.bold())
      Text("• Log every expense → +10 XP, +5 🪙\n• Log daily to build 🔥 streak\n• 100 XP = new level\n• Screenshot: ⌘⇧4 · Screen record: ⌘⇧5\n• Data: ~/Library/Application Support/BikeBuddy/data.json")
      Text("🤖 AI prompts").font(.headline)
      ForEach(prompts, id: \.self) { p in HStack { Text(p); Spacer(); Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(p, forType: .string) } } }
      Text("🐙 GitHub repo link").font(.headline)
      TextField("https://github.com/you/BikeBuddy", text: $s.d.repo)
      if let u = URL(string: s.d.repo), !s.d.repo.isEmpty { Link("Open repo", destination: u) }
    }.padding() }
  }
}

struct Root: View {
  @EnvironmentObject var s: Store
  var body: some View {
    TabView {
      Dash().tabItem { Label("Dashboard", systemImage: "chart.bar") }
      Rides().tabItem { Label("Rides", systemImage: "bicycle") }
      GameView().tabItem { Label("Game", systemImage: "gamecontroller") }
      Help().tabItem { Label("Help", systemImage: "questionmark.circle") }
    }
    .sheet(isPresented: Binding(get: { !s.d.onboarded }, set: { _ in })) {
      VStack(spacing: 14) {
        Text("🏍️ Welcome to BikeBuddy").font(.largeTitle.bold())
        Text("⛽ Track petrol, repairs, punctures, maintenance & accessories\n🔥 Build streaks · 🏆 earn badges · 🪙 collect coins\n🛣️ Log rides & find efficient routes\n🎮 Play the delivery mini-game")
        Button("Let's ride") { s.d.onboarded = true }.keyboardShortcut(.return)
      }.padding(40)
    }
  }
}

@main struct BikeBuddyApp: App {
  @StateObject var store = Store()
  var body: some Scene {
    WindowGroup { Root().environmentObject(store).frame(minWidth: 760, minHeight: 560).onAppear {
      let c = UNUserNotificationCenter.current(); c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
        guard ok else { return }
        let m = UNMutableNotificationContent(); m.title = "🏍️ BikeBuddy"; m.body = "Log today's ride or expense to keep your streak 🔥"
        var t = DateComponents(); t.hour = 20
        c.add(UNNotificationRequest(identifier: "daily", content: m, trigger: UNCalendarNotificationTrigger(dateMatching: t, repeats: true)))
      } } }
  }
}

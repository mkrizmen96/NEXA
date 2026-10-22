import SwiftUI
import LocalAuthentication
import AppIntents

@main
struct NEXAApp: App {
    @StateObject private var store = Store()

    init() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Theme.card)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.bg)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

enum Tab: Hashable { case home, transactions, analytics, plan, settings }

enum Route: Hashable {
    case tx(String)
    case editTx(String)
    case newTx(TxType, String?)
    case category(String, Date, Date)
    case day(Date)
    case bill(String)
    case newBill(RecurringKind)
    case editBill(String)
    case accounts, categories, reports, data, insights
}

/// One navigation stack per tab. Tapping the current tab returns to its first screen.
final class Router: ObservableObject {
    @Published var tab: Tab = .home
    @Published var home: [Route] = []
    @Published var transactions: [Route] = []
    @Published var analytics: [Route] = []
    @Published var plan: [Route] = []
    @Published var settings: [Route] = []

    func push(_ r: Route) {
        switch tab {
        case .home: home.append(r)
        case .transactions: transactions.append(r)
        case .analytics: analytics.append(r)
        case .plan: plan.append(r)
        case .settings: settings.append(r)
        }
    }

    func pop() {
        switch tab {
        case .home: if !home.isEmpty { home.removeLast() }
        case .transactions: if !transactions.isEmpty { transactions.removeLast() }
        case .analytics: if !analytics.isEmpty { analytics.removeLast() }
        case .plan: if !plan.isEmpty { plan.removeLast() }
        case .settings: if !settings.isEmpty { settings.removeLast() }
        }
    }

    func reset(_ t: Tab) {
        switch t {
        case .home: home = []
        case .transactions: transactions = []
        case .analytics: analytics = []
        case .plan: plan = []
        case .settings: settings = []
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @StateObject private var router = Router()
    @Environment(\.scenePhase) private var phase
    @State private var locked = false

    private var tabBinding: Binding<Tab> {
        Binding(get: { router.tab }, set: { new in
            if new == router.tab { router.reset(new) }   // tap Home while on Home → back to the dashboard
            router.tab = new
        })
    }

    var body: some View {
        TabView(selection: tabBinding) {
            NavigationStack(path: $router.home) { HomeView().destinations() }
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(Tab.home)
            NavigationStack(path: $router.transactions) { TransactionsView().destinations() }
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }.tag(Tab.transactions)
            NavigationStack(path: $router.analytics) { AnalyticsView().destinations() }
                .tabItem { Label("Analytics", systemImage: "chart.pie.fill") }.tag(Tab.analytics)
            NavigationStack(path: $router.plan) { PlanView().destinations() }
                .tabItem { Label("Budgets & Bills", systemImage: "calendar") }.tag(Tab.plan)
            NavigationStack(path: $router.settings) { SettingsView().destinations() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(Tab.settings)
        }
        .tint(Theme.mint)
        .environmentObject(router)
        .overlay(alignment: .bottom) { ToastHost().padding(.bottom, 60) }
        .fullScreenCover(isPresented: Binding(get: { !store.data.settings.onboarded }, set: { _ in })) {
            OnboardingView().environmentObject(store)
        }
        .overlay { if locked { LockView { locked = false } } }
        .onAppear { locked = store.data.settings.appLock; consumeQuickEntry() }
        .onChange(of: phase) { _, p in
            if p == .background && store.data.settings.appLock { locked = true }
            if p == .active { consumeQuickEntry() }
        }
        .onReceive(NotificationCenter.default.publisher(for: QuickEntry.notification)) { _ in consumeQuickEntry() }
    }

    /// Opened from Siri / Shortcuts ("Add expense in NEXA").
    private func consumeQuickEntry() {
        guard store.data.settings.onboarded, let raw = UserDefaults.standard.string(forKey: QuickEntry.key) else { return }
        UserDefaults.standard.removeObject(forKey: QuickEntry.key)
        router.tab = .home
        router.home = [.newTx(TxType(rawValue: raw) ?? .EXPENSE, nil)]
    }
}

extension View {
    func destinations() -> some View {
        navigationDestination(for: Route.self) { RouteView(route: $0) }
    }
}

struct RouteView: View {
    let route: Route
    var body: some View {
        switch route {
        case .tx(let id): TransactionDetailView(id: id)
        case .editTx(let id): TransactionFormView(editId: id, initialType: .EXPENSE, initialCategory: nil)
        case .newTx(let type, let cat): TransactionFormView(editId: nil, initialType: type, initialCategory: cat)
        case .category(let id, let from, let to): CategoryDetailView(id: id, from: from, to: to)
        case .day(let date): DayView(date: date)
        case .bill(let id): BillDetailView(id: id)
        case .newBill(let kind): BillFormView(editId: nil, initialKind: kind)
        case .editBill(let id): BillFormView(editId: id, initialKind: .BILL)
        case .accounts: AccountsView()
        case .categories: CategoriesView()
        case .reports: ReportsView()
        case .data: DataView()
        case .insights: InsightsView()
        }
    }
}

/// Short message with Undo, shown above the tab bar.
struct ToastHost: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if let t = store.toast {
            HStack {
                Text(t.text).font(.subheadline)
                Spacer()
                if t.canUndo {
                    Button("Undo") { store.undo(); store.toast = nil }.foregroundStyle(Theme.mint).fontWeight(.semibold)
                }
            }
            .padding(14)
            .background(Theme.cardHigh)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: t.id) {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                if store.toast?.id == t.id { withAnimation { store.toast = nil } }
            }
        }
    }
}

/// Face ID / passcode lock (Settings → App lock).
struct LockView: View {
    let onUnlock: () -> Void
    @State private var error: String?
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(Theme.mint)
            Text("NEXA is locked").font(.title3.weight(.semibold))
            if let error { Text(error).font(.footnote).foregroundStyle(Theme.muted) }
            Button("Unlock") { authenticate() }.buttonStyle(PrimaryButtonStyle()).frame(width: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { authenticate() }
    }

    private func authenticate() {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            onUnlock() // no passcode set on the phone: nothing to check against
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your finances") { ok, e in
            DispatchQueue.main.async {
                if ok { onUnlock() } else { error = e?.localizedDescription }
            }
        }
    }
}

// MARK: - Siri & Shortcuts quick entry

enum QuickEntry {
    static let key = "nexa.quickEntry"
    static let notification = Notification.Name("nexa.quickEntry")
    static func request(_ type: String) {
        UserDefaults.standard.set(type, forKey: key)
        DispatchQueue.main.async { NotificationCenter.default.post(name: notification, object: nil) }
    }
}

struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Add expense"
    static var description = IntentDescription("Opens NEXA on a new expense.")
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        QuickEntry.request("EXPENSE")
        return .result()
    }
}

struct AddIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Add income"
    static var description = IntentDescription("Opens NEXA on a new income entry.")
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        QuickEntry.request("INCOME")
        return .result()
    }
}

struct NexaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddExpenseIntent(), phrases: ["Add expense in \(.applicationName)"],
                    shortTitle: "Add expense", systemImageName: "minus.circle")
        AppShortcut(intent: AddIncomeIntent(), phrases: ["Add income in \(.applicationName)"],
                    shortTitle: "Add income", systemImageName: "plus.circle")
    }
}

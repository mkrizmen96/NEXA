import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var reservedText = ""
    @State private var editReserved = false

    var body: some View {
        let s = store.data.settings
        List {
            Section {
                nav("building.columns.fill", "Accounts & payment methods", "\(store.data.accounts.filter { !$0.archived }.count) active", .accounts)
                nav("square.grid.2x2.fill", "Categories", "Add, rename, reorder, archive", .categories)
                nav("chart.bar.doc.horizontal.fill", "Reports & export", "Monthly, annual, CSV, Excel, PDF", .reports)
                nav("externaldrive.fill", "Backup, restore & data", "Backup file, demo data, delete everything", .data)
                nav("lightbulb.fill", "Insights", "Spending changes, estimates and alerts", .insights)
            }
            .listRowBackground(Theme.card)
            Section("Alerts") {
                Toggle("Budget alert at 80%", isOn: binding(\.alert80))
                Toggle("Budget alert at 90%", isOn: binding(\.alert90))
                Toggle("Budget alert at 100%", isOn: binding(\.alert100))
                Toggle("Bill reminders", isOn: binding(\.billReminders))
                Toggle("Insights", isOn: binding(\.insights))
            }
            .listRowBackground(Theme.card)
            Section {
                Button { reservedText = Money.plain(s.reservedFunds); editReserved = true } label: {
                    LabelValue(label: "Other reserved funds", value: Money.format(s.reservedFunds))
                }
            } header: { Text("Available to spend") } footer: {
                Text("Money set aside (emergency fund, goals). It's subtracted from Available to spend, with unpaid bills and the savings still to put aside.")
            }
            .listRowBackground(Theme.card)
            Section {
                Toggle("Lock with Face ID / passcode", isOn: binding(\.appLock))
            } header: { Text("Privacy") } footer: { Text("Asks for Face ID (or your passcode) every time NEXA is opened.") }
            .listRowBackground(Theme.card)
            Section {
                Text("Say \"Add expense in NEXA\" or \"Add income in NEXA\" to Siri, or add them from the Shortcuts app to your Home Screen or Action Button.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            } header: { Text("Quick entry") }
            .listRowBackground(Theme.card)
            Section {
                Text("NEXA Personal Finance 2.2 for iPhone · works offline. Everything is entered by you and stored only on this phone; nothing connects to your bank.")
                    .font(.footnote).foregroundStyle(Theme.faint)
            }
            .listRowBackground(Color.clear)
        }
        .nexaBackground()
        .navigationTitle("Settings")
        .alert("Other reserved funds", isPresented: $editReserved) {
            TextField("RM", text: $reservedText).keyboardType(.decimalPad)
            Button("Save") { if let v = Money.parse(reservedText.isEmpty ? "0" : reservedText), v >= 0 { store.updateSettings { $0.reservedFunds = v } } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func binding(_ key: WritableKeyPath<Settings, Bool>) -> Binding<Bool> {
        Binding(get: { store.data.settings[keyPath: key] }, set: { v in store.updateSettings { $0[keyPath: key] = v } })
    }

    private func nav(_ icon: String, _ title: String, _ sub: String, _ route: Route) -> some View {
        Button { router.push(route) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Theme.mint).frame(width: 34, height: 34).background(Theme.mint.opacity(0.12)).clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Theme.text)
                    Text(sub).font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.faint)
            }
        }
    }
}

// MARK: - Accounts

struct AccountsView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Account?
    @State private var adding = false
    @State private var reconcileTarget: Account?
    @State private var reconcileText = ""

    var body: some View {
        let d = store.data
        ScrollView {
            VStack(spacing: 10) {
                Card {
                    Text("Total balance").font(.caption).foregroundStyle(Theme.muted)
                    Text(Money.format(Finance.totalBalance(d))).font(.title2.weight(.semibold))
                    Text("Credit card balances are what you owe, so they count as negative.").font(.caption).foregroundStyle(Theme.muted)
                }
                if d.accounts.isEmpty { EmptyStateView(title: "No accounts yet", message: "Add a bank account, e-wallet, cash or credit card.") }
                ForEach(d.accounts.sorted { !$0.archived && $1.archived }) { a in
                    let b = Finance.balance(d, a.id)
                    Card {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.name + (a.archived ? " (archived)" : "")).font(.headline).foregroundStyle(a.archived ? Theme.muted : Theme.text)
                                Text(a.type.label).font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(Money.format(b)).font(.headline).foregroundStyle(b < 0 ? Theme.red : Theme.text)
                        }
                        Button("Reconcile with actual balance") { reconcileText = Money.plain(b); reconcileTarget = a }
                            .font(.subheadline.weight(.medium)).foregroundStyle(Theme.mint)
                    }
                    .onTapGesture { editing = a }
                }
                Button("Add account") { adding = true }.buttonStyle(SecondaryButtonStyle())
            }
            .padding(16)
        }
        .nexaBackground()
        .navigationTitle("Accounts")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
        .sheet(item: $editing) { a in AccountSheet(existing: a) }
        .sheet(isPresented: $adding) { AccountSheet(existing: nil) }
        .alert("Actual balance", isPresented: Binding(get: { reconcileTarget != nil }, set: { if !$0 { reconcileTarget = nil } })) {
            TextField("RM", text: $reconcileText).keyboardType(.numbersAndPunctuation)
            Button("Save") { if let a = reconcileTarget, let v = Money.parse(reconcileText) { store.reconcile(a.id, actual: v) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the real balance from your bank app. NEXA records the difference as a reconciliation adjustment (not income or expense).")
        }
    }
}

struct AccountSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let existing: Account?
    @State private var name = ""
    @State private var type: AccountType = .BANK
    @State private var opening = ""
    @State private var archived = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (Maybank savings)", text: $name)
                    Picker("Type", selection: $type) { ForEach(AccountType.allCases, id: \.self) { Text($0.label).tag($0) } }
                    TextField(type == .CREDIT_CARD ? "Amount owed when you start (RM)" : "Opening balance (RM)", text: $opening).keyboardType(.decimalPad)
                } footer: {
                    Text(type == .CREDIT_CARD ? "Card purchases are expenses. Paying the card from your bank is a transfer, so nothing is counted twice."
                                              : "The balance before the transactions you record in NEXA.")
                }
                if existing != nil { Section { Toggle("Archived", isOn: $archived) } footer: { Text("Hidden from pickers and the total balance.") } }
                if let error { Section { Text(error).foregroundStyle(Theme.red) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(existing == nil ? "New account" : "Edit account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Enter a name"; return }
                        guard let v = opening.isEmpty ? 0 : Money.parse(opening) else { error = "Enter a valid amount"; return }
                        var a = existing ?? Account(name: name, type: type)
                        a.name = name.trimmingCharacters(in: .whitespaces)
                        a.type = type
                        a.openingBalance = type == .CREDIT_CARD ? -abs(v) : v
                        a.archived = archived
                        store.saveAccount(a)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let e = existing {
                    name = e.name; type = e.type; archived = e.archived
                    opening = Money.plain(e.type == .CREDIT_CARD ? -e.openingBalance : e.openingBalance)
                }
            }
        }
    }
}

// MARK: - Categories

struct CategoriesView: View {
    @EnvironmentObject var store: Store
    @State private var kind: CategoryKind = .EXPENSE
    @State private var editing: Category?
    @State private var adding = false

    var body: some View {
        let list = store.data.categories.filter { $0.kind == kind }.sorted { ($0.archived ? 1 : 0, $0.order) < ($1.archived ? 1 : 0, $1.order) }
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $kind) { Text("Expenses").tag(CategoryKind.EXPENSE); Text("Income").tag(CategoryKind.INCOME) }.pickerStyle(.segmented)
                Text("Transfers between your own accounts are kept separate and never use these categories.").font(.caption).foregroundStyle(Theme.muted)
                ForEach(list) { c in
                    HStack(spacing: 10) {
                        CategoryBadge(category: c, size: 34)
                        Text(c.name + (c.archived ? " (archived)" : "")).foregroundStyle(c.archived ? Theme.muted : Theme.text)
                        Spacer()
                        if !c.archived {
                            Button { store.moveCategory(c, up: true) } label: { Image(systemName: "chevron.up") }.buttonStyle(.plain)
                            Button { store.moveCategory(c, up: false) } label: { Image(systemName: "chevron.down") }.buttonStyle(.plain)
                        }
                    }
                    .foregroundStyle(Theme.muted)
                    .padding(10)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .onTapGesture { editing = c }
                }
            }
            .padding(16)
        }
        .nexaBackground()
        .navigationTitle("Categories")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
        .sheet(item: $editing) { c in CategorySheet(existing: c, kind: c.kind) }
        .sheet(isPresented: $adding) { CategorySheet(existing: nil, kind: kind) }
    }
}

struct CategorySheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let existing: Category?
    let kind: CategoryKind
    @State private var name = ""
    @State private var color = UI.colors[0]
    @State private var icon = "more"
    @State private var archived = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Name", text: $name) }
                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                        ForEach(UI.colors, id: \.self) { c in
                            Circle().fill(Color(hex: c)).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(c == color ? Theme.text : .clear, lineWidth: 2))
                                .onTapGesture { color = c }
                        }
                    }
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(UI.iconKeys, id: \.self) { k in
                            Image(systemName: UI.symbol(k)).foregroundStyle(Color(hex: color))
                                .frame(width: 38, height: 38)
                                .background(k == icon ? Color(hex: color).opacity(0.25) : Theme.cardHigh)
                                .clipShape(Circle())
                                .onTapGesture { icon = k }
                        }
                    }
                }
                if existing != nil { Section { Toggle("Archived", isOn: $archived) } footer: { Text("Hidden when adding transactions; history keeps it.") } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(existing == nil ? "New category" : "Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty else { return }
                        var c = existing ?? Category(name: n, kind: kind, color: color, icon: icon,
                                                     order: store.data.categories.filter { $0.kind == kind }.count)
                        c.name = n; c.color = color; c.icon = icon; c.archived = archived
                        store.saveCategory(c)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let e = existing { name = e.name; color = e.color; icon = e.icon; archived = e.archived }
            }
        }
    }
}

// MARK: - Reports

enum ReportRange: String, CaseIterable { case thisMonth = "This month", lastMonth = "Last month", thisYear = "This year", lastYear = "Last year", custom = "Custom" }

struct ReportsView: View {
    @EnvironmentObject var store: Store
    @State private var range: ReportRange = .thisMonth
    @State private var customFrom = YM.now().first
    @State private var customTo = D.today
    @State private var share: ShareItem?
    @State private var failed: String?

    private var dates: (Date, Date) {
        let now = YM.now()
        switch range {
        case .thisMonth: return (now.first, now.last)
        case .lastMonth: return (now.plus(-1).first, now.plus(-1).last)
        case .thisYear: return (YM(year: now.year, month: 1).first, YM(year: now.year, month: 12).last)
        case .lastYear: return (YM(year: now.year - 1, month: 1).first, YM(year: now.year - 1, month: 12).last)
        case .custom: return (D.startOfDay(customFrom), max(D.startOfDay(customFrom), D.startOfDay(customTo)))
        }
    }

    var body: some View {
        let d = store.data
        let (from, to) = dates
        let r = Reports.build(d, from, to)
        let tag = "\(D.isoDay(from))_to_\(D.isoDay(to))"
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
              Group {
                ChipRow(options: ReportRange.allCases, selected: $range) { $0.rawValue }
                if range == .custom {
                    DatePicker("From", selection: $customFrom, displayedComponents: .date)
                    DatePicker("To", selection: $customTo, displayedComponents: .date)
                }
                if let failed { Card { Text(failed).foregroundStyle(Theme.red) } }
              }
                Card {
                    Text("Summary").font(.headline)
                    ForEach(Reports.lines(r), id: \.0) { k, v in LabelValue(label: k, value: v) }
                }
                Card {
                    Text("Expenses by category").font(.headline)
                    if r.expenses.isEmpty { Text("No expenses in this period.").foregroundStyle(Theme.muted) }
                    ForEach(r.expenses) { s in LabelValue(label: "\(s.category?.name ?? "Uncategorised") · \(Int(s.share * 100))%", value: Money.format(s.amount)) }
                }
                Card {
                    Text("Income by category").font(.headline)
                    if r.incomes.isEmpty { Text("No income in this period.").foregroundStyle(Theme.muted) }
                    ForEach(r.incomes) { s in LabelValue(label: s.category?.name ?? "Uncategorised", value: Money.format(s.amount), color: Theme.mint) }
                }
                if r.months.count > 1 {
                    Card {
                        Text("Month by month").font(.headline)
                        ForEach(r.months) { m in
                            LabelValue(label: D.monthYearF.string(from: m.month.first),
                                       value: "\(Money.format(m.income)) in · \(Money.format(m.expense)) out", color: m.net < 0 ? Theme.red : Theme.text)
                        }
                    }
                }
                Card {
                    Text("Commitment payments").font(.headline)
                    if r.bills.isEmpty { Text("No bills due in this period.").foregroundStyle(Theme.muted) }
                    ForEach(r.bills) { b in
                        LabelValue(label: "\(D.dayShortF.string(from: b.due)) · \(b.recurring.name)", value: "\(Money.format(b.amount)) · \(UI.billLabel(b))", color: Theme.status(b.status))
                    }
                }
              Group {
                SectionTitle(text: "Export \(D.dayShortF.string(from: from)) – \(D.dayF.string(from: to))")
                Button("PDF report") { export("nexa-report-\(tag).pdf", Reports.pdf(d, r)) }.buttonStyle(PrimaryButtonStyle())
                HStack(spacing: 8) {
                    Button("CSV") { export("nexa-transactions-\(tag).csv", Data(Reports.csv(d, from, to, excel: false).utf8)) }.buttonStyle(SecondaryButtonStyle())
                    Button("Excel (CSV)") { export("nexa-transactions-\(tag)-excel.csv", Data(Reports.csv(d, from, to, excel: true).utf8)) }.buttonStyle(SecondaryButtonStyle())
                }
                Text("Exports use exactly the transactions in this report. Choose Save to Files, AirDrop, WhatsApp or email in the share sheet.")
                    .font(.caption).foregroundStyle(Theme.muted)
              }
            }
            .padding(16)
        }
        .nexaBackground()
        .navigationTitle("Reports")
        .sheet(item: $share) { s in ShareSheet(url: s.url) }
    }

    private func export(_ name: String, _ data: Data) {
        if let url = Reports.tempFile(name, data) { failed = nil; share = ShareItem(url: url) }
        else { failed = "The file could not be created. Nothing was exported." }
    }
}

// MARK: - Backup & data

struct DataView: View {
    @EnvironmentObject var store: Store
    @State private var share: ShareItem?
    @State private var importing = false
    @State private var pendingRestore: AppData?
    @State private var status: (Bool, String)?
    @State private var confirmDeleteAll = false
    @State private var confirmRemoveDemo = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let status { Card { Text(status.1).foregroundStyle(status.0 ? Theme.mint : Theme.red) } }
                Card {
                    Text("Backup").font(.headline)
                    Text("Saves everything to one file. In the share sheet choose Save to Files (iCloud Drive) or Google Drive. The same file also restores on the Android app.")
                        .font(.caption).foregroundStyle(Theme.muted)
                    Button("Create backup file") {
                        if let data = store.backupData(), let url = Reports.tempFile("nexa-backup-\(D.isoDay(Date())).json", data) {
                            share = ShareItem(url: url)
                        } else { status = (false, "Backup failed. Nothing was saved.") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                Card {
                    Text("Restore").font(.headline)
                    Text("Replaces all current data with a backup file. You'll be asked to confirm first.").font(.caption).foregroundStyle(Theme.muted)
                    Button("Choose backup file") { importing = true }.buttonStyle(SecondaryButtonStyle())
                }
                Card {
                    Text("Demo data").font(.headline)
                    Text(store.data.hasDemo ? "Demo records are marked \"(demo)\". Remove them before tracking your real finances."
                                            : "Adds labelled sample accounts, transactions, bills and budgets to explore the app.")
                        .font(.caption).foregroundStyle(Theme.muted)
                    if store.data.hasDemo {
                        Button("Remove demo data") { confirmRemoveDemo = true }.buttonStyle(SecondaryButtonStyle(color: Theme.amber))
                    } else {
                        Button("Add demo data") { store.loadDemo() }.buttonStyle(SecondaryButtonStyle())
                    }
                }
                Card {
                    Text("Delete all data").font(.headline).foregroundStyle(Theme.red)
                    Text("Permanently removes everything NEXA stores on this phone. Create a backup first if you might need it.").font(.caption).foregroundStyle(Theme.muted)
                    Button("Delete everything") { confirmDeleteAll = true }.buttonStyle(SecondaryButtonStyle(color: Theme.red))
                }
                Text("Your data is stored only in this app's private storage on this phone. Nothing is sent to any server.").font(.caption).foregroundStyle(Theme.faint)
            }
            .padding(16)
        }
        .nexaBackground()
        .navigationTitle("Backup & data")
        .sheet(item: $share) { s in ShareSheet(url: s.url) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data, .item]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do { pendingRestore = try Store.readBackup(try Data(contentsOf: url)) }
                catch { status = (false, error.localizedDescription) }
            case .failure(let e):
                status = (false, e.localizedDescription)
            }
        }
        .confirmationDialog("Restore this backup?", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }), titleVisibility: .visible) {
            Button("Restore", role: .destructive) { if let b = pendingRestore { store.restore(b); status = (true, "Backup restored.") } }
        } message: {
            if let b = pendingRestore { Text("It has \(b.accounts.count) accounts, \(b.transactions.count) transactions and \(b.recurring.count) bills. Your current data will be replaced.") }
        }
        .confirmationDialog("Delete all data?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { store.deleteAll(); status = (true, "All data deleted.") }
        } message: { Text("This can't be undone.") }
        .confirmationDialog("Remove demo data?", isPresented: $confirmRemoveDemo, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { store.removeDemo() }
        } message: { Text("All records marked (demo) are removed. Your own data stays.") }
    }
}

// MARK: - Insights

struct InsightsView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let list = Insights.build(store.data)
        ScrollView {
            VStack(spacing: 10) {
                if !store.data.settings.insights {
                    EmptyStateView(title: "Insights are off", message: "Turn them on in Settings → Alerts.")
                } else if list.isEmpty {
                    EmptyStateView(title: "Not enough data yet", message: "Insights appear once you have a few weeks of transactions.")
                }
                ForEach(list) { i in
                    Card {
                        switch i.kind {
                        case .fact: Tag(text: "Fact", color: Theme.mint)
                        case .estimate: Tag(text: "Estimate", color: Theme.blue)
                        case .alert: Tag(text: "Alert", color: Theme.amber)
                        }
                        Text(i.title).font(.headline)
                        Text(i.detail).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(16)
        }
        .nexaBackground()
        .navigationTitle("Insights & alerts")
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject var store: Store
    @State private var name = "Main bank account"
    @State private var type: AccountType = .BANK
    @State private var balance = ""
    @State private var demo = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
              Group {
                Spacer(minLength: 30)
                Text("NEXA").font(.headline).tracking(3).foregroundStyle(Theme.mint)
                Text("Personal Finance").font(.largeTitle.weight(.semibold))
                Text("Track income, spending, bills and budgets in one place. Everything stays on your phone.").foregroundStyle(Theme.muted)
                Text("Your first account").font(.headline).padding(.top, 10)
              }
                Field(label: "Account name", text: $name)
                ChipRow(options: AccountType.allCases, selected: $type) { $0.label }
                Field(label: type == .CREDIT_CARD ? "Amount owed now (RM)" : "Current balance (RM)", text: $balance, placeholder: "0.00", number: true)
                if let error { Text(error).font(.caption).foregroundStyle(Theme.red) }
                Toggle(isOn: $demo) {
                    VStack(alignment: .leading) {
                        Text("Add demo data")
                        Text("Sample data labelled (demo) to explore the charts. Remove it any time in Settings.").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.mint)
                Button("Get started") {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Enter an account name"; return }
                    guard let v = balance.isEmpty ? 0 : Money.parse(balance) else { error = "Enter a valid amount"; return }
                    store.finishOnboarding(account: Account(name: name.trimmingCharacters(in: .whitespaces), type: type,
                                                            openingBalance: type == .CREDIT_CARD ? -abs(v) : v), demo: demo)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
                Button("Skip, I'll add accounts later") { store.finishOnboarding(account: nil, demo: demo) }
                    .foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

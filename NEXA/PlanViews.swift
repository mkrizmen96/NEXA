import SwiftUI

enum PlanTab: String, CaseIterable { case bills = "Bills", budgets = "Budgets", income = "Income" }

struct PlanView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var tab: PlanTab = .bills
    @State private var payTarget: BillInstance?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Picker("", selection: $tab) { ForEach(PlanTab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.segmented)
                        MonthSwitcher(month: $store.month)
                    }
                    switch tab {
                    case .bills: BillsList(kind: .BILL, payTarget: $payTarget)
                    case .income: BillsList(kind: .INCOME, payTarget: $payTarget)
                    case .budgets:
                        SavingsCard(month: store.month)
                        BudgetsList()
                    }
                }
                .padding(16)
                .padding(.bottom, 70)
            }
            .nexaBackground()
            if tab != .budgets {
                Button { router.push(.newBill(tab == .income ? .INCOME : .BILL)) } label: {
                    Label(tab == .income ? "Add income" : "Add bill", systemImage: "plus").font(.headline)
                        .foregroundStyle(Theme.bg).padding(.horizontal, 18).frame(height: 54)
                        .background(Theme.mint).clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .padding(20)
            }
        }
        .navigationTitle("Budgets & Bills")
        .sheet(item: $payTarget) { b in PaySheet(bill: b) }
    }
}

struct BillsList: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let kind: RecurringKind
    @Binding var payTarget: BillInstance?

    var body: some View {
        let d = store.data
        let m = store.month
        let income = kind == .INCOME
        let list = Finance.instances(d, m.first, m.last, kind: kind)
        let earlier = Finance.instances(d, Finance.distantPast, D.addDays(m.first, -1), kind: kind).filter { !$0.isPaid }
        let total = list.reduce(0) { $0 + $1.amount }
        let paid = list.filter { $0.isPaid }.reduce(0) { $0 + $1.amount }
        let overdue = (earlier + list).filter { $0.status == .overdue }
        VStack(alignment: .leading, spacing: 12) {
            Card {
                Text(income ? "Expected income" : "Commitments this month").font(.caption).foregroundStyle(Theme.muted)
                Text(Money.format(total)).font(.title2.weight(.semibold))
                ProgressBar(ratio: total > 0 ? Double(paid) / Double(total) : 0, color: Theme.mint).padding(.vertical, 4)
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(income ? "Received" : "Paid").font(.caption2).foregroundStyle(Theme.muted)
                        Text(Money.format(paid)).foregroundStyle(Theme.mint)
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text(income ? "Still expected" : "Upcoming").font(.caption2).foregroundStyle(Theme.muted)
                        Text(Money.format(total - paid)).foregroundStyle(Theme.amber)
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text(income ? "Late" : "Overdue").font(.caption2).foregroundStyle(Theme.muted)
                        Text("\(overdue.count) · \(Money.format(overdue.reduce(0) { $0 + $1.expected }))")
                            .foregroundStyle(overdue.isEmpty ? Theme.text : Theme.red)
                    }
                }
                .font(.subheadline)
                if income {
                    Text("Expected income isn't part of your balance until you mark it received.").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            if !earlier.isEmpty {
                SectionTitle(text: income ? "Late from earlier months" : "Overdue from earlier months")
                Card(padding: 8) {
                    ForEach(earlier) { b in BillRow(b: b, onPay: { payTarget = b }).onTapGesture { router.push(.bill(b.recurring.id)) } }
                }
            }
            SectionTitle(text: D.monthF.string(from: m.first))
            Card(padding: 8) {
                if list.isEmpty {
                    EmptyStateView(title: income ? "No scheduled income" : "No bills this month",
                                   message: income ? "Add your fixed salary to see it as expected each month."
                                                   : "Add loans, rent, insurance, subscriptions and other commitments.")
                }
                ForEach(list) { b in BillRow(b: b, onPay: b.isPaid ? nil : { payTarget = b }).onTapGesture { router.push(.bill(b.recurring.id)) } }
            }
            let all = d.recurring.filter { $0.kind == kind }.sorted { $0.name < $1.name }
            if !all.isEmpty {
                SectionTitle(text: income ? "All income schedules" : "All commitments")
                Card(padding: 8) {
                    ForEach(all) { r in
                        HStack(spacing: 10) {
                            CategoryBadge(category: d.category(r.categoryId), size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name)
                                Text(r.frequency.label + (r.cancelled ? " · cancelled" : "") + (r.endDate.map { " · ends " + D.monthYearF.string(from: D.parseDay($0)) } ?? ""))
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(Money.format(r.amount))
                        }
                        .padding(8)
                        .contentShape(Rectangle())
                        .onTapGesture { router.push(.bill(r.id)) }
                    }
                }
            }
        }
    }
}

struct BudgetsList: View {
    @EnvironmentObject var store: Store
    @State private var editing: BudgetEdit?

    struct BudgetEdit: Identifiable { let category: Category?; var id: String { category?.id ?? "total" } }
    struct HistoryRow: Identifiable { let month: YM; let row: BudgetRow; var id: String { month.key } }

    var body: some View {
        let d = store.data
        let m = store.month
        let overall = Finance.overallBudget(d, m)
        let rows = Finance.categoryBudgets(d, m)
        let without = d.categories.filter { c in c.kind == .EXPENSE && !c.archived && !rows.contains { $0.category?.id == c.id } }.sorted { $0.order < $1.order }
        let history: [HistoryRow] = (0..<6).reversed().compactMap { back in
            let mm = m.plus(-back)
            return Finance.overallBudget(d, mm).map { HistoryRow(month: mm, row: $0) }
        }
        VStack(alignment: .leading, spacing: 12) {
            Card {
                Text("Total monthly budget").font(.caption).foregroundStyle(Theme.muted)
                if let overall { BudgetBody(row: overall) } else { Text("Not set · tap to set one").font(.headline) }
            }
            .onTapGesture { editing = BudgetEdit(category: nil) }

            SectionTitle(text: "Category budgets")
            if rows.isEmpty { Text("Tap a category below to give it a limit.").font(.caption).foregroundStyle(Theme.muted) }
            ForEach(rows) { row in
                Card {
                    HStack(spacing: 10) {
                        CategoryBadge(category: row.category, size: 32)
                        Text(row.category?.name ?? "").font(.subheadline.weight(.semibold))
                    }
                    BudgetBody(row: row)
                }
                .onTapGesture { editing = BudgetEdit(category: row.category) }
            }
            if !without.isEmpty {
                SectionTitle(text: "Add a category budget")
                Card(padding: 8) {
                    ForEach(without) { c in
                        HStack(spacing: 10) {
                            CategoryBadge(category: c, size: 30)
                            Text(c.name)
                            Spacer()
                            Text("Set limit").font(.subheadline.weight(.medium)).foregroundStyle(Theme.mint)
                        }
                        .padding(8)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = BudgetEdit(category: c) }
                    }
                }
            }
            if !history.isEmpty {
                SectionTitle(text: "Budget history")
                Card {
                    ForEach(history) { h in
                        HStack {
                            Text(D.monthYearF.string(from: h.month.first)).font(.caption).frame(width: 74, alignment: .leading)
                            ProgressBar(ratio: h.row.ratio, color: Theme.level(h.row.level))
                            Text("\(Int(h.row.ratio * 100))%").font(.caption).foregroundStyle(Theme.level(h.row.level)).frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .sheet(item: $editing) { e in BudgetSheet(category: e.category, month: m) }
    }
}

struct BudgetBody: View {
    let row: BudgetRow
    var body: some View {
        HStack(alignment: .bottom) {
            Text(row.remaining >= 0 ? "\(Money.format(row.remaining)) left" : "\(Money.format(-row.remaining)) over")
                .font(.headline).foregroundStyle(Theme.level(row.level))
            Spacer()
            Text("\(Int(row.ratio * 100))%").fontWeight(.semibold).foregroundStyle(Theme.level(row.level))
        }
        ProgressBar(ratio: row.ratio, color: Theme.level(row.level))
        Text("Spent \(Money.format(row.spent)) of \(Money.format(row.limit))").font(.caption).foregroundStyle(Theme.muted)
    }
}

struct BudgetSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let category: Category?
    let month: YM
    @State private var amount = ""
    @State private var onlyThisMonth = false
    @State private var carry = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        let monthOnly = store.data.budgets.first { $0.categoryId == category?.id && $0.month == month.key }
        let def = store.data.budgets.first { $0.categoryId == category?.id && $0.month == nil }
        NavigationStack {
            Form {
                Section {
                    TextField("Monthly limit (RM)", text: $amount).keyboardType(.decimalPad)
                    if let error { Text(error).foregroundStyle(Theme.red).font(.caption) }
                }
                Section {
                    Toggle("Only for \(D.monthF.string(from: month.first))", isOn: $onlyThisMonth)
                    Toggle("Carry forward unused budget", isOn: $carry)
                } footer: { Text("Off = used for every month without its own limit. Carry forward adds last month's unused amount.") }
                if monthOnly != nil || def != nil {
                    Section {
                        Button(monthOnly != nil ? "Remove this month's limit" : "Remove budget", role: .destructive) {
                            store.deleteBudget(category?.id, month: monthOnly != nil ? month : nil)
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(category.map { "\($0.name) budget" } ?? "Total monthly budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let v = Money.parse(amount), v > 0 else { error = "Enter a limit above 0"; return }
                        store.saveBudget(category?.id, month: onlyThisMonth ? month : nil, limit: v, carry: carry)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                let cur = monthOnly ?? def
                amount = cur.map { Money.plain($0.limit) } ?? ""
                onlyThisMonth = monthOnly != nil
                carry = cur?.carryForward ?? false
            }
        }
        .presentationDetents([.medium])
    }
}

/// Monthly savings target card.
struct SavingsCard: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let month: YM
    @State private var editing = false

    var body: some View {
        let target = Finance.savingsTarget(store.data, month)
        let saved = Finance.savedIn(store.data, month)
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Savings · \(D.monthYearF.string(from: month.first))").font(.caption).foregroundStyle(Theme.muted)
                    if let target {
                        let left = target - saved
                        Text(left > 0 ? "\(Money.format(left)) more to save" : "Target reached")
                            .font(.headline).foregroundStyle(left > 0 ? Theme.text : Theme.mint)
                    } else {
                        Text("Set how much to save this month").font(.headline)
                    }
                }
                Spacer()
                Button("+ Save") { router.push(.newTx(.EXPENSE, Finance.savingsCategory)) }.font(.subheadline.weight(.medium)).foregroundStyle(Theme.mint)
            }
            if let target {
                ProgressBar(ratio: target > 0 ? Double(saved) / Double(target) : 0, color: Theme.mint).padding(.vertical, 4)
                Text("Saved \(Money.format(saved)) of \(Money.format(target)) target").font(.caption).foregroundStyle(Theme.muted)
            } else {
                Text("Tap to set a target. What's still to be saved is held back from Available to spend.").font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .onTapGesture { editing = true }
        .sheet(isPresented: $editing) { SavingsSheet(month: month) }
    }
}

struct SavingsSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let month: YM
    @State private var amount = ""
    @State private var onlyThisMonth = true
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        let monthOnly = store.data.savingsGoals.first { $0.month == month.key }
        let def = store.data.savingsGoals.first { $0.month == nil }
        NavigationStack {
            Form {
                Section {
                    TextField("Amount to save (RM)", text: $amount).keyboardType(.decimalPad)
                    if let error { Text(error).foregroundStyle(Theme.red).font(.caption) }
                    Toggle("Only for \(D.monthF.string(from: month.first))", isOn: $onlyThisMonth)
                } footer: {
                    Text("Counts as saved: expenses in Savings Contributions and transfers into a Savings account.")
                }
                if monthOnly != nil || def != nil {
                    Section {
                        Button(monthOnly != nil ? "Remove this month's target" : "Remove target", role: .destructive) {
                            store.deleteSavingsGoal(month: monthOnly != nil ? month : nil)
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Savings target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let v = Money.parse(amount), v > 0 else { error = "Enter an amount above 0"; return }
                        store.saveSavingsGoal(month: onlyThisMonth ? month : nil, amount: v)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                let cur = monthOnly ?? def
                amount = cur.map { Money.plain($0.amount) } ?? ""
                onlyThisMonth = monthOnly != nil || cur == nil
            }
        }
        .presentationDetents([.medium])
    }
}

/// Records a payment for one bill instance (amount and date can differ from expected).
struct PaySheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let bill: BillInstance
    @State private var amount = ""
    @State private var date = Date()
    @State private var accountId: String?
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        let income = bill.recurring.kind == .INCOME
        let accounts = store.data.accounts.filter { !$0.archived }
        NavigationStack {
            Form {
                Section {
                    TextField("Amount (RM)", text: $amount).keyboardType(.decimalPad)
                    DatePicker(income ? "Date received" : "Date paid", selection: $date, displayedComponents: .date)
                    if accounts.isEmpty {
                        Text("Add an account first (Settings → Accounts).").foregroundStyle(Theme.red)
                    } else {
                        Picker(income ? "Received into" : "Paid from", selection: $accountId) {
                            ForEach(accounts) { a in Text(a.name).tag(Optional(a.id)) }
                        }
                    }
                    if let error { Text(error).foregroundStyle(Theme.red).font(.caption) }
                } header: {
                    Text("Due \(D.dayF.string(from: bill.due)) · expected \(Money.format(bill.expected))")
                } footer: {
                    Text(income ? "Creates one income transaction linked to this schedule."
                                : "Creates one expense linked to this bill, so it is only counted once.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(income ? "Mark received" : "Pay \(bill.recurring.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let v = Money.parse(amount), v > 0 else { error = "Enter an amount above 0"; return }
                        guard let acc = accountId else { error = "Choose an account"; return }
                        store.markPaid(bill, amount: v, date: date, accountId: acc)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                amount = Money.plain(bill.expected)
                let preferred = bill.recurring.accountId
                accountId = accounts.contains { $0.id == preferred } ? preferred : accounts.first?.id
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct BillDetailView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let id: String
    @State private var payTarget: BillInstance?
    @State private var paidTarget: BillInstance?
    @State private var confirmCancel = false
    @State private var confirmDelete = false

    var body: some View {
        let d = store.data
        Group {
            if let r = d.recurring.first(where: { $0.id == id }) {
                content(d, r)
            } else {
                EmptyStateView(title: "Not found", message: "This bill was deleted.")
            }
        }
        .nexaBackground()
        .navigationTitle(d.recurring.first { $0.id == id }?.name ?? "Bill")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $payTarget) { b in PaySheet(bill: b) }
    }

    @ViewBuilder
    private func content(_ d: AppData, _ r: Recurring) -> some View {
        let income = r.kind == .INCOME
        let today = D.today
        let history = Finance.instances(d, D.parseDay(r.trackFrom), D.addMonths(today, 3), today: today, kind: r.kind).filter { $0.recurring.id == r.id }
        let next = history.first { !$0.isPaid }
        let remaining = r.endDate.map { e in
            Finance.instances(d, today, D.parseDay(e), today: today, kind: r.kind).filter { $0.recurring.id == r.id && !$0.isPaid }.reduce(0) { $0 + $1.expected }
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Card {
                    HStack(spacing: 12) {
                        CategoryBadge(category: d.category(r.categoryId), size: 48)
                        VStack(alignment: .leading) {
                            Text(r.name).font(.title3.weight(.semibold))
                            Text("\(Money.format(r.amount)) · \(r.frequency.label.lowercased())\(r.autoDebit ? " · auto-debit" : "")")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    if let next {
                        Divider().overlay(Theme.border)
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Next: \(D.weekdayF.string(from: next.due))").font(.subheadline.weight(.semibold))
                                Tag(text: UI.billLabel(next), color: Theme.status(next.status))
                            }
                            Spacer()
                            Text(Money.format(next.expected)).font(.headline)
                        }
                        Button(income ? "Mark received" : "Mark as paid") { payTarget = next }.buttonStyle(PrimaryButtonStyle())
                    }
                }
                Card {
                    LabelValue(label: "Category", value: d.category(r.categoryId)?.name ?? "–")
                    LabelValue(label: income ? "Paid into" : "Paid from", value: d.account(r.accountId)?.name ?? "Not set")
                    LabelValue(label: "First due date", value: D.dayF.string(from: D.parseDay(r.startDate)))
                    LabelValue(label: "Ends", value: r.endDate.map { D.dayF.string(from: D.parseDay($0)) } ?? "No end date")
                    if r.hasPromo {
                        LabelValue(label: "Promo price", value: "\(Money.format(r.promoAmount)) until \(D.monthYearF.string(from: Finance.dueDate(r, r.promoCount - 1)))", color: Theme.blue)
                        LabelValue(label: "Then", value: Money.format(r.amount))
                    }
                    LabelValue(label: "Reminder", value: "\(r.reminderDays) day\(r.reminderDays == 1 ? "" : "s") before")
                    if let remaining { LabelValue(label: "Still to pay until the end", value: Money.format(remaining), color: Theme.amber) }
                    if r.cancelled { LabelValue(label: "Status", value: "Cancelled", color: Theme.red) }
                    if !r.note.isEmpty { LabelValue(label: "Note", value: r.note) }
                }
                SectionTitle(text: income ? "Receipts" : "Payment history")
                Card(padding: 8) {
                    if history.isEmpty {
                        EmptyStateView(title: "Nothing yet", message: "Due dates appear here from \(D.dayF.string(from: D.parseDay(r.trackFrom))).")
                    }
                    ForEach(Array(history.reversed())) { b in
                        BillRow(b: b, onPay: b.isPaid ? nil : { payTarget = b })
                            .onTapGesture { if b.isPaid { paidTarget = b } else { payTarget = b } }
                        if let p = b.payment {
                            Text("\(income ? "Received" : "Paid") \(D.dayF.string(from: p.at)) from \(d.account(p.accountId)?.name ?? "?")" +
                                 (p.amount != b.expected ? " · expected \(Money.format(b.expected))" : ""))
                                .font(.caption).foregroundStyle(Theme.muted).padding(.leading, 64).padding(.bottom, 6)
                        }
                    }
                }
                HStack(spacing: 8) {
                    if !r.cancelled { Button("Cancel recurring") { confirmCancel = true }.buttonStyle(SecondaryButtonStyle(color: Theme.amber)) }
                    Button("Delete") { confirmDelete = true }.buttonStyle(SecondaryButtonStyle(color: Theme.red))
                }
            }
            .padding(16)
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { router.push(.editBill(r.id)) } label: { Image(systemName: "pencil") } } }
        .confirmationDialog("Payment for \(paidTarget.map { D.dayF.string(from: $0.due) } ?? "")",
                            isPresented: Binding(get: { paidTarget != nil }, set: { if !$0 { paidTarget = nil } }), titleVisibility: .visible) {
            Button("Open transaction") { if let p = paidTarget?.payment { router.push(.tx(p.id)) } }
            Button("Mark unpaid", role: .destructive) { if let b = paidTarget { store.unmarkPaid(b) } }
        }
        .confirmationDialog("Cancel \(r.name)?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel recurring", role: .destructive) { store.cancelRecurring(r) }
        } message: { Text("No new due dates after today. Past payments stay in your history.") }
        .confirmationDialog("Delete \(r.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.deleteRecurring(r); router.pop() }
        } message: { Text("The schedule is removed. Payments already recorded stay as normal transactions.") }
    }
}

struct BillFormView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let editId: String?
    let initialKind: RecurringKind

    @State private var loaded = false
    @State private var kind: RecurringKind = .BILL
    @State private var name = ""
    @State private var amount = ""
    @State private var frequency: Frequency = .MONTHLY
    @State private var start = Date()
    @State private var hasEnd = false
    @State private var payments = ""
    @State private var categoryId: String?
    @State private var accountId: String?
    @State private var autoDebit = false
    @State private var reminder = 3
    @State private var hasPromo = false
    @State private var promoAmount = ""
    @State private var promoCount = ""
    @State private var note = ""
    @State private var error: String?

    private var existing: Recurring? { editId.flatMap { id in store.data.recurring.first { $0.id == id } } }
    private var draft: Recurring {
        Recurring(kind: kind, name: name, amount: Money.parse(amount) ?? 0, frequency: frequency,
                  startDate: D.isoDay(start), trackFrom: D.isoDay(start))
    }

    var body: some View {
        let cats = store.data.categories.filter { $0.kind == (kind == .INCOME ? .INCOME : .EXPENSE) && !$0.archived }.sorted { $0.order < $1.order }
        let accounts = store.data.accounts.filter { !$0.archived }
        let count = Int(payments)
        Form {
            if editId == nil {
                Picker("Type", selection: $kind) {
                    Text("Bill / commitment").tag(RecurringKind.BILL)
                    Text("Scheduled income").tag(RecurringKind.INCOME)
                }
                .pickerStyle(.segmented)
            }
            Section {
                TextField(kind == .BILL ? "Name (Car loan, Coway, Unifi…)" : "Name (Fixed salary)", text: $name)
                TextField(hasPromo ? "Normal amount (RM)" : "Amount (RM)", text: $amount).keyboardType(.decimalPad)
                Picker("How often", selection: $frequency) { ForEach(Frequency.allCases, id: \.self) { Text($0.label).tag($0) } }
                DatePicker("First due date", selection: $start, displayedComponents: .date)
            }
            Section {
                Toggle("Has an end date", isOn: $hasEnd)
                if hasEnd {
                    TextField("Total number of payments (e.g. 84)", text: $payments).keyboardType(.numberPad)
                    if let c = count, c > 0 { Text("Last payment \(D.dayF.string(from: Finance.dueDate(draft, c - 1)))").foregroundStyle(Theme.muted) }
                }
            } footer: { Text("For loans and fixed-term plans.") }
            Section {
                Picker("Category", selection: $categoryId) { ForEach(cats) { Text($0.name).tag(Optional($0.id)) } }
                if !accounts.isEmpty {
                    Picker(kind == .INCOME ? "Paid into" : "Paid from", selection: $accountId) { ForEach(accounts) { Text($0.name).tag(Optional($0.id)) } }
                }
                if kind == .BILL { Toggle("Auto-debit (recorded as paid on the due date)", isOn: $autoDebit) }
                Picker("Remind me", selection: $reminder) {
                    Text("1 day before").tag(1); Text("3 days before").tag(3); Text("7 days before").tag(7)
                }
            }
            Section {
                Toggle("Lower price at the start", isOn: $hasPromo)
                if hasPromo {
                    TextField("Promo amount (RM)", text: $promoAmount).keyboardType(.decimalPad)
                    TextField("Number of promo payments (e.g. 18)", text: $promoCount).keyboardType(.numberPad)
                    if let pc = Int(promoCount), pc > 0 {
                        Text("Promo until \(D.monthYearF.string(from: Finance.dueDate(draft, pc - 1))), normal amount from \(D.monthYearF.string(from: Finance.dueDate(draft, pc)))")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            } footer: { Text("e.g. RM85 for the first 18 payments, then RM95.") }
            if hasEnd, let c = count, c > 0, let v = Money.parse(amount), v > 0 {
                let pa = hasPromo ? (Money.parse(promoAmount) ?? 0) : 0
                let pc = hasPromo ? min(Int(promoCount) ?? 0, c) : 0
                Section { Text("Total over \(c) payments: \(Money.format(pa * pc + v * (c - pc)))").foregroundStyle(Theme.amber) }
            }
            Section { TextField("Note (optional)", text: $note, axis: .vertical) }
            if let error { Section { Text(error).foregroundStyle(Theme.red) } }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle(editId == nil ? (kind == .INCOME ? "New income" : "New bill") : "Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(editId == nil ? "Add" : "Save") { save() } } }
        .onAppear { load(cats: cats, accounts: accounts) }
        .onChange(of: kind) { _, _ in
            let newCats = store.data.categories.filter { $0.kind == (kind == .INCOME ? .INCOME : .EXPENSE) && !$0.archived }.sorted { $0.order < $1.order }
            if !newCats.contains(where: { $0.id == categoryId }) { categoryId = newCats.first?.id }
        }
    }

    private func load(cats: [Category], accounts: [Account]) {
        guard !loaded else { return }
        loaded = true
        if let e = existing {
            kind = e.kind; name = e.name; amount = Money.plain(e.amount); frequency = e.frequency; start = D.parseDay(e.startDate)
            hasEnd = e.endDate != nil
            if let end = e.endDate { payments = String(Finance.occurrences(e, D.parseDay(e.startDate), D.parseDay(end)).count) }
            categoryId = e.categoryId; accountId = e.accountId; autoDebit = e.autoDebit; reminder = e.reminderDays
            hasPromo = e.hasPromo; promoAmount = e.hasPromo ? Money.plain(e.promoAmount) : ""; promoCount = e.hasPromo ? String(e.promoCount) : ""
            note = e.note
        } else {
            kind = initialKind
            let kindCats = store.data.categories.filter { $0.kind == (initialKind == .INCOME ? .INCOME : .EXPENSE) && !$0.archived }.sorted { $0.order < $1.order }
            categoryId = initialKind == .INCOME ? "inc_salary" : kindCats.first?.id
            accountId = accounts.first?.id
        }
    }

    private func save() {
        let v = Money.parse(amount)
        let pa = Money.parse(promoAmount)
        let pc = Int(promoCount)
        let c = Int(payments)
        if name.trimmingCharacters(in: .whitespaces).isEmpty { error = "Enter a name"; return }
        guard let value = v, value > 0 else { error = "Enter an amount above 0"; return }
        if hasEnd && (c ?? 0) <= 0 { error = "Enter how many payments in total"; return }
        if hasPromo && ((pa ?? 0) <= 0 || (pc ?? 0) <= 0) { error = "Enter the promo amount and how many payments it lasts"; return }
        if autoDebit && accountId == nil { error = "Choose the account that is debited"; return }

        let firstOfMonth = YM.now().first
        var r = existing ?? draft
        r.kind = kind
        r.name = name.trimmingCharacters(in: .whitespaces)
        r.amount = value
        r.frequency = frequency
        r.startDate = D.isoDay(start)
        r.endDate = hasEnd ? D.isoDay(Finance.dueDate(draft, (c ?? 1) - 1)) : nil
        // Older due dates are history from before tracking — never "overdue".
        r.trackFrom = existing?.trackFrom ?? D.isoDay(max(D.startOfDay(start), firstOfMonth))
        r.categoryId = categoryId
        r.accountId = accountId
        r.autoDebit = kind == .BILL && autoDebit
        r.reminderDays = reminder
        r.note = note.trimmingCharacters(in: .whitespaces)
        r.promoAmount = hasPromo ? (pa ?? 0) : 0
        r.promoCount = hasPromo ? (pc ?? 0) : 0
        store.saveRecurring(r)
        router.pop()
    }
}

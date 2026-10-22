import SwiftUI

enum TxPeriod: String, CaseIterable { case month = "This month", last = "Last month", quarter = "3 months", year = "This year", all = "All time" }
enum TxSort: String, CaseIterable { case newest = "Newest", oldest = "Oldest", highest = "Highest", lowest = "Lowest" }
enum TxFilter: String, CaseIterable { case all = "All types", expense = "Expenses", income = "Income", transfer = "Transfers" }

struct TransactionsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var query = ""
    @State private var period: TxPeriod = .month
    @State private var filter: TxFilter = .all
    @State private var sort: TxSort = .newest
    @State private var categoryId: String?
    @State private var accountId: String?

    private var range: (Date, Date) {
        let now = YM.now()
        switch period {
        case .month: return (now.first, now.last)
        case .last: return (now.plus(-1).first, now.plus(-1).last)
        case .quarter: return (now.plus(-2).first, now.last)
        case .year: return (YM(year: now.year, month: 1).first, YM(year: now.year, month: 12).last)
        case .all: return (Finance.distantPast, D.addYears(D.today, 50))
        }
    }

    private var list: [Transaction] {
        let d = store.data
        let (from, to) = range
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = d.transactions.filter { t in
            guard Finance.inRange(t, from, to) else { return false }
            switch filter {
            case .all: break
            case .expense: if t.type != .EXPENSE { return false }
            case .income: if t.type != .INCOME { return false }
            case .transfer: if t.type != .TRANSFER { return false }
            }
            if let categoryId, t.categoryId != categoryId { return false }
            if let accountId, t.accountId != accountId && t.toAccountId != accountId { return false }
            if q.isEmpty { return true }
            return t.merchant.lowercased().contains(q) || t.note.lowercased().contains(q)
                || (d.category(t.categoryId)?.name.lowercased().contains(q) ?? false) || Money.plain(t.amount).contains(q)
        }
        switch sort {
        case .newest: return filtered.sorted { $0.at > $1.at }
        case .oldest: return filtered.sorted { $0.at < $1.at }
        case .highest: return filtered.sorted { $0.amount > $1.amount }
        case .lowest: return filtered.sorted { $0.amount < $1.amount }
        }
    }

    var body: some View {
        let d = store.data
        let items = list
        let dupes = Finance.duplicateIds(d)
        let totalIn = items.filter { $0.type == .INCOME }.reduce(0) { $0 + $1.amount }
        let totalOut = items.filter { $0.type == .EXPENSE }.reduce(0) { $0 + $1.amount }
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ChipRow(options: TxPeriod.allCases, selected: $period) { $0.rawValue }
                    ChipRow(options: TxFilter.allCases, selected: $filter) { $0.rawValue }
                    HStack(spacing: 8) {
                        PickerRow(label: "Category", value: d.category(categoryId)?.name ?? "All",
                                  options: [""] + d.categories.sorted { ($0.kind.rawValue, $0.order) < ($1.kind.rawValue, $1.order) }.map { $0.id },
                                  display: { d.category($0)?.name ?? "All" }, onSelect: { categoryId = $0.isEmpty ? nil : $0 })
                        PickerRow(label: "Account", value: d.account(accountId)?.name ?? "All",
                                  options: [""] + d.accounts.map { $0.id },
                                  display: { d.account($0)?.name ?? "All" }, onSelect: { accountId = $0.isEmpty ? nil : $0 })
                    }
                    HStack {
                        VStack(alignment: .leading) {
                            Text("In \(Money.format(totalIn))").foregroundStyle(Theme.mint)
                            Text("Out \(Money.format(totalOut))").foregroundStyle(Theme.red)
                        }
                        .font(.subheadline)
                        Spacer()
                        Menu {
                            ForEach(TxSort.allCases, id: \.self) { s in Button(s.rawValue) { sort = s } }
                        } label: { Label(sort.rawValue, systemImage: "arrow.up.arrow.down").font(.subheadline) }
                    }
                    if items.isEmpty {
                        EmptyStateView(title: d.transactions.isEmpty ? "No transactions yet" : "Nothing matches",
                                       message: d.transactions.isEmpty ? "Tap + to add your first expense or income." : "Try another period, filter or search.")
                    } else if sort == .newest || sort == .oldest {
                        ForEach(groupByDay(items)) { group in
                            DayHeader(day: group.day, items: group.items)
                            ForEach(group.items) { t in
                                TxRow(data: d, t: t, duplicate: dupes.contains(t.id)).onTapGesture { router.push(.tx(t.id)) }
                            }
                        }
                    } else {
                        ForEach(items) { t in
                            TxRow(data: d, t: t, showDate: true, duplicate: dupes.contains(t.id)).onTapGesture { router.push(.tx(t.id)) }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 70)
            }
            .nexaBackground()
            Button { router.push(.newTx(.EXPENSE, nil)) } label: {
                Image(systemName: "plus").font(.title2.weight(.bold)).foregroundStyle(Theme.bg)
                    .frame(width: 56, height: 56).background(Theme.mint).clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .padding(20)
        }
        .navigationTitle("Transactions")
        .searchable(text: $query, prompt: "Merchant, note, category or amount")
    }

    private func groupByDay(_ items: [Transaction]) -> [DayGroup] {
        var order: [Date] = []
        var map: [Date: [Transaction]] = [:]
        for t in items {
            if map[t.day] == nil { order.append(t.day) }
            map[t.day, default: []].append(t)
        }
        return order.map { DayGroup(day: $0, items: map[$0] ?? []) }
    }
}

struct DayGroup: Identifiable {
    let day: Date
    let items: [Transaction]
    var id: Date { day }
}

struct TrendBar: Identifiable {
    let month: YM
    let amount: Int
    var id: String { month.key }
}

struct DayHeader: View {
    let day: Date
    let items: [Transaction]
    var body: some View {
        let net = items.reduce(0) { $0 + ($1.type == .INCOME ? $1.amount : ($1.type == .EXPENSE ? -$1.amount : 0)) }
        let label = day == D.today ? "Today" : (day == D.addDays(D.today, -1) ? "Yesterday" : D.weekdayF.string(from: day))
        HStack {
            Text(label)
            Spacer()
            Text(Money.format(net, plus: true)).foregroundStyle(net >= 0 ? Theme.mint : Theme.muted)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Theme.muted)
        .padding(.top, 10)
    }
}

/// Fast one-handed entry: type → amount on a thumb keypad → category → save.
struct TransactionFormView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let editId: String?
    let initialType: TxType
    let initialCategory: String?

    @State private var loaded = false
    @State private var type: TxType = .EXPENSE
    @State private var amount = ""
    @State private var categoryId: String?
    @State private var date = Date()
    @State private var accountId: String?
    @State private var toAccountId: String?
    @State private var merchant = ""
    @State private var subcategory = ""
    @State private var note = ""
    @State private var error: String?
    @State private var duplicate: Transaction?
    @State private var pending: Transaction?

    private var existing: Transaction? { editId.flatMap { id in store.data.transactions.first { $0.id == id } } }
    private var accounts: [Account] { store.data.accounts.filter { !$0.archived || $0.id == existing?.accountId || $0.id == existing?.toAccountId } }
    private var categories: [Category] {
        let kind: CategoryKind = type == .INCOME ? .INCOME : .EXPENSE
        return store.data.categories.filter { $0.kind == kind && (!$0.archived || $0.id == categoryId) }.sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if type != .ADJUSTMENT {
                        ChipRow(options: [TxType.EXPENSE, .INCOME, .TRANSFER], selected: $type) {
                            $0 == .EXPENSE ? "Expense" : ($0 == .INCOME ? "Income" : "Transfer")
                        }
                    }
                    VStack(spacing: 4) {
                        Text("RM \(amount.isEmpty ? "0" : amount)").font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(type == .INCOME ? Theme.mint : (type == .EXPENSE ? Theme.red : Theme.blue))
                            .lineLimit(1).minimumScaleFactor(0.5)
                        if let error { Text(error).font(.caption).foregroundStyle(Theme.red) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)

                    if accounts.isEmpty {
                        Card {
                            Text("Add an account first").font(.headline)
                            Text("Transactions belong to an account: bank, e-wallet or cash.").font(.caption).foregroundStyle(Theme.muted)
                        }
                        .onTapGesture { router.push(.accounts) }
                    }
                    if type == .EXPENSE || type == .INCOME { categoryPicker }
                    datePicker
                    if !accounts.isEmpty { accountPickers }
                    Field(label: type == .INCOME ? "From (payer)" : "Merchant or description", text: $merchant,
                          placeholder: type == .INCOME ? "Company name" : "Lotus's, GrabFood…")
                    if type == .EXPENSE || type == .INCOME { Field(label: "Subcategory (optional)", text: $subcategory) }
                    Field(label: "Note (optional)", text: $note)
                    if existing?.recurringId != nil {
                        Text("This is a bill payment. Deleting it marks that bill unpaid again.").font(.caption).foregroundStyle(Theme.amber)
                    }
                }
                .padding(16)
            }
            keypad
        }
        .nexaBackground()
        .navigationTitle(editId == nil ? "New transaction" : "Edit transaction")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: type) { _, _ in
            if type != .TRANSFER && !categories.contains(where: { $0.id == categoryId }) { categoryId = categories.first?.id }
        }
        .alert("Possible duplicate", isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil; pending = nil } })) {
            Button("Save anyway") { if let p = pending { save(p) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let dup = duplicate {
                Text("You already have \(UI.signed(dup)) at \(UI.title(store.data, dup)) on \(D.dayF.string(from: dup.at)). Save this one too?")
            }
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Category").font(.caption).foregroundStyle(Theme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories) { c in
                        let sel = c.id == categoryId
                        Button { categoryId = c.id; error = nil } label: {
                            VStack(spacing: 4) {
                                CategoryBadge(category: c, size: 34)
                                Text(c.name).font(.caption2).multilineTextAlignment(.center).lineLimit(2).frame(height: 28)
                            }
                            .frame(width: 76).padding(.vertical, 8)
                            .background(sel ? UI.color(c).opacity(0.16) : Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(sel ? UI.color(c) : Theme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var datePicker: some View {
        HStack(spacing: 8) {
            Chip(text: "Today", selected: D.startOfDay(date) == D.today) { date = Date() }
            Chip(text: "Yesterday", selected: D.startOfDay(date) == D.addDays(D.today, -1)) { date = D.addDays(Date(), -1) }
            DatePicker("", selection: $date, displayedComponents: .date).labelsHidden()
        }
    }

    private var accountPickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            PickerRow(label: type == .TRANSFER ? "From account" : (type == .INCOME ? "Into account" : "Paid from"),
                      value: store.data.account(accountId)?.name ?? "Choose", options: accounts.map { $0.id },
                      display: { id in store.data.account(id).map { "\($0.name) · \($0.type.label)" } ?? "" }, onSelect: { accountId = $0 })
            if type == .TRANSFER {
                PickerRow(label: "To account", value: store.data.account(toAccountId)?.name ?? "Choose",
                          options: accounts.map { $0.id }.filter { $0 != accountId },
                          display: { id in store.data.account(id).map { "\($0.name) · \($0.type.label)" } ?? "" }, onSelect: { toAccountId = $0; error = nil })
                Text("Transfers between your own accounts (including paying off a credit card) are not income or expenses.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    private var keypad: some View {
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]
        return VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(keys, id: \.self) { k in
                    Button { press(k) } label: {
                        Group {
                            if k == "⌫" { Image(systemName: "delete.left") } else { Text(k).font(.title2.weight(.medium)) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(Theme.text)
                        .background(Theme.cardHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button(editId == nil ? "Save" : "Save changes") { trySave() }.buttonStyle(PrimaryButtonStyle())
        }
        .padding(12)
        .background(Theme.card)
    }

    private func press(_ k: String) {
        error = nil
        switch k {
        case "⌫": if !amount.isEmpty { amount.removeLast() }
        case ".": if !amount.contains(".") { amount = amount.isEmpty ? "0." : amount + "." }
        default:
            if let dot = amount.firstIndex(of: "."), amount[amount.index(after: dot)...].count >= 2 { return }
            if amount.replacingOccurrences(of: ".", with: "").count >= 9 { return }
            amount = amount == "0" ? k : amount + k
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let lastAccount = store.data.transactions.max { $0.at < $1.at }?.accountId
        if let e = existing {
            type = e.type; amount = Money.plain(e.amount); categoryId = e.categoryId; date = e.at
            accountId = e.accountId; toAccountId = e.toAccountId; merchant = e.merchant; subcategory = e.subcategory; note = e.note
        } else {
            type = initialType
            categoryId = initialCategory ?? categories.first?.id
            accountId = accounts.contains { $0.id == lastAccount } ? lastAccount : accounts.first?.id
        }
    }

    private func trySave() {
        let v = Money.parse(amount)
        if v == nil || v! <= 0 { error = "Enter an amount above RM 0" }
        else if accountId == nil { error = "Add an account first" }
        else if type == .TRANSFER && toAccountId == nil { error = "Choose the account the money goes to" }
        else if type == .TRANSFER && toAccountId == accountId { error = "Choose two different accounts" }
        else if (type == .INCOME || type == .EXPENSE) && categoryId == nil { error = "Choose a category" }
        else { error = nil }
        guard error == nil, let value = v, let acc = accountId else { return }

        let time: Date
        if let e = existing { time = D.cal.date(bySettingHour: D.cal.component(.hour, from: e.at), minute: D.cal.component(.minute, from: e.at), second: 0, of: date) ?? date }
        else if D.startOfDay(date) == D.today { time = Date() }
        else { time = D.combine(date, hour: 12, minute: 0) }

        var t = existing ?? Transaction(type: type, amount: value, dateTime: D.isoDateTime(time), accountId: acc)
        t.type = type
        t.amount = value
        t.dateTime = D.isoDateTime(time)
        t.categoryId = type == .TRANSFER ? nil : categoryId
        t.subcategory = subcategory.trimmingCharacters(in: .whitespaces)
        t.accountId = acc
        t.toAccountId = type == .TRANSFER ? toAccountId : nil
        t.merchant = merchant.trimmingCharacters(in: .whitespaces)
        t.note = note.trimmingCharacters(in: .whitespaces)

        if existing == nil, let dup = store.duplicateOf(t) {
            duplicate = dup
            pending = t
        } else {
            save(t)
        }
    }

    private func save(_ t: Transaction) {
        store.saveTransaction(t)
        router.pop()
    }
}

struct TransactionDetailView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let id: String
    @State private var confirmDelete = false

    var body: some View {
        let d = store.data
        Group {
            if let t = d.transactions.first(where: { $0.id == id }) {
                ScrollView {
                    VStack(spacing: 12) {
                        VStack(spacing: 6) {
                            CategoryBadge(category: d.category(t.categoryId), type: t.type, size: 56)
                            Text(UI.title(d, t)).font(.title3.weight(.semibold))
                            Text(UI.signed(t)).font(.system(size: 34, weight: .semibold)).foregroundStyle(UI.amountColor(t))
                        }
                        .frame(maxWidth: .infinity)
                        Card {
                            LabelValue(label: "Type", value: t.type.rawValue.capitalized)
                            LabelValue(label: "Date", value: "\(D.weekdayF.string(from: t.at)), \(D.timeF.string(from: t.at))")
                            if t.type == .INCOME || t.type == .EXPENSE {
                                HStack {
                                    LabelValue(label: "Category", value: d.category(t.categoryId)?.name ?? "Uncategorised")
                                    Menu("Change") {
                                        ForEach(d.categories.filter { $0.kind == (t.type == .INCOME ? .INCOME : .EXPENSE) && !$0.archived }.sorted { $0.order < $1.order }) { c in
                                            Button(c.name) { store.recategorize(t.id, c.id) }
                                        }
                                    }
                                    .foregroundStyle(Theme.mint).font(.subheadline)
                                }
                                if !t.subcategory.isEmpty { LabelValue(label: "Subcategory", value: t.subcategory) }
                            }
                            LabelValue(label: t.type == .TRANSFER ? "From" : "Account", value: d.account(t.accountId)?.name ?? "Deleted account")
                            if t.type == .TRANSFER { LabelValue(label: "To", value: d.account(t.toAccountId)?.name ?? "Deleted account") }
                            if !t.merchant.isEmpty { LabelValue(label: "Merchant", value: t.merchant) }
                            LabelValue(label: "Source", value: t.source.rawValue.capitalized)
                            if t.demo { LabelValue(label: "Demo data", value: "Yes", color: Theme.amber) }
                        }
                        if !t.note.isEmpty { Card { Text("Note").font(.caption).foregroundStyle(Theme.muted); Text(t.note) } }
                        if let rid = t.recurringId {
                            Card {
                                Text("Linked bill payment").font(.caption).foregroundStyle(Theme.amber)
                                Text(d.recurring.first { $0.id == rid }?.name ?? "Deleted bill").font(.headline)
                                Text("For the instance due \(t.occurrenceDate ?? "")").font(.caption).foregroundStyle(Theme.muted)
                            }
                            .onTapGesture { if d.recurring.contains(where: { $0.id == rid }) { router.push(.bill(rid)) } }
                        }
                    }
                    .padding(16)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button { router.push(.editTx(t.id)) } label: { Image(systemName: "pencil") } }
                    ToolbarItem(placement: .topBarTrailing) { Button { confirmDelete = true } label: { Image(systemName: "trash").foregroundStyle(Theme.red) } }
                }
                .confirmationDialog("Delete transaction?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { store.deleteTransaction(t.id); router.pop() }
                } message: {
                    Text(t.recurringId != nil ? "This is a bill payment; the bill becomes unpaid again. You can undo right after."
                                              : "\(UI.signed(t)) on \(D.dayF.string(from: t.at)) will be removed. You can undo right after.")
                }
            } else {
                EmptyStateView(title: "Transaction not found", message: "It may have been deleted.")
            }
        }
        .nexaBackground()
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A plain list of transactions with totals.
struct TxListView<Header: View>: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let title: String
    let items: [Transaction]
    @ViewBuilder var header: Header

    var body: some View {
        let spent = items.filter { $0.type == .EXPENSE }.reduce(0) { $0 + $1.amount }
        let earned = items.filter { $0.type == .INCOME }.reduce(0) { $0 + $1.amount }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                header
                HStack {
                    Text("Spent \(Money.format(spent))").foregroundStyle(Theme.red)
                    Spacer()
                    if earned > 0 { Text("Received \(Money.format(earned))").foregroundStyle(Theme.mint) }
                }
                .font(.subheadline).padding(.vertical, 8)
                if items.isEmpty { EmptyStateView(title: "No transactions", message: "Nothing recorded here.") }
                ForEach(items.sorted { $0.at > $1.at }) { t in
                    TxRow(data: store.data, t: t, showDate: true).onTapGesture { router.push(.tx(t.id)) }
                }
            }
            .padding(16)
        }
        .nexaBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DayView: View {
    @EnvironmentObject var store: Store
    let date: Date
    var body: some View {
        TxListView(title: D.weekdayF.string(from: date), items: store.data.transactions.filter { $0.day == D.startOfDay(date) }) { EmptyView() }
    }
}

struct CategoryDetailView: View {
    @EnvironmentObject var store: Store
    let id: String
    let from: Date
    let to: Date

    var body: some View {
        let d = store.data
        let cat = d.category(id)
        let items = d.transactions.filter { Finance.inRange($0, from, to) && ($0.categoryId ?? Finance.uncategorised) == id }
        let end = YM(to)
        let trend: [TrendBar] = (0..<6).reversed().map { back in
            let m = end.plus(-back)
            let sum = d.transactions.filter { ($0.type == .EXPENSE || $0.type == .INCOME) && ($0.categoryId ?? Finance.uncategorised) == id && Finance.inRange($0, m.first, m.last) }
                .reduce(0) { $0 + $1.amount }
            return TrendBar(month: m, amount: sum)
        }
        let maxV = max(trend.map { $0.amount }.max() ?? 1, 1)
        TxListView(title: cat?.name ?? "Uncategorised", items: items) {
            Card {
                HStack(spacing: 12) {
                    CategoryBadge(category: cat)
                    VStack(alignment: .leading) {
                        Text("\(D.dayShortF.string(from: from)) – \(D.dayF.string(from: to))").font(.caption).foregroundStyle(Theme.muted)
                        Text("\(items.count) transactions · \(Money.format(items.reduce(0) { $0 + $1.amount }))").font(.headline)
                    }
                }
                Text("Last 6 months").font(.caption).foregroundStyle(Theme.muted).padding(.top, 8)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(trend) { bar in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 6).fill(UI.color(cat)).frame(height: max(2, CGFloat(60 * bar.amount / maxV)))
                            Text(D.monthShortF.string(from: bar.month.first)).font(.caption2).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 84, alignment: .bottom)
            }
        }
    }
}

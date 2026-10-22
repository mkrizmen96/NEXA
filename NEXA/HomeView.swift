import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var payTarget: BillInstance?

    var body: some View {
        let d = store.data
        let m = store.month
        let today = D.today
        let balance = Finance.totalBalance(d)
        let unpaid = Finance.unpaidCommitments(d, m, today: today)
        let toSave = Finance.savingsStillToSave(d, m)
        let summary = Finance.summary(d, m.first, m.last)
        let bills = Finance.instances(d, m.first, m.last, today: today)
        let overdueEarlier = Finance.instances(d, Finance.distantPast, D.addDays(m.first, -1), today: today).filter { !$0.isPaid }
        let alerts = Insights.build(d, today: today).filter { $0.kind == .alert }

        ScrollView {
            VStack(spacing: 12) {
              Group {
                header(alerts: alerts.count)
                if !d.accounts.contains(where: { !$0.archived }) {
                    Card {
                        Text("Add your first account").font(.headline)
                        Text("Your balance is the accounts' opening balances plus every transaction.").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    .onTapGesture { router.push(.accounts) }
                }
                BalanceCard(balance: balance, unpaid: unpaid, toSave: toSave, reserved: d.settings.reservedFunds)
                    .onTapGesture { router.push(.accounts) }
                HStack(spacing: 8) {
                    StatTile(label: "Income", value: summary.income, color: Theme.mint)
                    StatTile(label: "Expenses", value: summary.expense, color: Theme.red)
                    StatTile(label: "Commitments", value: bills.reduce(0) { $0 + $1.amount }, color: Theme.amber)
                }
                IncomeCard(month: m)
                quickActions
                BudgetCard(row: Finance.overallBudget(d, m)).onTapGesture { router.tab = .plan }
                SavingsCard(month: m)
              }
              Group {
                if let top = Finance.breakdown(d, m.first, m.last).first { topCategory(top, total: summary.expense, m: m) }
                if !alerts.isEmpty { alertsCard(alerts) }

                SectionTitle(text: "Bills this month", action: "See all") { router.tab = .plan }
                Card(padding: 8) {
                    let list = Array((overdueEarlier + bills.filter { !$0.isPaid }).prefix(5))
                    if list.isEmpty {
                        EmptyStateView(title: bills.isEmpty ? "No bills yet" : "All bills paid",
                                       message: bills.isEmpty ? "Add commitments like loans, rent and subscriptions." : "Every bill this month is paid.")
                    } else {
                        ForEach(list) { b in BillRow(b: b, onPay: { payTarget = b }).onTapGesture { router.push(.bill(b.recurring.id)) } }
                    }
                }

                let expected = Finance.instances(d, m.first, m.last, today: today, kind: .INCOME).filter { !$0.isPaid }
                if !expected.isEmpty {
                    SectionTitle(text: "Expected income")
                    Card(padding: 8) {
                        Text("Not included in your balance until you mark it received.").font(.caption).foregroundStyle(Theme.muted).padding(8)
                        ForEach(expected) { b in BillRow(b: b, onPay: { payTarget = b }).onTapGesture { router.push(.bill(b.recurring.id)) } }
                    }
                }

                SectionTitle(text: "Recent transactions", action: "See all") { router.tab = .transactions }
                Card(padding: 8) {
                    let recent = Array(d.transactions.sorted { $0.at > $1.at }.prefix(5))
                    if recent.isEmpty {
                        EmptyStateView(title: "No transactions yet", message: "Tap Expense or Income above to record your first one.")
                    } else {
                        ForEach(recent) { t in TxRow(data: d, t: t, showDate: true).onTapGesture { router.push(.tx(t.id)) } }
                    }
                }
              }
            }
            .padding(16)
        }
        .nexaBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $payTarget) { b in PaySheet(bill: b) }
    }

    private func header(alerts: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("NEXA").font(.caption.weight(.semibold)).tracking(3).foregroundStyle(Theme.mint)
                Text("Overview").font(.title2.weight(.semibold))
            }
            Spacer()
            MonthSwitcher(month: $store.month)
            Button { router.push(.insights) } label: {
                Image(systemName: "bell.fill").foregroundStyle(Theme.text)
                    .overlay(alignment: .topTrailing) {
                        if alerts > 0 {
                            Text("\(alerts)").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.bg)
                                .padding(3).background(Theme.red).clipShape(Circle()).offset(x: 8, y: -8)
                        }
                    }
            }
            .padding(.leading, 6)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            QuickAction(label: "Expense", icon: "minus", color: Theme.red) { router.push(.newTx(.EXPENSE, nil)) }
            QuickAction(label: "Income", icon: "plus", color: Theme.mint) { router.push(.newTx(.INCOME, nil)) }
            QuickAction(label: "Bill", icon: "calendar.badge.plus", color: Theme.amber) { router.push(.newBill(.BILL)) }
            QuickAction(label: "Reports", icon: "chart.bar.doc.horizontal", color: Theme.blue) { router.push(.reports) }
        }
    }

    private func topCategory(_ top: Slice, total: Int, m: YM) -> some View {
        Card {
            HStack(spacing: 12) {
                CategoryBadge(category: top.category)
                VStack(alignment: .leading) {
                    Text("Biggest spending category").font(.caption).foregroundStyle(Theme.muted)
                    Text(top.category?.name ?? "Uncategorised").font(.headline)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(Money.format(top.amount)).font(.headline)
                    Text("\(Int(top.share * 100))% of spending").font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
        .onTapGesture { router.push(.category(top.category?.id ?? Finance.uncategorised, m.first, m.last)) }
    }

    private func alertsCard(_ alerts: [Insight]) -> some View {
        Card {
            ForEach(alerts.prefix(3)) { a in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Theme.amber).frame(width: 8, height: 8).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.title).font(.subheadline.weight(.semibold))
                        Text(a.detail).font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .onTapGesture { router.push(.insights) }
    }
}

struct BalanceCard: View {
    let balance: Int
    let unpaid: Int
    let toSave: Int
    let reserved: Int
    var body: some View {
        let available = balance - unpaid - toSave - reserved
        Card(padding: 20) {
            Text("Total balance").font(.subheadline).foregroundStyle(Theme.muted)
            Text(Money.format(balance)).font(.system(size: 34, weight: .semibold))
            Divider().overlay(Theme.border).padding(.vertical, 6)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Available to spend").font(.caption).foregroundStyle(Theme.muted)
                        Tag(text: "Estimate", color: Theme.muted)
                    }
                    Text(Money.format(available)).font(.title3.weight(.semibold)).foregroundStyle(available < 0 ? Theme.red : Theme.mint)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Reserved for bills").font(.caption).foregroundStyle(Theme.muted)
                    Text(Money.format(unpaid)).font(.headline).foregroundStyle(Theme.amber)
                }
            }
            let also = [toSave > 0 ? "\(Money.format(toSave)) still to save this month" : nil,
                        reserved > 0 ? "\(Money.format(reserved)) you set aside" : nil].compactMap { $0 }
            if !also.isEmpty {
                Text("Also excludes \(also.joined(separator: " and ")).").font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }
}

struct StatTile: View {
    let label: String
    let value: Int
    let color: Color
    var body: some View {
        Card(padding: 12) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label).font(.caption2).foregroundStyle(Theme.muted)
            }
            Text(Money.format(value)).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

struct QuickAction: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(color)
                    .frame(width: 36, height: 36).background(color.opacity(0.15)).clipShape(Circle())
                Text(label).font(.caption.weight(.medium)).foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

/// Wages entered by hand: tap a figure to edit it (or add one).
struct IncomeCard: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let month: YM
    private let main = ["inc_salary", "inc_overtime", "inc_claim"]

    var body: some View {
        let d = store.data
        let byCat = Dictionary(uniqueKeysWithValues: Finance.breakdown(d, month.first, month.last, type: .INCOME).map { ($0.id, $0.amount) })
        let other = byCat.filter { !main.contains($0.key) }.values.reduce(0, +)
        Card {
            HStack {
                Text("Income this month").font(.subheadline.weight(.semibold))
                Spacer()
                Button("+ Add") { router.push(.newTx(.INCOME, nil)) }.font(.subheadline.weight(.medium)).foregroundStyle(Theme.mint)
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(main, id: \.self) { id in
                    let entries = d.transactions.filter { $0.type == .INCOME && $0.categoryId == id && Finance.inRange($0, month.first, month.last) }
                    let amount = byCat[id] ?? 0
                    Button {
                        if entries.isEmpty { router.push(.newTx(.INCOME, id)) }
                        else if entries.count == 1 { router.push(.editTx(entries[0].id)) }
                        else { router.push(.category(id, month.first, month.last)) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.category(id)?.name ?? id).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
                            Text(Money.format(amount)).font(.footnote.weight(.semibold)).foregroundStyle(amount > 0 ? Theme.mint : Theme.faint)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(entries.isEmpty ? "Add" : "Edit").font(.caption2).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            if other > 0 { Text("Other income \(Money.format(other))").font(.caption).foregroundStyle(Theme.muted) }
        }
    }
}

struct BudgetCard: View {
    let row: BudgetRow?
    var body: some View {
        Card {
            if let row {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Monthly budget").font(.caption).foregroundStyle(Theme.muted)
                        Text(row.remaining >= 0 ? "\(Money.format(row.remaining)) left" : "\(Money.format(-row.remaining)) over")
                            .font(.title3.weight(.semibold)).foregroundStyle(Theme.level(row.level))
                    }
                    Spacer()
                    Text("\(Int(row.ratio * 100))%").font(.headline).foregroundStyle(Theme.level(row.level))
                }
                ProgressBar(ratio: row.ratio, color: Theme.level(row.level)).padding(.vertical, 4)
                Text("\(Money.format(row.spent)) of \(Money.format(row.limit))").font(.caption).foregroundStyle(Theme.muted)
            } else {
                Text("Monthly budget").font(.headline)
                Text("Set a spending limit in Budgets & Bills to track how much is left.").font(.subheadline).foregroundStyle(Theme.muted)
            }
        }
    }
}

struct BillRow: View {
    let b: BillInstance
    var onPay: (() -> Void)?
    var body: some View {
        let color = Theme.status(b.status)
        let income = b.recurring.kind == .INCOME
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text("\(D.dayOfMonth(b.due))").font(.headline)
                Text(D.monthShortF.string(from: b.due)).font(.caption2)
            }
            .foregroundStyle(color).frame(width: 44, height: 44).background(color.opacity(0.14)).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(b.recurring.name).lineLimit(1)
                HStack(spacing: 6) {
                    Tag(text: UI.billLabel(b), color: color)
                    if b.recurring.hasPromo && b.index < b.recurring.promoCount { Tag(text: "Promo", color: Theme.blue) }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(b.amount)).foregroundStyle(b.isPaid ? Theme.muted : (income ? Theme.mint : Theme.text))
                if !b.isPaid, let onPay {
                    Button(income ? "Received" : "Pay", action: onPay).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mint)
                }
            }
        }
        .padding(8)
        .contentShape(Rectangle())
    }
}

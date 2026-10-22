import Foundation

enum InsightKind { case fact, estimate, alert }

struct Insight: Identifiable {
    let kind: InsightKind
    let title: String
    let detail: String
    var id: String { title }
}

/// Data-driven insights, only produced when there is enough data. Estimates are labelled.
enum Insights {
    static func build(_ d: AppData, today: Date = D.today) -> [Insight] {
        guard d.settings.insights else { return [] }
        var out: [Insight] = []
        let m = YM(today)
        let last = m.plus(-1)

        let spentNow = Finance.expenses(d, m.first, today)
        let lastTo = last.day(D.dayOfMonth(today))
        let spentBefore = Finance.expenses(d, last.first, lastTo)
        if let change = Finance.percentChange(spentNow, spentBefore), spentNow > 0, abs(change) >= 0.1 {
            let pct = Int((abs(change) * 100).rounded())
            out.append(Insight(kind: .fact, title: change > 0 ? "Spending up \(pct)%" : "Spending down \(pct)%",
                               detail: "\(Money.format(spentNow)) so far this month vs \(Money.format(spentBefore)) by the same day last month."))
        }

        for row in Finance.categoryBudgets(d, m) {
            guard let crossed = Finance.crossedThreshold(d, row) else { continue }
            let name = row.category?.name ?? "Total"
            out.append(Insight(kind: .alert, title: crossed >= 100 ? "\(name) budget exceeded" : "\(name) at \(crossed)% of budget",
                               detail: "\(Money.format(row.spent)) of \(Money.format(row.limit)) · \(Money.format(row.remaining)) left."))
        }
        if let row = Finance.overallBudget(d, m), let crossed = Finance.crossedThreshold(d, row) {
            out.append(Insight(kind: .alert, title: crossed >= 100 ? "Monthly budget exceeded" : "Monthly budget at \(crossed)%",
                               detail: "\(Money.format(row.spent)) of \(Money.format(row.limit)) spent this month."))
        }

        if d.settings.billReminders {
            for b in Finance.instances(d, today, D.addDays(today, 7), today: today) where !b.isPaid && b.status == .dueSoon {
                let when = b.due == today ? "today" : D.dayShortF.string(from: b.due)
                out.append(Insight(kind: .alert, title: "\(b.recurring.name) due \(when)", detail: "\(Money.format(b.expected)) · not paid yet."))
            }
        }

        for r in d.recurring where r.kind == .BILL {
            let paid = d.transactions.filter { $0.recurringId == r.id }.sorted { $0.at < $1.at }
            if paid.count >= 2 {
                let a = paid[paid.count - 2], b = paid[paid.count - 1]
                if b.amount > a.amount {
                    out.append(Insight(kind: .fact, title: "\(r.name) went up",
                                       detail: "Last paid \(Money.format(b.amount)), before that \(Money.format(a.amount))."))
                }
            }
        }

        let s = Finance.summary(d, last.first, last.last)
        if let rate = s.savingsRate {
            out.append(Insight(kind: .fact, title: "Saved \(Int((rate * 100).rounded()))% in \(D.monthF.string(from: last.first))",
                               detail: "Income \(Money.format(s.income)), expenses \(Money.format(s.expense))."))
        }

        let day = D.dayOfMonth(today)
        if day >= 7 && spentNow > 0 {
            let pace = Double(spentNow) / Double(day)
            out.append(Insight(kind: .estimate, title: "Estimated month-end spending: \(Money.format(Int(pace * Double(m.length))))",
                               detail: "Estimate based on your average of \(Money.format(Int(pace))) a day so far."))
        }

        let months = Finance.monthly(d, months: 12, end: last).filter { $0.expense > 0 }
        if months.count >= 3, let hi = months.max(by: { $0.expense < $1.expense }), let lo = months.min(by: { $0.expense < $1.expense }) {
            out.append(Insight(kind: .fact, title: "Highest month: \(D.monthYearF.string(from: hi.month.first))",
                               detail: "\(Money.format(hi.expense)) spent. Lowest was \(D.monthYearF.string(from: lo.month.first)) at \(Money.format(lo.expense))."))
        }

        let dupes = Finance.duplicateIds(d)
        if !dupes.isEmpty {
            out.append(Insight(kind: .alert, title: "\(dupes.count) possible duplicate transactions",
                               detail: "Same amount, date and merchant. Check Transactions to remove any extras."))
        }
        return out
    }
}

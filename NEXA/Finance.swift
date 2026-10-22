import Foundation

enum BillStatus: String {
    case upcoming = "Upcoming", dueSoon = "Due soon", overdue = "Overdue", paid = "Paid", autoDebit = "Auto-debit"
}

/// One due date of a recurring bill or scheduled income.
struct BillInstance: Identifiable, Hashable {
    let recurring: Recurring
    let due: Date
    let index: Int
    let expected: Int
    let payment: Transaction?
    let status: BillStatus
    var id: String { recurring.id + "|" + D.isoDay(due) }
    var isPaid: Bool { payment != nil }
    /// Paid amount when paid (amounts can vary), otherwise the expected amount.
    var amount: Int { payment?.amount ?? expected }
}

enum BudgetLevel { case ok, warn, over }

struct BudgetRow: Identifiable {
    let category: Category?
    let limit: Int
    let spent: Int
    var id: String { category?.id ?? "total" }
    var remaining: Int { limit - spent }
    var ratio: Double { limit <= 0 ? 0 : Double(spent) / Double(limit) }
    var level: BudgetLevel { ratio >= 1 ? .over : (ratio >= 0.8 ? .warn : .ok) }
}

struct Slice: Identifiable { let category: Category?; let amount: Int; let share: Double; var id: String { category?.id ?? Finance.uncategorised } }
struct MonthPoint: Identifiable { let month: YM; let income: Int; let expense: Int; var net: Int { income - expense }; var id: String { month.key } }
struct DayPoint: Identifiable { let date: Date; let amount: Int; let spike: Bool; var id: Date { date } }

struct Summary {
    let income: Int
    let expense: Int
    let savingsContributions: Int
    var net: Int { income - expense }
    var savings: Int { net + savingsContributions }
    var savingsRate: Double? { income > 0 ? Double(savings) / Double(income) : nil }
}

/// All money rules live here, mirroring the Android engine (see its unit tests).
enum Finance {
    static let uncategorised = "none"
    static let savingsCategory = "exp_savings"

    // MARK: Balances

    /// Opening balance + income − expenses ± transfers ± reconciliation adjustments.
    static func balance(_ d: AppData, _ accountId: String) -> Int {
        guard let a = d.account(accountId) else { return 0 }
        var b = a.openingBalance
        for t in d.transactions {
            switch t.type {
            case .INCOME: if t.accountId == accountId { b += t.amount }
            case .EXPENSE: if t.accountId == accountId { b -= t.amount }
            case .TRANSFER:
                if t.accountId == accountId { b -= t.amount }
                if t.toAccountId == accountId { b += t.amount }
            case .ADJUSTMENT: if t.accountId == accountId { b += t.amount }
            }
        }
        return b
    }

    static func totalBalance(_ d: AppData) -> Int {
        d.accounts.filter { !$0.archived }.reduce(0) { $0 + balance(d, $1.id) }
    }

    // MARK: Income & expenses

    static func inRange(_ t: Transaction, _ from: Date, _ to: Date) -> Bool { t.day >= from && t.day <= to }

    static func income(_ d: AppData, _ from: Date, _ to: Date) -> Int {
        d.transactions.filter { $0.type == .INCOME && inRange($0, from, to) }.reduce(0) { $0 + $1.amount }
    }

    static func expenses(_ d: AppData, _ from: Date, _ to: Date, category: String? = nil) -> Int {
        d.transactions.filter {
            $0.type == .EXPENSE && inRange($0, from, to) && (category == nil || ($0.categoryId ?? uncategorised) == category)
        }.reduce(0) { $0 + $1.amount }
    }

    static func summary(_ d: AppData, _ from: Date, _ to: Date) -> Summary {
        Summary(income: income(d, from, to), expense: expenses(d, from, to),
                savingsContributions: expenses(d, from, to, category: savingsCategory))
    }

    // MARK: Bills, commitments, scheduled income

    static func dueDate(_ r: Recurring, _ i: Int) -> Date {
        let start = D.parseDay(r.startDate)
        switch r.frequency {
        case .WEEKLY: return D.addDays(start, 7 * i)
        case .MONTHLY: return D.addMonths(start, i)
        case .QUARTERLY: return D.addMonths(start, 3 * i)
        case .YEARLY: return D.addYears(start, i)
        }
    }

    static func expectedAmount(_ r: Recurring, _ i: Int) -> Int { r.hasPromo && i < r.promoCount ? r.promoAmount : r.amount }

    static func occurrences(_ r: Recurring, _ from: Date, _ to: Date) -> [(Int, Date)] {
        let end = r.endDate.map { D.parseDay($0) }
        var out: [(Int, Date)] = []
        var i = 0
        while i < 10_000 {
            let due = dueDate(r, i)
            if due > to { break }
            if let end, due > end { break }
            if due >= from { out.append((i, due)) }
            i += 1
        }
        return out
    }

    static func paymentIndex(_ d: AppData) -> [String: Transaction] {
        var map: [String: Transaction] = [:]
        for t in d.transactions { if let r = t.recurringId, let o = t.occurrenceDate { map[r + "|" + o] = t } }
        return map
    }

    static func instances(_ d: AppData, _ from: Date, _ to: Date, today: Date = D.today, kind: RecurringKind? = .BILL,
                          payments: [String: Transaction]? = nil) -> [BillInstance] {
        let pay = payments ?? paymentIndex(d)
        var out: [BillInstance] = []
        for r in d.recurring where kind == nil || r.kind == kind {
            let track = D.parseDay(r.trackFrom)
            for (i, due) in occurrences(r, max(from, track), to) {
                let p = pay[r.id + "|" + D.isoDay(due)]
                out.append(BillInstance(recurring: r, due: due, index: i, expected: expectedAmount(r, i), payment: p,
                                        status: status(r, due, p, today)))
            }
        }
        return out.sorted { $0.due < $1.due }
    }

    static func status(_ r: Recurring, _ due: Date, _ payment: Transaction?, _ today: Date) -> BillStatus {
        if payment != nil { return .paid }
        if due < today { return .overdue }
        if r.autoDebit { return .autoDebit }
        if due <= D.addDays(today, max(r.reminderDays, 1)) { return .dueSoon }
        return .upcoming
    }

    static let distantPast = D.parseDay("2000-01-01")

    /// Unpaid bills due up to the end of the month (incl. overdue). Paid ones are already expenses.
    static func unpaidCommitments(_ d: AppData, _ m: YM, today: Date = D.today) -> Int {
        instances(d, distantPast, m.last, today: today).filter { !$0.isPaid }.reduce(0) { $0 + $1.expected }
    }

    /// Balance − unpaid bills − savings still to put aside − other reserved funds.
    static func availableToSpend(_ d: AppData, _ m: YM, today: Date = D.today) -> Int {
        totalBalance(d) - unpaidCommitments(d, m, today: today) - savingsStillToSave(d, m) - d.settings.reservedFunds
    }

    // MARK: Savings target

    static func savingsTarget(_ d: AppData, _ m: YM) -> Int? {
        (d.savingsGoals.first { $0.month == m.key } ?? d.savingsGoals.first { $0.month == nil })?.amount
    }

    /// Savings Contributions expenses + transfers into a Savings account.
    static func savedIn(_ d: AppData, _ m: YM) -> Int {
        let savingsAccounts = Set(d.accounts.filter { $0.type == .SAVINGS }.map { $0.id })
        let toSavings = d.transactions.filter {
            $0.type == .TRANSFER && inRange($0, m.first, m.last) &&
                savingsAccounts.contains($0.toAccountId ?? "") && !savingsAccounts.contains($0.accountId)
        }.reduce(0) { $0 + $1.amount }
        return expenses(d, m.first, m.last, category: savingsCategory) + toSavings
    }

    static func savingsStillToSave(_ d: AppData, _ m: YM) -> Int {
        guard let target = savingsTarget(d, m) else { return 0 }
        return max(0, target - savedIn(d, m))
    }

    // MARK: Budgets

    private static func budgetFor(_ d: AppData, _ cat: String?, _ m: YM) -> Budget? {
        d.budgets.first { $0.categoryId == cat && $0.month == m.key } ?? d.budgets.first { $0.categoryId == cat && $0.month == nil }
    }

    static func budgetLimit(_ d: AppData, _ cat: String?, _ m: YM) -> Int? {
        guard let b = budgetFor(d, cat, m) else { return nil }
        var limit = b.limit
        if b.carryForward, let prev = budgetFor(d, cat, m.plus(-1)) {
            let p = m.plus(-1)
            limit += max(0, prev.limit - expenses(d, p.first, p.last, category: cat))
        }
        return limit
    }

    static func overallBudget(_ d: AppData, _ m: YM) -> BudgetRow? {
        guard let limit = budgetLimit(d, nil, m) else { return nil }
        return BudgetRow(category: nil, limit: limit, spent: expenses(d, m.first, m.last))
    }

    static func categoryBudgets(_ d: AppData, _ m: YM) -> [BudgetRow] {
        d.categories.filter { $0.kind == .EXPENSE && !$0.archived }.sorted { $0.order < $1.order }.compactMap { c in
            budgetLimit(d, c.id, m).map { BudgetRow(category: c, limit: $0, spent: expenses(d, m.first, m.last, category: c.id)) }
        }
    }

    static func crossedThreshold(_ d: AppData, _ row: BudgetRow) -> Int? {
        let pct = Int(row.ratio * 100)
        if d.settings.alert100 && pct >= 100 { return 100 }
        if d.settings.alert90 && pct >= 90 { return 90 }
        if d.settings.alert80 && pct >= 80 { return 80 }
        return nil
    }

    // MARK: Analytics

    static func breakdown(_ d: AppData, _ from: Date, _ to: Date, type: TxType = .EXPENSE) -> [Slice] {
        let txs = d.transactions.filter { $0.type == type && inRange($0, from, to) }
        let total = txs.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return [] }
        return Dictionary(grouping: txs) { $0.categoryId ?? uncategorised }
            .map { cid, list -> Slice in
                let sum = list.reduce(0) { $0 + $1.amount }
                return Slice(category: d.category(cid), amount: sum, share: Double(sum) / Double(total))
            }
            .sorted { $0.amount > $1.amount }
    }

    static func monthly(_ d: AppData, months: Int, end: YM) -> [MonthPoint] {
        (0..<months).reversed().map { back in
            let m = end.plus(-back)
            return MonthPoint(month: m, income: income(d, m.first, m.last), expense: expenses(d, m.first, m.last))
        }
    }

    /// Daily expenses. A spike is > mean + 2 standard deviations (needs 7+ days with spending).
    static func daily(_ d: AppData, days: Int, end: Date) -> [DayPoint] {
        let start = D.addDays(end, -(days - 1))
        var byDay: [Date: Int] = [:]
        for t in d.transactions where t.type == .EXPENSE && inRange(t, start, end) { byDay[t.day, default: 0] += t.amount }
        let values = (0..<days).map { byDay[D.addDays(start, $0)] ?? 0 }
        let active = values.filter { $0 > 0 }.count
        let mean = Double(values.reduce(0, +)) / Double(max(days, 1))
        let sd = sqrt(values.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(max(days, 1)))
        return values.enumerated().map { i, v in
            DayPoint(date: D.addDays(start, i), amount: v, spike: active >= 7 && sd > 0 && Double(v) > mean + 2 * sd)
        }
    }

    static func percentChange(_ now: Int, _ before: Int) -> Double? { before <= 0 ? nil : Double(now - before) / Double(before) }

    // MARK: Duplicates

    private static func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

    static func looksLikeDuplicate(_ a: Transaction, _ b: Transaction) -> Bool {
        if a.id == b.id || a.type != b.type || a.amount != b.amount || a.day != b.day { return false }
        if a.recurringId != nil && a.recurringId == b.recurringId && a.occurrenceDate == b.occurrenceDate { return true }
        let ma = norm(a.merchant), mb = norm(b.merchant)
        return ma.isEmpty || mb.isEmpty || ma == mb || ma.contains(mb) || mb.contains(ma)
    }

    static func findDuplicate(_ d: AppData, _ c: Transaction) -> Transaction? {
        d.transactions.first { looksLikeDuplicate($0, c) }
    }

    static func duplicateIds(_ d: AppData) -> Set<String> {
        var out = Set<String>()
        let groups = Dictionary(grouping: d.transactions) { "\($0.type.rawValue)|\($0.amount)|\(D.isoDay($0.day))" }
        for g in groups.values where g.count > 1 {
            for i in 0..<g.count { for j in (i + 1)..<g.count where looksLikeDuplicate(g[i], g[j]) { out.insert(g[i].id); out.insert(g[j].id) } }
        }
        return out
    }
}

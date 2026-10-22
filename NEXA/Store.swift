import Foundation
import SwiftUI
import UserNotifications

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let canUndo: Bool
}

/// Holds all app data, saves it atomically to the app's private storage, and
/// provides every action (with Undo for destructive ones). Local only — no network.
final class Store: ObservableObject {
    @Published private(set) var data: AppData
    @Published var month: YM = .now()
    @Published var toast: Toast?

    private var undoSnapshot: AppData?
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("nexa-data.json")
        if let raw = try? Data(contentsOf: url) {
            if let decoded = try? JSONDecoder().decode(AppData.self, from: raw) {
                data = DefaultData.withNewDefaults(decoded)
            } else {
                // Keep the unreadable file for recovery instead of overwriting it.
                try? raw.write(to: dir.appendingPathComponent("nexa-data-corrupt-\(Int(Date().timeIntervalSince1970)).json"))
                data = AppData(categories: DefaultData.categories())
            }
        } else {
            data = AppData(categories: DefaultData.categories())
        }
        recordAutoDebits()
    }

    private func commit(_ new: AppData, _ message: String? = nil, undoable: Bool = false) {
        let old = data
        data = new
        save()
        if undoable { undoSnapshot = old }
        if let message { toast = Toast(text: message, canUndo: undoable) }
        Notifier.budgetCrossings(old: old, new: new)
        Notifier.reschedule(new)
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let raw = try? enc.encode(data) { try? raw.write(to: url, options: [.atomic, .completeFileProtection]) }
    }

    func undo() {
        guard let s = undoSnapshot else { return }
        undoSnapshot = nil
        commit(s, "Change undone")
    }

    func say(_ text: String) { toast = Toast(text: text, canUndo: false) }

    // MARK: Onboarding

    func finishOnboarding(account: Account?, demo: Bool) {
        var d = data
        if let account { d.accounts.append(account) }
        if demo { d = mergeDemo(d) }
        d.settings.onboarded = true
        commit(d)
        recordAutoDebits()
        Notifier.requestPermission()
    }

    // MARK: Transactions

    func duplicateOf(_ t: Transaction) -> Transaction? {
        var d = data
        d.transactions.removeAll { $0.id == t.id }
        return Finance.findDuplicate(d, t)
    }

    func saveTransaction(_ t: Transaction) {
        var d = data
        let exists = d.transactions.contains { $0.id == t.id }
        if let i = d.transactions.firstIndex(where: { $0.id == t.id }) { d.transactions[i] = t } else { d.transactions.append(t) }
        commit(d, exists ? "Transaction updated" : "Transaction saved", undoable: true)
    }

    func deleteTransaction(_ id: String) {
        var d = data
        d.transactions.removeAll { $0.id == id }
        commit(d, "Transaction deleted", undoable: true)
    }

    func recategorize(_ id: String, _ categoryId: String) {
        var d = data
        if let i = d.transactions.firstIndex(where: { $0.id == id }) { d.transactions[i].categoryId = categoryId }
        commit(d, "Category changed", undoable: true)
    }

    // MARK: Accounts

    func saveAccount(_ a: Account) {
        var d = data
        let exists = d.accounts.contains { $0.id == a.id }
        if let i = d.accounts.firstIndex(where: { $0.id == a.id }) { d.accounts[i] = a } else { d.accounts.append(a) }
        commit(d, exists ? "Account updated" : "Account added")
    }

    /// Records the difference to the real balance as an adjustment (never income or expense).
    func reconcile(_ accountId: String, actual: Int) {
        let diff = actual - Finance.balance(data, accountId)
        guard diff != 0 else { say("Already matches your actual balance"); return }
        var d = data
        d.transactions.append(Transaction(type: .ADJUSTMENT, amount: diff, dateTime: D.isoDateTime(Date()), accountId: accountId,
                                          merchant: "Balance reconciliation", note: "Adjusted to match the actual account balance"))
        commit(d, "Balance reconciled", undoable: true)
    }

    // MARK: Categories

    func saveCategory(_ c: Category) {
        var d = data
        if let i = d.categories.firstIndex(where: { $0.id == c.id }) { d.categories[i] = c } else { d.categories.append(c) }
        commit(d)
    }

    func moveCategory(_ c: Category, up: Bool) {
        var siblings = data.categories.filter { $0.kind == c.kind }.sorted { $0.order < $1.order }
        guard let i = siblings.firstIndex(where: { $0.id == c.id }) else { return }
        let j = up ? i - 1 : i + 1
        guard siblings.indices.contains(j) else { return }
        siblings.swapAt(i, j)
        var order: [String: Int] = [:]
        for (k, s) in siblings.enumerated() { order[s.id] = k }
        var d = data
        d.categories = d.categories.map { var x = $0; if let o = order[x.id] { x.order = o }; return x }
        commit(d)
    }

    // MARK: Bills & scheduled income

    func saveRecurring(_ r: Recurring) {
        var d = data
        let exists = d.recurring.contains { $0.id == r.id }
        if let i = d.recurring.firstIndex(where: { $0.id == r.id }) { d.recurring[i] = r } else { d.recurring.append(r) }
        commit(d, exists ? "Saved" : "\(r.name) added")
        recordAutoDebits()
    }

    func cancelRecurring(_ r: Recurring) {
        var d = data
        if let i = d.recurring.firstIndex(where: { $0.id == r.id }) {
            d.recurring[i].cancelled = true
            d.recurring[i].endDate = D.isoDay(D.today)
        }
        commit(d, "\(r.name) cancelled", undoable: true)
    }

    func deleteRecurring(_ r: Recurring) {
        var d = data
        d.recurring.removeAll { $0.id == r.id }
        d.transactions = d.transactions.map { t in
            var t = t
            if t.recurringId == r.id { t.recurringId = nil; t.occurrenceDate = nil }
            return t
        }
        commit(d, "\(r.name) deleted", undoable: true)
    }

    /// Paying a bill creates ONE linked transaction; that link is what marks it paid,
    /// so it can never be deducted twice.
    func markPaid(_ b: BillInstance, amount: Int, date: Date, accountId: String) {
        guard b.payment == nil else { return }
        let r = b.recurring
        var d = data
        d.transactions.append(Transaction(
            type: r.kind == .INCOME ? .INCOME : .EXPENSE, amount: amount,
            dateTime: D.isoDateTime(D.combine(date, hour: 12, minute: 0)), categoryId: r.categoryId, accountId: accountId,
            merchant: r.name, recurringId: r.id, occurrenceDate: D.isoDay(b.due)))
        commit(d, r.kind == .INCOME ? "Marked as received" : "Marked as paid", undoable: true)
    }

    func unmarkPaid(_ b: BillInstance) {
        guard let p = b.payment else { return }
        deleteTransaction(p.id)
    }

    /// Auto-debit bills are recorded as paid on their due date.
    private func recordAutoDebits() {
        let today = D.today
        let due = Finance.instances(data, Finance.distantPast, today, today: today).filter {
            !$0.isPaid && $0.recurring.autoDebit && data.account($0.recurring.accountId) != nil
        }
        guard !due.isEmpty else { return }
        var d = data
        for b in due {
            d.transactions.append(Transaction(
                type: .EXPENSE, amount: b.expected, dateTime: D.isoDateTime(D.combine(b.due, hour: 9, minute: 0)),
                categoryId: b.recurring.categoryId, accountId: b.recurring.accountId ?? "", merchant: b.recurring.name,
                note: "Auto-debit (recorded automatically on the due date)", recurringId: b.recurring.id,
                occurrenceDate: D.isoDay(b.due), demo: b.recurring.demo))
        }
        commit(d)
    }

    // MARK: Budgets & savings

    func saveBudget(_ categoryId: String?, month: YM?, limit: Int, carry: Bool) {
        var d = data
        d.budgets.removeAll { $0.categoryId == categoryId && $0.month == month?.key }
        d.budgets.append(Budget(categoryId: categoryId, month: month?.key, limit: limit, carryForward: carry))
        commit(d, "Budget saved")
    }

    func deleteBudget(_ categoryId: String?, month: YM?) {
        var d = data
        d.budgets.removeAll { $0.categoryId == categoryId && $0.month == month?.key }
        commit(d, "Budget removed", undoable: true)
    }

    func saveSavingsGoal(month: YM?, amount: Int) {
        var d = data
        d.savingsGoals.removeAll { $0.month == month?.key }
        d.savingsGoals.append(SavingsGoal(month: month?.key, amount: amount))
        commit(d, "Savings target saved")
    }

    func deleteSavingsGoal(month: YM?) {
        var d = data
        d.savingsGoals.removeAll { $0.month == month?.key }
        commit(d, "Savings target removed", undoable: true)
    }

    // MARK: Settings & data

    func updateSettings(_ f: (inout Settings) -> Void) {
        var d = data
        f(&d.settings)
        commit(d)
    }

    private func mergeDemo(_ d0: AppData) -> AppData {
        var d = d0
        let demo = DefaultData.demo()
        d.accounts += demo.accounts
        d.transactions += demo.transactions
        d.recurring += demo.recurring
        d.budgets += demo.budgets.filter { b in !d0.budgets.contains { $0.categoryId == b.categoryId && $0.month == nil } }
        return d
    }

    func loadDemo() { commit(mergeDemo(data), "Demo data added"); recordAutoDebits() }

    func removeDemo() {
        let accs = Set(data.accounts.filter { $0.demo }.map { $0.id })
        let bills = Set(data.recurring.filter { $0.demo }.map { $0.id })
        var d = data
        d.accounts.removeAll { $0.demo }
        d.transactions.removeAll { t in
            t.demo || accs.contains(t.accountId) || accs.contains(t.toAccountId ?? "") || bills.contains(t.recurringId ?? "")
        }
        d.recurring.removeAll { $0.demo }
        d.budgets.removeAll { $0.demo }
        commit(d, "Demo data removed", undoable: true)
    }

    func backupData() -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(data)
    }

    /// Throws a readable message when the file isn't a NEXA backup.
    static func readBackup(_ raw: Data) throws -> AppData {
        guard let d = try? JSONDecoder().decode(AppData.self, from: raw) else {
            throw NSError(domain: "NEXA", code: 1, userInfo: [NSLocalizedDescriptionKey: "This file is not a NEXA backup."])
        }
        guard !d.categories.isEmpty else {
            throw NSError(domain: "NEXA", code: 2, userInfo: [NSLocalizedDescriptionKey: "This backup looks incomplete."])
        }
        return DefaultData.withNewDefaults(d)
    }

    func restore(_ backup: AppData) {
        var b = backup
        b.settings.onboarded = true
        commit(b, "Backup restored", undoable: true)
    }

    func deleteAll() {
        commit(AppData(categories: DefaultData.categories()), "All data deleted")
        undoSnapshot = nil
    }
}

/// Local notifications: bill reminders (scheduled ahead) and budget threshold alerts.
enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Re-schedules reminders for the next 60 days of unpaid bills (iOS allows 64 pending).
    static func reschedule(_ d: AppData) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map { $0.identifier }.filter { $0.hasPrefix("bill|") })
            guard d.settings.onboarded, d.settings.billReminders else { return }
            let today = D.today
            let bills = Finance.instances(d, today, D.addDays(today, 60), today: today)
                .filter { !$0.isPaid && !$0.recurring.autoDebit }
                .prefix(50)
            for b in bills {
                let fire = D.combine(D.addDays(b.due, -max(b.recurring.reminderDays, 0)), hour: 9, minute: 0)
                guard fire > Date() else { continue }
                let content = UNMutableNotificationContent()
                content.title = "\(b.recurring.name) is due \(D.dayShortF.string(from: b.due))"
                content.body = "\(Money.format(b.expected)) · open NEXA to mark it paid"
                content.sound = .default
                let comps = D.cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let req = UNNotificationRequest(identifier: "bill|\(b.id)", content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                center.add(req)
            }
        }
    }

    /// Alerts immediately when a change pushes a budget across 80/90/100%.
    static func budgetCrossings(old: AppData, new: AppData) {
        guard new.settings.onboarded else { return }
        let m = YM.now()
        let before = Dictionary(uniqueKeysWithValues: rows(old, m).map { ($0.id, Finance.crossedThreshold(old, $0) ?? 0) })
        for r in rows(new, m) {
            guard let t = Finance.crossedThreshold(new, r), t > (before[r.id] ?? 0) else { continue }
            let content = UNMutableNotificationContent()
            let name = r.category?.name ?? "Monthly"
            content.title = t >= 100 ? "\(name) budget exceeded" : "\(name) budget at \(t)%"
            content.body = "\(Money.format(r.spent)) of \(Money.format(r.limit)) spent"
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "budget|\(r.id)|\(m.key)|\(t)", content: content, trigger: nil))
        }
    }

    private static func rows(_ d: AppData, _ m: YM) -> [BudgetRow] {
        (Finance.overallBudget(d, m).map { [$0] } ?? []) + Finance.categoryBudgets(d, m)
    }
}

import Foundation

/*
 Data schema — identical JSON to the Android app, so backups move between phones.

   Account 1───* Transaction (accountId; toAccountId for transfers)
   Category 1──* Transaction (categoryId)
   Category 1──* Budget (categoryId; nil = overall monthly budget)
   Recurring 1─* Transaction (recurringId + occurrenceDate = a paid bill / received income)

 Money is stored as whole sen (Int, RM 1.00 = 100) so totals never drift.
*/

enum TxType: String, Codable, CaseIterable { case INCOME, EXPENSE, TRANSFER, ADJUSTMENT }
enum TxSource: String, Codable { case MANUAL, IMPORTED, SYNCED }
enum CategoryKind: String, Codable, CaseIterable { case EXPENSE, INCOME }
enum RecurringKind: String, Codable, CaseIterable { case BILL, INCOME }

enum AccountType: String, Codable, CaseIterable {
    case BANK, SAVINGS, EWALLET, CASH, CREDIT_CARD
    var label: String {
        switch self {
        case .BANK: return "Bank account"
        case .SAVINGS: return "Savings"
        case .EWALLET: return "E-wallet"
        case .CASH: return "Cash"
        case .CREDIT_CARD: return "Credit card"
        }
    }
}

enum Frequency: String, Codable, CaseIterable {
    case WEEKLY, MONTHLY, QUARTERLY, YEARLY
    var label: String {
        switch self {
        case .WEEKLY: return "Weekly"
        case .MONTHLY: return "Monthly"
        case .QUARTERLY: return "Quarterly"
        case .YEARLY: return "Yearly"
        }
    }
}

struct Account: Codable, Identifiable, Equatable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var type: AccountType
    /// Balance before the first recorded transaction. Negative for credit card debt.
    var openingBalance: Int = 0
    var archived: Bool = false
    var demo: Bool = false
}

struct Category: Codable, Identifiable, Equatable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var kind: CategoryKind
    var color: Int
    var icon: String
    var order: Int
    var archived: Bool = false
}

struct Transaction: Codable, Identifiable, Equatable, Hashable {
    var id: String = UUID().uuidString
    var type: TxType
    /// Always positive, except ADJUSTMENT which is signed.
    var amount: Int
    /// Local date-time, e.g. "2026-10-21T14:30".
    var dateTime: String
    var categoryId: String? = nil
    var subcategory: String = ""
    var accountId: String
    var toAccountId: String? = nil
    var merchant: String = ""
    var note: String = ""
    var source: TxSource = .MANUAL
    var recurringId: String? = nil
    /// Due date (yyyy-MM-dd) of the bill instance this pays.
    var occurrenceDate: String? = nil
    var importKey: String? = nil
    var demo: Bool = false

    var at: Date { D.parseDateTime(dateTime) }
    var day: Date { D.startOfDay(at) }
    var ym: YM { YM(at) }
}

struct Recurring: Codable, Identifiable, Equatable, Hashable {
    var id: String = UUID().uuidString
    var kind: RecurringKind
    var name: String
    var amount: Int
    var frequency: Frequency
    var startDate: String
    var endDate: String? = nil
    /// Due dates before this are history from before the bill was added — never overdue.
    var trackFrom: String
    var categoryId: String? = nil
    var accountId: String? = nil
    var autoDebit: Bool = false
    var reminderDays: Int = 3
    var note: String = ""
    var promoAmount: Int = 0
    var promoCount: Int = 0
    var cancelled: Bool = false
    var demo: Bool = false

    var hasPromo: Bool { promoCount > 0 && promoAmount > 0 }
}

struct Budget: Codable, Identifiable, Equatable, Hashable {
    var id: String = UUID().uuidString
    var categoryId: String? = nil
    /// "2026-10" for one month only, nil for every month.
    var month: String? = nil
    var limit: Int
    var carryForward: Bool = false
    var demo: Bool = false
}

struct SavingsGoal: Codable, Equatable, Hashable {
    var month: String? = nil
    var amount: Int
}

struct Settings: Codable, Equatable {
    var onboarded: Bool = false
    var alert80: Bool = true
    var alert90: Bool = true
    var alert100: Bool = true
    var billReminders: Bool = true
    var insights: Bool = true
    var reservedFunds: Int = 0
    /// iPhone only: ask for Face ID / passcode when opening the app.
    var appLock: Bool = false
}

struct AppData: Codable, Equatable {
    var version: Int = 1
    var accounts: [Account] = []
    var categories: [Category] = []
    var transactions: [Transaction] = []
    var recurring: [Recurring] = []
    var budgets: [Budget] = []
    var savingsGoals: [SavingsGoal] = []
    var settings: Settings = Settings()

    func category(_ id: String?) -> Category? { guard let id else { return nil }; return categories.first { $0.id == id } }
    func account(_ id: String?) -> Account? { guard let id else { return nil }; return accounts.first { $0.id == id } }
    var hasDemo: Bool {
        accounts.contains { $0.demo } || transactions.contains { $0.demo } || recurring.contains { $0.demo } || budgets.contains { $0.demo }
    }
}

// MARK: - Tolerant decoding (missing keys fall back to defaults, like the Android app)

extension KeyedDecodingContainer {
    func v<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
    func opt<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}

extension Account {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(AccountType.self, forKey: .type)
        openingBalance = c.v(.openingBalance, 0)
        archived = c.v(.archived, false)
        demo = c.v(.demo, false)
    }
}

extension Category {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(CategoryKind.self, forKey: .kind)
        color = c.v(.color, 0xFF8A93A6)
        icon = c.v(.icon, "more")
        order = c.v(.order, 0)
        archived = c.v(.archived, false)
    }
}

extension Transaction {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(TxType.self, forKey: .type)
        amount = try c.decode(Int.self, forKey: .amount)
        dateTime = try c.decode(String.self, forKey: .dateTime)
        categoryId = c.opt(.categoryId)
        subcategory = c.v(.subcategory, "")
        accountId = try c.decode(String.self, forKey: .accountId)
        toAccountId = c.opt(.toAccountId)
        merchant = c.v(.merchant, "")
        note = c.v(.note, "")
        source = c.v(.source, TxSource.MANUAL)
        recurringId = c.opt(.recurringId)
        occurrenceDate = c.opt(.occurrenceDate)
        importKey = c.opt(.importKey)
        demo = c.v(.demo, false)
    }
}

extension Recurring {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(RecurringKind.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        amount = try c.decode(Int.self, forKey: .amount)
        frequency = c.v(.frequency, Frequency.MONTHLY)
        startDate = try c.decode(String.self, forKey: .startDate)
        endDate = c.opt(.endDate)
        trackFrom = c.v(.trackFrom, startDate)
        categoryId = c.opt(.categoryId)
        accountId = c.opt(.accountId)
        autoDebit = c.v(.autoDebit, false)
        reminderDays = c.v(.reminderDays, 3)
        note = c.v(.note, "")
        promoAmount = c.v(.promoAmount, 0)
        promoCount = c.v(.promoCount, 0)
        cancelled = c.v(.cancelled, false)
        demo = c.v(.demo, false)
    }
}

extension Budget {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, UUID().uuidString)
        categoryId = c.opt(.categoryId)
        month = c.opt(.month)
        limit = try c.decode(Int.self, forKey: .limit)
        carryForward = c.v(.carryForward, false)
        demo = c.v(.demo, false)
    }
}

extension SavingsGoal {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        month = c.opt(.month)
        amount = try c.decode(Int.self, forKey: .amount)
    }
}

extension Settings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        onboarded = c.v(.onboarded, false)
        alert80 = c.v(.alert80, true)
        alert90 = c.v(.alert90, true)
        alert100 = c.v(.alert100, true)
        billReminders = c.v(.billReminders, true)
        insights = c.v(.insights, true)
        reservedFunds = c.v(.reservedFunds, 0)
        appLock = c.v(.appLock, false)
    }
}

extension AppData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.v(.version, 1)
        accounts = c.v(.accounts, [])
        categories = c.v(.categories, [])
        transactions = c.v(.transactions, [])
        recurring = c.v(.recurring, [])
        budgets = c.v(.budgets, [])
        savingsGoals = c.v(.savingsGoals, [])
        settings = c.v(.settings, Settings())
    }
}

// MARK: - Money

enum Money {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    /// 123456 -> "RM 1,234.56"
    static func format(_ sen: Int, plus: Bool = false) -> String {
        let sign = sen < 0 ? "-" : (plus && sen > 0 ? "+" : "")
        let value = formatter.string(from: NSNumber(value: Double(abs(sen)) / 100)) ?? "0.00"
        return "\(sign)RM \(value)"
    }

    static func short(_ sen: Int) -> String {
        let rm = Double(abs(sen)) / 100
        let sign = sen < 0 ? "-" : ""
        if rm >= 1_000_000 { return String(format: "%@RM %.1fm", sign, rm / 1_000_000) }
        if rm >= 1_000 { return String(format: "%@RM %.1fk", sign, rm / 1_000) }
        return String(format: "%@RM %.0f", sign, rm)
    }

    /// "1,234.5" / "RM 12" -> sen. nil when the text is not a valid amount.
    static func parse(_ text: String) -> Int? {
        let t = text.replacingOccurrences(of: "RM", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !t.isEmpty, t != ".", t != "-",
              t.range(of: #"^-?\d{0,12}(\.\d*)?$"#, options: .regularExpression) != nil,
              var d = Decimal(string: t, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        d *= 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &d, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// 8500 -> "85", 8550 -> "85.50"
    static func plain(_ sen: Int) -> String {
        if sen % 100 == 0 { return String(sen / 100) }
        return String(format: "%.2f", Double(sen) / 100)
    }
}

// MARK: - Dates

/// A calendar month.
struct YM: Hashable, Comparable {
    var year: Int
    var month: Int

    init(year: Int, month: Int) { self.year = year; self.month = month }
    init(_ date: Date) {
        let c = D.cal.dateComponents([.year, .month], from: date)
        year = c.year ?? 2000
        month = c.month ?? 1
    }
    init?(key: String) {
        let p = key.split(separator: "-")
        guard p.count == 2, let y = Int(p[0]), let m = Int(p[1]) else { return nil }
        year = y; month = m
    }
    static func now() -> YM { YM(Date()) }
    static func < (a: YM, b: YM) -> Bool { a.index < b.index }

    var index: Int { year * 12 + month - 1 }
    func plus(_ n: Int) -> YM {
        let i = index + n
        return YM(year: Int(floor(Double(i) / 12)), month: ((i % 12) + 12) % 12 + 1)
    }
    var first: Date { D.cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date() }
    var length: Int { D.cal.range(of: .day, in: .month, for: first)?.count ?? 30 }
    var last: Date { D.addDays(first, length - 1) }
    var key: String { String(format: "%04d-%02d", year, month) }
    func day(_ d: Int) -> Date { D.addDays(first, min(max(d, 1), length) - 1) }
}

enum D {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_MY")
        c.timeZone = .current
        return c
    }()

    private static func fmt(_ pattern: String, posix: Bool = false) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: posix ? "en_US_POSIX" : "en_MY")
        f.calendar = cal
        f.timeZone = .current
        f.dateFormat = pattern
        return f
    }

    private static let isoDayF = fmt("yyyy-MM-dd", posix: true)
    private static let isoDTF = fmt("yyyy-MM-dd'T'HH:mm", posix: true)
    static let dayF = fmt("d MMM yyyy")
    static let dayShortF = fmt("d MMM")
    static let weekdayF = fmt("EEE, d MMM yyyy")
    static let monthF = fmt("MMMM yyyy")
    static let monthShortF = fmt("MMM")
    static let monthYearF = fmt("MMM yyyy")
    static let timeF = fmt("h:mm a")

    private static var cache: [String: Date] = [:]

    static func parseDateTime(_ s: String) -> Date {
        if let hit = cache[s] { return hit }
        let d = isoDTF.date(from: String(s.prefix(16))) ?? isoDayF.date(from: String(s.prefix(10))) ?? Date()
        cache[s] = d
        return d
    }
    static func parseDay(_ s: String) -> Date { startOfDay(isoDayF.date(from: String(s.prefix(10))) ?? Date()) }
    static func isoDay(_ d: Date) -> String { isoDayF.string(from: d) }
    static func isoDateTime(_ d: Date) -> String { isoDTF.string(from: d) }

    static func startOfDay(_ d: Date) -> Date { cal.startOfDay(for: d) }
    static var today: Date { startOfDay(Date()) }
    static func addDays(_ d: Date, _ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: d) ?? d }
    static func addMonths(_ d: Date, _ n: Int) -> Date { cal.date(byAdding: .month, value: n, to: d) ?? d }
    static func addYears(_ d: Date, _ n: Int) -> Date { cal.date(byAdding: .year, value: n, to: d) ?? d }
    static func days(from a: Date, to b: Date) -> Int { cal.dateComponents([.day], from: startOfDay(a), to: startOfDay(b)).day ?? 0 }
    static func dayOfMonth(_ d: Date) -> Int { cal.component(.day, from: d) }
    static func combine(_ day: Date, hour: Int, minute: Int) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
    /// Monday of the week containing d.
    static func weekStart(_ d: Date) -> Date {
        let wd = cal.component(.weekday, from: d) // 1 = Sunday
        return addDays(startOfDay(d), -((wd + 5) % 7))
    }
}

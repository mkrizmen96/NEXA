import Foundation

enum DefaultData {
    static func categories() -> [Category] {
        let expense: [(String, String, Int, String)] = [
            ("exp_food", "Food & Dining", 0xFFFF9F6E, "restaurant"),
            ("exp_groceries", "Groceries", 0xFF8BD17C, "cart"),
            ("exp_transport", "Petrol & Transportation", 0xFF6EA8FE, "car"),
            ("exp_bills", "Bills & Utilities", 0xFFE9BE73, "bolt"),
            ("exp_housing", "Housing", 0xFFB59CFF, "home"),
            ("exp_loans", "Loans & Installments", 0xFFFF7785, "bank"),
            ("exp_insurance", "Insurance", 0xFF4FC3F7, "shield"),
            ("exp_health", "Health", 0xFFFF8FB1, "health"),
            ("exp_shopping", "Shopping", 0xFFFFC857, "bag"),
            ("exp_entertainment", "Entertainment", 0xFFC792EA, "movie"),
            ("exp_subscriptions", "Subscriptions", 0xFF7FDBCA, "repeat"),
            ("exp_family", "Family", 0xFFF78C6C, "family"),
            ("exp_travel", "Travel", 0xFF82AAFF, "flight"),
            ("exp_work", "Work Expenses", 0xFFA3B1C6, "work"),
            ("exp_savings", "Savings Contributions", 0xFF58E0B0, "savings"),
            ("exp_other", "Other Expenses", 0xFF8A93A6, "more"),
        ]
        let income: [(String, String, Int, String)] = [
            ("inc_salary", "Fixed salary", 0xFF58E0B0, "wallet"),
            ("inc_overtime", "Overtime (OT)", 0xFF7FDBCA, "clock"),
            ("inc_claim", "Claim", 0xFF6EA8FE, "receipt"),
            ("inc_bonus", "Bonus", 0xFFE9BE73, "star"),
            ("inc_freelance", "Freelance", 0xFFB59CFF, "laptop"),
            ("inc_business", "Business", 0xFFC792EA, "store"),
            ("inc_other", "Other Income", 0xFFA3B1C6, "more"),
        ]
        return expense.enumerated().map { i, e in Category(id: e.0, name: e.1, kind: .EXPENSE, color: e.2, icon: e.3, order: i) }
            + income.enumerated().map { i, e in Category(id: e.0, name: e.1, kind: .INCOME, color: e.2, icon: e.3, order: i) }
    }

    private static let renamed: [String: (String, String)] = [
        "inc_salary": ("Salary", "Fixed salary"),
        "inc_overtime": ("Overtime", "Overtime (OT)"),
    ]

    /// Adds default categories introduced later (e.g. Claim) without touching user renames.
    static func withNewDefaults(_ data: AppData) -> AppData {
        var d = data
        d.categories = d.categories.map { c in
            var c = c
            if let r = renamed[c.id], c.name == r.0 { c.name = r.1 }
            return c
        }
        for def in categories() where !d.categories.contains(where: { $0.id == def.id }) {
            d.categories.append(def)
        }
        return d
    }

    /// Clearly labelled demo data (demo = true). Settings → Backup & data removes it in one tap.
    static func demo(today: Date = D.today) -> AppData {
        let bank = Account(name: "Maybank (demo)", type: .BANK, openingBalance: 4_200_00, demo: true)
        let wallet = Account(name: "Touch 'n Go (demo)", type: .EWALLET, openingBalance: 150_00, demo: true)
        let card = Account(name: "Credit card (demo)", type: .CREDIT_CARD, openingBalance: 0, demo: true)
        var tx: [Transaction] = []
        func add(_ day: Date, _ type: TxType, _ amount: Int, _ cat: String?, _ acc: Account, _ merchant: String, to: Account? = nil) {
            guard day <= today else { return }
            tx.append(Transaction(type: type, amount: amount, dateTime: D.isoDateTime(D.combine(day, hour: 12, minute: 0)),
                                  categoryId: cat, accountId: acc.id, toAccountId: to?.id, merchant: merchant, demo: true))
        }
        let thisMonth = YM(today)
        for m in 0...5 {
            let first = thisMonth.plus(-m).first
            add(first, .INCOME, 5_200_00, "inc_salary", bank, "Salary")
            add(D.addDays(first, 2), .INCOME, 180_00 + m * 40_00, "inc_overtime", bank, "OT")
            if m % 2 == 0 { add(D.addDays(first, 4), .INCOME, 95_00, "inc_claim", bank, "Mileage claim") }
            add(D.addDays(first, 1), .EXPENSE, 1_200_00, "exp_housing", bank, "Rent")
            add(D.addDays(first, 3), .EXPENSE, 380_00 + m * 25_00, "exp_groceries", card, "Lotus's")
            add(D.addDays(first, 5), .EXPENSE, 160_00, "exp_transport", wallet, "Petronas")
            add(D.addDays(first, 8), .EXPENSE, 220_00 + (m % 3) * 60_00, "exp_food", card, "GrabFood")
            add(D.addDays(first, 12), .EXPENSE, 129_00, "exp_bills", bank, "Unifi")
            add(D.addDays(first, 15), .EXPENSE, 150_00 + (m % 2) * 210_00, "exp_shopping", card, "Shopee")
            add(D.addDays(first, 18), .TRANSFER, 600_00, nil, bank, "Card repayment", to: card)
            add(D.addDays(first, 20), .EXPENSE, 55_00, "exp_subscriptions", card, "Netflix")
        }
        let trackFrom = D.isoDay(thisMonth.first)
        let bills = [
            Recurring(kind: .BILL, name: "Car loan (demo)", amount: 850_00, frequency: .MONTHLY,
                      startDate: D.isoDay(D.addYears(thisMonth.day(5), -2)), endDate: D.isoDay(D.addYears(thisMonth.day(5), 7)),
                      trackFrom: trackFrom, categoryId: "exp_loans", accountId: bank.id, demo: true),
            Recurring(kind: .BILL, name: "Coway mattress (demo)", amount: 95_00, frequency: .MONTHLY,
                      startDate: "2026-04-07", endDate: "2033-03-07", trackFrom: trackFrom, categoryId: "exp_housing",
                      accountId: bank.id, promoAmount: 85_00, promoCount: 18, demo: true),
            Recurring(kind: .BILL, name: "Phone bill (demo)", amount: 98_00, frequency: .MONTHLY,
                      startDate: D.isoDay(thisMonth.day(25)), trackFrom: trackFrom, categoryId: "exp_bills",
                      accountId: bank.id, autoDebit: true, demo: true),
        ]
        let budgets = [
            Budget(categoryId: nil, limit: 3_000_00, demo: true),
            Budget(categoryId: "exp_food", limit: 300_00, demo: true),
            Budget(categoryId: "exp_groceries", limit: 450_00, demo: true),
            Budget(categoryId: "exp_shopping", limit: 250_00, demo: true),
            Budget(categoryId: "exp_transport", limit: 250_00, demo: true),
        ]
        return AppData(accounts: [bank, wallet, card], transactions: tx, recurring: bills, budgets: budgets)
    }
}

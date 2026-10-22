import UIKit

/// Reports, CSV/Excel export and the PDF report — all built from stored transactions.
enum Reports {
    struct Report {
        let from: Date
        let to: Date
        let summary: Summary
        let expenses: [Slice]
        let incomes: [Slice]
        let months: [MonthPoint]
        let budgets: [(YM, BudgetRow)]
        let bills: [BillInstance]
        let count: Int
    }

    static func build(_ d: AppData, _ from: Date, _ to: Date) -> Report {
        let first = YM(from), last = YM(to)
        let n = max(1, last.index - first.index + 1)
        let months = Finance.monthly(d, months: n, end: last)
        var budgets: [(YM, BudgetRow)] = []
        for mp in months {
            if let o = Finance.overallBudget(d, mp.month) { budgets.append((mp.month, o)) }
            for r in Finance.categoryBudgets(d, mp.month) { budgets.append((mp.month, r)) }
        }
        return Report(from: from, to: to, summary: Finance.summary(d, from, to),
                      expenses: Finance.breakdown(d, from, to, type: .EXPENSE),
                      incomes: Finance.breakdown(d, from, to, type: .INCOME),
                      months: months, budgets: budgets,
                      bills: Finance.instances(d, from, to),
                      count: d.transactions.filter { Finance.inRange($0, from, to) }.count)
    }

    static func lines(_ r: Report) -> [(String, String)] {
        [
            ("Period", "\(D.dayF.string(from: r.from)) – \(D.dayF.string(from: r.to))"),
            ("Total income", Money.format(r.summary.income)),
            ("Total expenses", Money.format(r.summary.expense)),
            ("Net cash flow", Money.format(r.summary.net, plus: true)),
            ("Savings", Money.format(r.summary.savings)),
            ("Savings rate", r.summary.savingsRate.map { "\(Int($0 * 100))%" } ?? "–"),
            ("Transactions", "\(r.count)"),
        ]
    }

    private static func esc(_ s: String) -> String {
        s.contains(",") || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    /// Excel mode adds a BOM and CRLF so Excel opens it with the right encoding and columns.
    static func csv(_ d: AppData, _ from: Date, _ to: Date, excel: Bool) -> String {
        let nl = excel ? "\r\n" : "\n"
        var s = excel ? "\u{FEFF}" : ""
        s += "Date,Time,Type,Amount (MYR),Category,Account,To account,Merchant,Note,Source" + nl
        for t in d.transactions.filter({ Finance.inRange($0, from, to) }).sorted(by: { $0.at < $1.at }) {
            let signed = t.type == .EXPENSE ? -t.amount : t.amount
            let cols = [
                D.isoDay(t.at), String(t.dateTime.dropFirst(11).prefix(5)), t.type.rawValue.lowercased(),
                String(format: "%.2f", Double(signed) / 100), d.category(t.categoryId)?.name ?? "",
                d.account(t.accountId)?.name ?? "", d.account(t.toAccountId)?.name ?? "", t.merchant, t.note,
                t.source.rawValue.lowercased(),
            ]
            s += cols.map(esc).joined(separator: ",") + nl
        }
        return s
    }

    /// A4 PDF report.
    static func pdf(_ d: AppData, _ r: Report) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 40
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 20)]
        let h2: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 13)]
        let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10.5)]
        let muted: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.gray]

        return renderer.pdfData { ctx in
            var y: CGFloat = 0
            func newPage() { ctx.beginPage(); y = margin }
            func ensure(_ h: CGFloat) { if y + h > page.height - margin { newPage() } }
            func text(_ s: String, _ a: [NSAttributedString.Key: Any], _ gap: CGFloat = 16) {
                ensure(gap); (s as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: a); y += gap
            }
            func row(_ l: String, _ r: String) {
                ensure(15)
                (String(l.prefix(60)) as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: body)
                let w = (r as NSString).size(withAttributes: body).width
                (r as NSString).draw(at: CGPoint(x: page.width - margin - w, y: y), withAttributes: body)
                y += 15
            }
            newPage()
            text("NEXA Personal Finance report", title, 28)
            text("\(D.dayF.string(from: r.from)) – \(D.dayF.string(from: r.to)) · generated \(D.dayF.string(from: Date()))", muted, 24)
            text("Summary", h2, 20)
            for (k, v) in lines(r) { row(k, v) }
            y += 10; text("Expenses by category", h2, 20)
            if r.expenses.isEmpty { text("No expenses in this period.", muted) }
            for s in r.expenses { row("\(s.category?.name ?? "Uncategorised") (\(Int(s.share * 100))%)", Money.format(s.amount)) }
            y += 10; text("Income by category", h2, 20)
            if r.incomes.isEmpty { text("No income in this period.", muted) }
            for s in r.incomes { row(s.category?.name ?? "Uncategorised", Money.format(s.amount)) }
            if r.months.count > 1 {
                y += 10; text("Month by month", h2, 20)
                for m in r.months {
                    row(D.monthYearF.string(from: m.month.first),
                        "In \(Money.format(m.income))   Out \(Money.format(m.expense))   Net \(Money.format(m.net, plus: true))")
                }
            }
            y += 10; text("Budget performance", h2, 20)
            if r.budgets.isEmpty { text("No budgets set.", muted) }
            for (m, b) in r.budgets { row("\(D.monthYearF.string(from: m.first)) · \(b.category?.name ?? "Total")", "\(Money.format(b.spent)) of \(Money.format(b.limit))") }
            y += 10; text("Commitment payments", h2, 20)
            if r.bills.isEmpty { text("No bills due.", muted) }
            for b in r.bills { row("\(D.dayF.string(from: b.due)) · \(b.recurring.name)", "\(Money.format(b.amount)) · \(b.isPaid ? "Paid" : b.status.rawValue)") }
            y += 10; text("Transactions", h2, 20)
            for t in d.transactions.filter({ Finance.inRange($0, r.from, r.to) }).sorted(by: { $0.at < $1.at }) {
                row("\(D.dayShortF.string(from: t.at))  \(UI.title(d, t))", UI.signed(t))
            }
        }
    }

    /// Writes data to a temporary file to hand to the share sheet ("Save to Files", AirDrop, WhatsApp…).
    static func tempFile(_ name: String, _ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }
}

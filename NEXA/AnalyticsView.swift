import SwiftUI
import Charts

enum Span: String, CaseIterable { case week = "Week", month = "Month", year = "Year" }

struct BarPoint: Identifiable {
    let label: String
    let series: String
    let value: Double
    var id: String { label + series }
}

struct AnalyticsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var span: Span = .month
    @State private var months = 6
    @State private var days = 30
    @State private var angle: Int?
    @State private var selectedSlice: Int?
    @State private var selectedMonth: String?
    @State private var selectedDay: Date?

    private var range: (Date, Date) {
        let t = D.today
        switch span {
        case .week: let s = D.weekStart(t); return (s, D.addDays(s, 6))
        case .month: let m = YM(t); return (m.first, m.last)
        case .year: let y = YM(t).year; return (YM(year: y, month: 1).first, YM(year: y, month: 12).last)
        }
    }

    private var previous: (Date, Date) {
        let (f, t) = range
        switch span {
        case .week: return (D.addDays(f, -7), D.addDays(t, -7))
        case .month: let m = YM(f).plus(-1); return (m.first, m.last)
        case .year: return (D.addYears(f, -1), D.addYears(t, -1))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                donutCard
                incomeExpenseCard
                budgetCard
                dailyCard
                summaryCard
            }
            .padding(16)
        }
        .nexaBackground()
        .navigationTitle("Analytics")
        .onChange(of: span) { _, _ in selectedSlice = nil }
    }

    // A. Expense breakdown
    private var donutCard: some View {
        let d = store.data
        let (f, t) = range
        let (pf, pt) = previous
        let slices = Finance.breakdown(d, f, t)
        let prev = Finance.breakdown(d, pf, pt)
        let total = slices.reduce(0) { $0 + $1.amount }
        let prevTotal = prev.reduce(0) { $0 + $1.amount }
        let sel = selectedSlice.flatMap { $0 < slices.count ? slices[$0] : nil }
        return Card {
            Text("Spending by category").font(.headline)
            ChipRow(options: Span.allCases, selected: $span) { $0.rawValue }
            Text("\(D.dayShortF.string(from: f)) – \(D.dayF.string(from: t))").font(.caption).foregroundStyle(Theme.muted)
            if slices.isEmpty {
                EmptyStateView(title: "No spending in this period", message: "Expenses you record will appear here.")
            } else {
                Chart(Array(slices.enumerated()), id: \.element.id) { i, s in
                    SectorMark(angle: .value("Amount", s.amount), innerRadius: .ratio(0.62),
                               outerRadius: .ratio(selectedSlice == i ? 1.0 : 0.92), angularInset: 1.5)
                        .foregroundStyle(UI.color(s.category))
                        .opacity(selectedSlice == nil || selectedSlice == i ? 1 : 0.35)
                }
                .chartAngleSelection(value: $angle)
                .onChange(of: angle) { _, a in
                    guard let a else { return }
                    var acc = 0
                    for (i, s) in slices.enumerated() { acc += s.amount; if a <= acc { selectedSlice = selectedSlice == i ? nil : i; break } }
                }
                .chartBackground { _ in
                    VStack(spacing: 2) {
                        Text(sel?.category?.name ?? "Total spent").font(.caption).foregroundStyle(Theme.muted).lineLimit(1).frame(maxWidth: 110)
                        Text(Money.format(sel?.amount ?? total)).font(.headline)
                        if let sel { Text("\(Int((sel.share * 100).rounded()))%").font(.subheadline.weight(.semibold)).foregroundStyle(UI.color(sel.category)) }
                    }
                }
                .frame(height: 220)
                .padding(.vertical, 6)

                let change = Finance.percentChange(total, prevTotal)
                Text(change.map { "\($0 >= 0 ? "▲" : "▼") \(Int((abs($0) * 100).rounded()))% vs previous \(span.rawValue.lowercased()) (\(Money.format(prevTotal)))" }
                     ?? "No spending in the previous \(span.rawValue.lowercased()) to compare.")
                    .font(.caption).foregroundStyle((change ?? 0) > 0 ? Theme.red : Theme.mint)

                ForEach(Array(slices.enumerated()), id: \.element.id) { i, s in
                    let p = prev.first { $0.id == s.id }?.amount ?? 0
                    let pc = Finance.percentChange(s.amount, p)
                    Button { router.push(.category(s.category?.id ?? Finance.uncategorised, f, t)) } label: {
                        HStack(spacing: 10) {
                            Circle().fill(UI.color(s.category)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.category?.name ?? "Uncategorised").font(.subheadline)
                                Text(pc.map { "\($0 >= 0 ? "+" : "−")\(Int((abs($0) * 100).rounded()))% vs before" } ?? "New this \(span.rawValue.lowercased())")
                                    .font(.caption2).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(Money.format(s.amount)).font(.subheadline)
                            Text("\(Int((s.share * 100).rounded()))%").font(.caption).foregroundStyle(Theme.muted).frame(width: 36, alignment: .trailing)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 6)
                        .background(selectedSlice == i ? Theme.cardHigh : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // B. Income vs expenses
    private var incomeExpenseCard: some View {
        let points = Finance.monthly(store.data, months: months, end: .now())
        let label: (YM) -> String = { m in months == 12 ? D.monthYearF.string(from: m.first) : D.monthShortF.string(from: m.first) }
        let bars = points.flatMap { p in
            [BarPoint(label: label(p.month), series: "Income", value: Double(p.income) / 100),
             BarPoint(label: label(p.month), series: "Expenses", value: Double(p.expense) / 100)]
        }
        let maxV = max(bars.map { $0.value }.max() ?? 1, 1)
        let sel = points.first { label($0.month) == selectedMonth } ?? points.last
        return Card {
            HStack {
                Text("Income vs expenses").font(.headline)
                Spacer()
                Chip(text: "6M", selected: months == 6) { months = 6; selectedMonth = nil }
                Chip(text: "12M", selected: months == 12) { months = 12; selectedMonth = nil }
            }
            Chart {
                ForEach(points.filter { $0.net < 0 }) { p in
                    RectangleMark(x: .value("Month", label(p.month)), yStart: .value("RM", 0.0), yEnd: .value("RM", maxV))
                        .foregroundStyle(Theme.red.opacity(0.08))
                }
                ForEach(bars) { b in
                    BarMark(x: .value("Month", b.label), y: .value("RM", b.value))
                        .foregroundStyle(by: .value("Type", b.series))
                        .position(by: .value("Type", b.series))
                        .cornerRadius(4)
                        .opacity(selectedMonth == nil || selectedMonth == b.label ? 1 : 0.4)
                }
            }
            .chartForegroundStyleScale(["Income": Theme.mint, "Expenses": Theme.red])
            .chartXSelection(value: $selectedMonth)
            .chartYAxis { AxisMarks { v in AxisGridLine().foregroundStyle(Theme.border); AxisValueLabel().foregroundStyle(Theme.muted) } }
            .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.muted) } }
            .chartLegend(position: .bottom)
            .frame(height: 200)
            Text("Red tint = spent more than earned").font(.caption2).foregroundStyle(Theme.muted)
            if let sel {
                Divider().overlay(Theme.border)
                Text(D.monthF.string(from: sel.month.first)).font(.subheadline.weight(.semibold))
                LabelValue(label: "Income", value: Money.format(sel.income), color: Theme.mint)
                LabelValue(label: "Expenses", value: Money.format(sel.expense), color: Theme.red)
                LabelValue(label: "Net cash flow", value: Money.format(sel.net, plus: true), color: sel.net >= 0 ? Theme.mint : Theme.red)
            }
        }
    }

    // C. Budget vs actual
    private var budgetCard: some View {
        let m = YM.now()
        let rows = (Finance.overallBudget(store.data, m).map { [$0] } ?? []) + Finance.categoryBudgets(store.data, m)
        return Card {
            Text("Budget vs actual · \(D.monthYearF.string(from: m.first))").font(.headline)
            if rows.isEmpty {
                EmptyStateView(title: "No budgets yet", message: "Set budgets in Budgets & Bills to compare limits with spending.")
                Button("Set budgets") { router.tab = .plan }.buttonStyle(SecondaryButtonStyle())
            }
            ForEach(rows) { row in
                Button {
                    if let c = row.category { router.push(.category(c.id, m.first, m.last)) }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(row.category?.name ?? "Total budget").font(.subheadline.weight(row.category == nil ? .semibold : .regular))
                            Spacer()
                            Text("\(Money.format(row.spent)) / \(Money.format(row.limit))").font(.caption).foregroundStyle(Theme.muted)
                        }
                        ProgressBar(ratio: row.ratio, color: Theme.level(row.level), height: 10)
                        Text(row.remaining >= 0 ? "\(Money.format(row.remaining)) left" : "\(Money.format(-row.remaining)) over budget")
                            .font(.caption2).foregroundStyle(Theme.level(row.level))
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // D. Daily spending
    private var dailyCard: some View {
        let points = Finance.daily(store.data, days: days, end: D.today)
        let sel = selectedDay.flatMap { s in points.first { $0.date == D.startOfDay(s) } }
        let avg = points.isEmpty ? 0 : points.reduce(0) { $0 + $1.amount } / points.count
        let spikes = points.filter { $0.spike }
        return Card {
            HStack {
                Text("Daily spending").font(.headline)
                Spacer()
                ForEach([7, 30, 90], id: \.self) { n in Chip(text: "\(n)D", selected: days == n) { days = n; selectedDay = nil } }
            }
            if points.allSatisfy({ $0.amount == 0 }) {
                EmptyStateView(title: "No spending yet", message: "Daily totals will show here.")
            } else {
                Chart {
                    ForEach(points) { p in
                        AreaMark(x: .value("Day", p.date, unit: .day), y: .value("RM", Double(p.amount) / 100))
                            .foregroundStyle(Theme.mint.opacity(0.1))
                        LineMark(x: .value("Day", p.date, unit: .day), y: .value("RM", Double(p.amount) / 100))
                            .foregroundStyle(Theme.mint)
                    }
                    ForEach(spikes) { p in
                        PointMark(x: .value("Day", p.date, unit: .day), y: .value("RM", Double(p.amount) / 100))
                            .foregroundStyle(Theme.red)
                    }
                    if let sel {
                        RuleMark(x: .value("Day", sel.date, unit: .day)).foregroundStyle(Theme.text.opacity(0.3))
                    }
                }
                .chartXSelection(value: $selectedDay)
                .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Theme.border); AxisValueLabel().foregroundStyle(Theme.muted) } }
                .chartXAxis { AxisMarks { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.muted) } }
                .frame(height: 180)
                if let sel {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(D.weekdayF.string(from: sel.date)).font(.subheadline.weight(.semibold))
                            Text(Money.format(sel.amount) + (sel.spike ? " · unusually high" : "")).font(.caption)
                                .foregroundStyle(sel.spike ? Theme.red : Theme.muted)
                        }
                        Spacer()
                        Button("View") { router.push(.day(sel.date)) }.foregroundStyle(Theme.mint)
                    }
                } else {
                    Text("Average \(Money.format(avg)) a day · tap the chart to see a day").font(.caption).foregroundStyle(Theme.muted)
                }
                if !spikes.isEmpty {
                    Text("\(spikes.count) unusually high day\(spikes.count > 1 ? "s" : "") marked in red").font(.caption).foregroundStyle(Theme.red)
                }
            }
        }
    }

    // E. Summary
    private var summaryCard: some View {
        let d = store.data
        let (f, t) = range
        let (pf, pt) = previous
        let s = Finance.summary(d, f, t)
        let ps = Finance.summary(d, pf, pt)
        let top = Finance.breakdown(d, f, t).first
        let past = Finance.monthly(d, months: 6, end: YM.now().plus(-1)).filter { $0.expense > 0 || $0.income > 0 }
        let ch = Finance.percentChange(s.expense, ps.expense)
        return Card {
            Text("Financial summary · this \(span.rawValue.lowercased())").font(.headline)
            LabelValue(label: "Total income", value: Money.format(s.income), color: Theme.mint)
            LabelValue(label: "Total expenses", value: Money.format(s.expense), color: Theme.red)
            LabelValue(label: "Net cash flow", value: Money.format(s.net, plus: true), color: s.net >= 0 ? Theme.mint : Theme.red)
            LabelValue(label: "Savings", value: Money.format(s.savings))
            LabelValue(label: "Savings rate", value: s.savingsRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "No income yet")
            LabelValue(label: "Highest category", value: top.map { "\($0.category?.name ?? "Uncategorised") · \(Money.format($0.amount))" } ?? "–")
            LabelValue(label: "Spending vs previous \(span.rawValue.lowercased())",
                       value: ch.map { "\($0 >= 0 ? "+" : "−")\(Int((abs($0) * 100).rounded()))%" } ?? "–",
                       color: (ch ?? 0) > 0 ? Theme.red : Theme.mint)
            LabelValue(label: "Monthly average spending",
                       value: past.isEmpty ? "Needs a full month" : "\(Money.format(past.reduce(0) { $0 + $1.expense } / past.count)) (\(past.count) mo)")
        }
    }
}

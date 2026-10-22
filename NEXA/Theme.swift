import SwiftUI

extension Color {
    init(hex: Int) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Modern Dark Premium palette.
enum Theme {
    static let bg = Color(hex: 0x090B10)
    static let card = Color(hex: 0x151A24)
    static let cardHigh = Color(hex: 0x1C2230)
    static let border = Color(hex: 0x242B3A)
    static let mint = Color(hex: 0x58E0B0)
    static let red = Color(hex: 0xFF7785)
    static let amber = Color(hex: 0xE9BE73)
    static let blue = Color(hex: 0x7AA7FF)
    static let text = Color(hex: 0xE8ECF4)
    static let muted = Color(hex: 0x8A93A6)
    static let faint = Color(hex: 0x5A6275)

    static func level(_ l: BudgetLevel) -> Color {
        switch l { case .ok: return mint; case .warn: return amber; case .over: return red }
    }
    static func status(_ s: BillStatus) -> Color {
        switch s {
        case .paid: return mint
        case .overdue: return red
        case .dueSoon: return amber
        case .autoDebit: return blue
        case .upcoming: return muted
        }
    }
}

/// Small shared text helpers.
enum UI {
    static func symbol(_ key: String?) -> String {
        switch key {
        case "restaurant": return "fork.knife"
        case "cart": return "cart.fill"
        case "car": return "car.fill"
        case "bolt": return "bolt.fill"
        case "home": return "house.fill"
        case "bank": return "building.columns.fill"
        case "shield": return "shield.fill"
        case "health": return "cross.case.fill"
        case "bag": return "bag.fill"
        case "movie": return "film.fill"
        case "repeat": return "repeat"
        case "family": return "figure.2.and.child.holdinghands"
        case "flight": return "airplane"
        case "work": return "briefcase.fill"
        case "savings": return "banknote.fill"
        case "wallet": return "wallet.pass.fill"
        case "clock": return "clock.fill"
        case "laptop": return "laptopcomputer"
        case "store": return "storefront.fill"
        case "star": return "star.fill"
        case "receipt": return "doc.text.fill"
        case "transfer": return "arrow.left.arrow.right"
        case "adjust": return "slider.horizontal.3"
        default: return "ellipsis"
        }
    }

    static let iconKeys = ["restaurant", "cart", "car", "bolt", "home", "bank", "shield", "health", "bag", "movie", "repeat",
                           "family", "flight", "work", "savings", "wallet", "clock", "laptop", "store", "star", "receipt", "more"]
    static let colors = [0xFF58E0B0, 0xFF7FDBCA, 0xFF6EA8FE, 0xFF82AAFF, 0xFFB59CFF, 0xFFC792EA, 0xFFFF8FB1,
                         0xFFFF7785, 0xFFF78C6C, 0xFFFF9F6E, 0xFFFFC857, 0xFFE9BE73, 0xFF8BD17C, 0xFFA3B1C6]

    static func color(_ c: Category?) -> Color { c.map { Color(hex: $0.color) } ?? Theme.muted }

    static func title(_ d: AppData, _ t: Transaction) -> String {
        if !t.merchant.isEmpty { return t.merchant }
        if t.type == .TRANSFER { return "Transfer" }
        return d.category(t.categoryId)?.name ?? "Uncategorised"
    }

    static func subtitle(_ d: AppData, _ t: Transaction) -> String {
        switch t.type {
        case .TRANSFER: return "\(d.account(t.accountId)?.name ?? "?") → \(d.account(t.toAccountId)?.name ?? "?")"
        case .ADJUSTMENT: return "Reconciliation · \(d.account(t.accountId)?.name ?? "")"
        default: return [d.category(t.categoryId)?.name ?? "Uncategorised", d.account(t.accountId)?.name].compactMap { $0 }.joined(separator: " · ")
        }
    }

    static func signed(_ t: Transaction) -> String {
        switch t.type {
        case .INCOME, .ADJUSTMENT: return Money.format(t.amount, plus: true)
        case .EXPENSE: return Money.format(-t.amount)
        case .TRANSFER: return Money.format(t.amount)
        }
    }

    static func amountColor(_ t: Transaction) -> Color {
        switch t.type {
        case .INCOME: return Theme.mint
        case .EXPENSE: return Theme.text
        case .TRANSFER: return Theme.blue
        case .ADJUSTMENT: return Theme.muted
        }
    }

    static func billLabel(_ b: BillInstance) -> String {
        guard b.recurring.kind == .INCOME else { return b.isPaid ? "Paid" : b.status.rawValue }
        if b.isPaid { return "Received" }
        return b.status == .overdue ? "Late" : "Expected"
    }
}

// MARK: - Components

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

struct Chip: View {
    let text: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(selected ? Theme.mint : Theme.muted)
                .background(selected ? Theme.mint.opacity(0.15) : Theme.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? Theme.mint.opacity(0.4) : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ChipRow<T: Hashable>: View {
    let options: [T]
    @Binding var selected: T
    let label: (T) -> String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { o in Chip(text: label(o), selected: o == selected) { selected = o } }
            }
        }
    }
}

struct ProgressBar: View {
    let ratio: Double
    let color: Color
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule().fill(color).frame(width: g.size.width * min(max(ratio, 0), 1))
            }
        }
        .frame(height: height)
    }
}

struct CategoryBadge: View {
    let category: Category?
    var type: TxType? = nil
    var size: CGFloat = 40
    var body: some View {
        let color: Color = type == .TRANSFER ? Theme.blue : (type == .ADJUSTMENT ? Theme.muted : UI.color(category))
        let icon = type == .TRANSFER ? "transfer" : (type == .ADJUSTMENT ? "adjust" : category?.icon)
        Image(systemName: UI.symbol(icon))
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.16))
            .clipShape(Circle())
    }
}

struct Tag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.14)).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct SectionTitle: View {
    let text: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(text).font(.headline)
            Spacer()
            if let action, let onAction { Button(action, action: onAction).font(.subheadline.weight(.medium)).foregroundStyle(Theme.mint) }
        }
        .padding(.top, 6)
    }
}

struct LabelValue: View {
    let label: String
    let value: String
    var color: Color = Theme.text
    var body: some View {
        HStack {
            Text(label).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).foregroundStyle(color).fontWeight(.medium)
        }
        .font(.subheadline)
        .padding(.vertical, 3)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct MonthSwitcher: View {
    @Binding var month: YM
    var body: some View {
        HStack(spacing: 2) {
            Button { month = month.plus(-1) } label: { Image(systemName: "chevron.left").frame(width: 30, height: 30) }
            Button { month = .now() } label: { Text(D.monthYearF.string(from: month.first)).font(.subheadline.weight(.medium)) }
            Button { month = month.plus(1) } label: { Image(systemName: "chevron.right").frame(width: 30, height: 30) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 4)
        .background(Theme.card)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }
}

struct TxRow: View {
    let data: AppData
    let t: Transaction
    var showDate = false
    var duplicate = false
    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(category: data.category(t.categoryId), type: t.type)
            VStack(alignment: .leading, spacing: 2) {
                Text(UI.title(data, t)).lineLimit(1)
                Text(sub).font(.caption).foregroundStyle(duplicate ? Theme.amber : Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(UI.signed(t)).foregroundStyle(UI.amountColor(t)).fontWeight(.medium)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    private var sub: String {
        var parts = [UI.subtitle(data, t)]
        if showDate { parts.append(D.dayShortF.string(from: t.at)) }
        if t.recurringId != nil { parts.append("Bill payment") }
        if duplicate { parts.append("Possible duplicate") }
        return parts.joined(separator: " · ")
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(Theme.bg)
            .background(Theme.mint.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var color: Color = Theme.text
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(color)
            .background(configuration.isPressed ? Theme.cardHigh : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

/// Dark rounded text field.
struct Field: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var number = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.muted)
            TextField(placeholder, text: $text)
                .keyboardType(number ? .decimalPad : .default)
                .padding(12)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
        }
    }
}

/// A row that opens a menu of options.
struct PickerRow<T: Hashable>: View {
    let label: String
    let value: String
    let options: [T]
    let display: (T) -> String
    let onSelect: (T) -> Void
    var body: some View {
        Menu {
            ForEach(options, id: \.self) { o in Button(display(o)) { onSelect(o) } }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.caption).foregroundStyle(Theme.muted)
                    Text(value).foregroundStyle(Theme.text)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").foregroundStyle(Theme.muted)
            }
            .padding(12)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
        }
    }
}

/// UIKit share sheet: Save to Files, AirDrop, WhatsApp, Google Drive…
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ShareItem: Identifiable { let id = UUID(); let url: URL }

extension View {
    func nexaBackground() -> some View {
        self.scrollContentBackground(.hidden).background(Theme.bg.ignoresSafeArea())
    }
}

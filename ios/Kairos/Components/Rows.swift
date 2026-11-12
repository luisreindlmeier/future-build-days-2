import SwiftUI

/// 1 pt divider in the divider color.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color.divider).frame(height: 1)
    }
}

/// Section title: 18 semibold, or Marcellus SC for the pages that carry a score.
struct SectionHeader: View {
    let title: LocalizedStringKey
    var trailing: Text?
    var display = false

    init(_ title: LocalizedStringKey, trailing: Text? = nil, display: Bool = false) {
        self.title = title
        self.trailing = trailing
        self.display = display
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if display {
                Text(title).font(.display(22, relativeTo: .title2)).foregroundStyle(Color.ink)
            } else {
                Text(title).appFont(18, .semibold, relativeTo: .headline).foregroundStyle(Color.ink)
            }
            Spacer(minLength: 12)
            if let trailing {
                trailing.appFont(14, relativeTo: .subheadline).foregroundStyle(Color.textMuted)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Plain row: title 17 medium, optional subtitle 14 muted, trailing accessory.
struct Row<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(17, .medium)
                    .foregroundStyle(Color.ink)
                if let subtitle {
                    Text(subtitle)
                        .appFont(14, relativeTo: .subheadline)
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, Spacing.rowVertical)
        .contentShape(Rectangle())
    }
}

extension Row where Leading == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, leading: { EmptyView() }, trailing: trailing)
    }
}

extension Row where Leading == EmptyView, Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

struct Chevron: View {
    var body: some View {
        Icon("chevron-right", size: 18)
            .environment(\.inkColor, .textMuted)
    }
}

/// Rows separated by hairlines, none after the last.
struct RowList<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let data: Data
    @ViewBuilder var content: (Data.Element) -> Content

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                content(element)
                if index < data.count - 1 { Hairline() }
            }
        }
    }
}

extension View {
    /// The white tile with `tileShadow`.
    func tile(padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.heroBlock, style: .continuous))
            .tileShadow()
    }

    /// The coach's card: a tint of the navy instead of white, without a shadow.
    func tintTile(padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color(hex: 0xE1E7FA), Color(hex: 0xEDF0FC)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: Radius.heroBlock, style: .continuous)
            )
    }
}

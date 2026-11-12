import Charts
import SwiftUI

/// What the prediction agent says about the customer's future, with the simulated range as a chart.
struct PredictionView: View {
    @Environment(AppModel.self) private var model
    @State private var scenario = "full_plan"

    private struct Point: Identifiable {
        let series: String
        let age: Int
        let low: Double
        let middle: Double
        let high: Double

        var id: String { "\(series)\(age)" }
    }

    var body: some View {
        ScrollView {
            if let workspace = model.workspace, let forecast = workspace.forecast {
                VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                    Text(forecast.headline ?? "")
                        .appFont(20, .semibold, relativeTo: .title3, lineHeight: 1.3)
                        .foregroundStyle(Color.ink)
                        .padding(.top, 8)
                    if let chart = workspace.prediction.chart {
                        chartTile(chart, workspace: workspace)
                    }
                    if let text = forecast.ifNothingChanges {
                        section("If nothing changes", text)
                    }
                    if let lines = forecast.whatItMeans, !lines.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader("What it means for you")
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .appFont(15, relativeTo: .subheadline, lineHeight: 1.4)
                                    .foregroundStyle(Color.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 10)
                                if index < lines.count - 1 { Hairline() }
                            }
                        }
                    }
                    if let best = forecast.bestChange, let why = best.why {
                        section("The change that helps most", why + (best.firstStep.map { " First step: \($0)" } ?? ""))
                    }
                    if let watch = forecast.watchOut?.sentence {
                        HStack(alignment: .top, spacing: 12) {
                            Icon("cloud-lightning", size: 22)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Watch out").appFont(16, .semibold, relativeTo: .callout).foregroundStyle(Color.ink)
                                Text(watch).appFont(15, relativeTo: .subheadline, lineHeight: 1.4).foregroundStyle(Color.textSecondary)
                            }
                        }
                        .tile()
                    }
                    if let tradeOff = forecast.tradeOff {
                        section("The trade-off", tradeOff)
                    }
                    if let disclaimer = forecast.disclaimer {
                        Text(disclaimer)
                            .appFont(13, relativeTo: .footnote)
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .padding(.horizontal, Spacing.screenSide)
                .padding(.bottom, 32)
            }
        }
        .screenBackground()
        .navigationTitle("Your outlook")
        .toolbarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: scenario)
    }

    private func section(_ title: LocalizedStringKey, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
            Text(text)
                .appFont(15, relativeTo: .subheadline, lineHeight: 1.4)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func label(_ id: String, _ workspace: Workspace) -> String {
        if id == "full_plan" { return "Do all of the above" }
        return workspace.prediction.engine?.scenarios.first { $0.id == id }?.label ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func chartTile(_ chart: ForecastChart, workspace: Workspace) -> some View {
        let options = chart.byScenario.keys.filter { $0 != "baseline" }.sorted { $0 == "full_plan" || ($1 != "full_plan" && $0 < $1) }
        let chosen = chart.byScenario[scenario] ?? chart.fullPlan
        let points = band("Same habits", chart.todayPath, chart) + band("With the change", chosen, chart)
        return VStack(alignment: .leading, spacing: 14) {
            Menu {
                Picker("Change", selection: $scenario) {
                    ForEach(options, id: \.self) { Text(label($0, workspace)).tag($0) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(label(scenario, workspace))
                        .appFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                    Icon("chevrons-up-down", size: 14)
                }
            }
            Chart(points) { point in
                AreaMark(x: .value("Age", point.age), yStart: .value("Weaker tenth", point.low), yEnd: .value("Better tenth", point.high))
                    .foregroundStyle(by: .value("Path", point.series))
                    .opacity(0.16)
                LineMark(x: .value("Age", point.age), y: .value("Middle", point.middle))
                    .foregroundStyle(by: .value("Path", point.series))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            .chartForegroundStyleScale(["Same habits": Color.textMuted, "With the change": Color.accent])
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.divider)
                    AxisValueLabel { if let amount = value.as(Double.self) { Text(Format.short(amount)) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 5)) { value in
                    AxisValueLabel { if let age = value.as(Int.self) { Text("\(age)") } }
                }
            }
            .chartXScale(domain: chart.startAge...(chart.startAge + chart.years))
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 220)
            Text("Wealth by age. The line is the middle of \((workspace.prediction.engine?.paths ?? 2000).formatted(.number.locale(Locale(identifier: "en_GB")))) simulated futures, the band runs from the weaker tenth to the better tenth.")
                .appFont(13, relativeTo: .footnote, lineHeight: 1.35)
                .foregroundStyle(Color.textMuted)
        }
        .tile()
    }

    private func band(_ series: String, _ band: ForecastChart.Band, _ chart: ForecastChart) -> [Point] {
        band.p50.indices.map { index in
            Point(series: series, age: chart.startAge + index, low: band.p10[safe: index] ?? band.p50[index], middle: band.p50[index], high: band.p90[safe: index] ?? band.p50[index])
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

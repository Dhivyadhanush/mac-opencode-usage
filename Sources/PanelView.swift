import SwiftUI

private func usageColor(_ pct: Double?, warning: Double, critical: Double) -> Color {
    guard let pct else { return .secondary }
    // Two independent steppers: if they are set the wrong way round the yellow
    // state would never appear, so treat critical as the higher of the two.
    if pct >= max(critical, warning) { return .red }
    if pct >= warning { return .yellow }
    return .primary
}

private let clock: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
}()

struct PanelView: View {
    @ObservedObject var store: Store
    @State private var showSettings = false
    @State private var showAllModels = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if showSettings { SettingsView(store: store) }
                content
            }
            .padding(16)
        }
        .frame(width: 440, height: 660)
        .onAppear { store.refreshIfStale() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("OpenCode usage").font(.system(size: 16, weight: .bold))
                Text(store.data?.meters?.workspace.map { "\($0) · Go plan" } ?? "Go plan")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.busy)
            .help("Refresh usage")

            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let data = store.data {
            HStack(spacing: 10) {
                summaryCard(data.meters == nil ? "Last 5h" : "5-hour", Usage.top(data, .five))
                summaryCard("Weekly", Usage.top(data, .week))
                summaryCard("Monthly", Usage.top(data, .month))
            }

            if let error = store.error {
                banner("Refresh failed; showing previous data.", detail: error)
            }

            // A model newer than the table, or a Go Plus/Teams account, would
            // otherwise look like a broken app: every percentage is a dash.
            if data.models.contains(where: { $0.month > 0 }) && Usage.top(data, .month) == nil {
                banner("No spend limits for these models.",
                       detail: "Only the Go plan table is built in, so this model has no percentage. Spend and requests still update.")
            }

            Divider()
            Text("Models this month").font(.system(size: 12, weight: .semibold))

            if data.models.isEmpty {
                Text("No OpenCode Go usage in this period.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(data.models) { model in
                    modelCard(model)
                }
            }

            allModels(data)

            Divider()
            details(data)
        } else if let error = store.error {
            banner("Could not load usage", detail: error)
        } else {
            Text("Loading usage…").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private func summaryCard(_ label: String, _ top: Usage.Top?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Text(top.map { Usage.percent($0.pct) } ?? "—")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(usageColor(top?.pct, warning: store.warning, critical: store.critical))
            Text(summaryNote(top) ?? "no usage yet")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
    }

    private func summaryNote(_ top: Usage.Top?) -> String? {
        guard let top else { return nil }
        if store.data?.meters != nil { return "\(Usage.money(top.value)) · \(top.model.id)" }
        return "\(Usage.money(top.value)) / \(Usage.money(top.cap)) · \(top.model.id)"
    }

    private func modelCard(_ model: ModelUsage) -> some View {
        let monthCap = Usage.cap(model, .month)
        let monthPct = monthCap.map { model.month / $0 }

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(model.id).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(model.limit.map { "limit " + Usage.money($0) } ?? "no limit data")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                miniStat(store.data?.meters == nil ? "Last 5h" : "5-hour", model, .five)
                miniStat("Week", model, .week)
                miniStat("Month", model, .month)
            }

            if let monthPct, store.data?.meters == nil {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.12))
                        Capsule()
                            .fill(usageColor(monthPct, warning: store.warning, critical: store.critical))
                            .frame(width: geometry.size.width * min(monthPct, 1))
                    }
                }
                .frame(height: 4)
            }

            Text("\(model.requests) req this month · \(Usage.compact(model.input)) in · "
                + "\(Usage.compact(model.output)) out · \(Usage.compact(model.cacheRead)) cache")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.04)))
    }

    private func miniStat(_ label: String, _ model: ModelUsage, _ period: Period) -> some View {
        let value = model.value(period)
        let cap = Usage.cap(model, period)
        let pct = cap.map { value / $0 }
        // The console meter only knows account totals, so per-model cards show spend
        // rather than a percentage that would not add up to it.
        let metered = store.data?.meters != nil

        return VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(metered ? Usage.money(value) : (pct.map(Usage.percent) ?? "—"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(metered ? .primary : usageColor(pct, warning: store.warning, critical: store.critical))
            Text(metered ? "spent" : (cap.map { "\(Usage.money(value)) / \(Usage.money($0))" } ?? "\(Usage.money(value)) · no limit data"))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func details(_ data: UsageData) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Details").font(.system(size: 12, weight: .semibold))
            detailRow("Today", Usage.money(data.today))
            detailRow("Month requests", String(data.monthRequests))
            detailRow(
                "Month tokens",
                "\(Usage.compact(data.input)) in · \(Usage.compact(data.output)) out · "
                    + "\(Usage.compact(data.cacheRead)) cache"
            )
            if let meter = data.meters?.five {
                detailRow("5h resets", reset(meter))
                // In metered mode every other time above is a future reset, so
                // without this row stale data would look fresh.
                detailRow("Updated", clock.string(from: data.updatedAt) + " " + Usage.offset)
                detailRow("Source", "console meter")
            } else {
                // No console workspace linked: these are the edges of a rolling
                // sum, not a reset time.
                detailRow("5h starts", clock.string(from: data.fiveSinceAt) + " " + Usage.offset)
                detailRow("5h ends", clock.string(from: data.updatedAt) + " " + Usage.offset)
                detailRow("Source", "console usage API")
            }
        }
    }

    private func reset(_ meter: Meters.Meter) -> String {
        guard let at = meter.resetsAt else { return "unknown" }
        return clock.string(from: at) + " " + Usage.offset
    }

    // Every model in the Go table, including ones with no spend this month —
    // otherwise a model you have never touched is invisible. A plain button
    // rather than DisclosureGroup: that one never took clicks in a
    // MenuBarExtra window.
    @ViewBuilder
    private func allModels(_ data: UsageData) -> some View {
        let names = Limits.models()
        Button {
            showAllModels.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: showAllModels ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                Text("All \(names.count) models")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)

        if showAllModels {
            VStack(spacing: 3) {
                ForEach(names, id: \.self) { name in
                    let model = data.models.first { $0.id == name }
                    let limit = Limits.value(model: name)
                    HStack(spacing: 6) {
                        Text(name).font(.system(size: 10))
                        Spacer()
                        if let model, model.month > 0 {
                            Text(Usage.money(model.month)).font(.system(size: 10, weight: .medium))
                            Text("/ \(Usage.money(limit ?? 0))").font(.system(size: 10)).foregroundStyle(.secondary)
                        } else {
                            Text("no usage").font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .medium))
        }
    }

    private func banner(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(.red)
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.red.opacity(0.12)))
    }
}

struct SettingsView: View {
    let store: Store

    @AppStorage("refreshMinutes") private var refreshMinutes = 10
    @AppStorage("warning") private var warning = 80
    @AppStorage("critical") private var critical = 95
    @AppStorage("barFive") private var barFive = true
    @AppStorage("barWeek") private var barWeek = true
    @AppStorage("barMonth") private var barMonth = true
    @State private var loginError: String?
    @State private var launchAtLogin = LoginItem.enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings").font(.system(size: 12, weight: .semibold))

            HStack {
                Text("Refresh")
                Spacer()
                Stepper("\(refreshMinutes) min", value: $refreshMinutes, in: 1...120)
                    .fixedSize()
            }


            HStack(spacing: 12) {
                Text("Warn / critical")
                Spacer()
                Stepper("\(warning)%", value: $warning, in: 1...100).fixedSize()
                Stepper("\(critical)%", value: $critical, in: 1...100).fixedSize()
            }

            HStack(spacing: 12) {
                Text("Menu bar")
                Spacer()
                Toggle("H", isOn: $barFive).toggleStyle(.checkbox)
                Toggle("W", isOn: $barWeek).toggleStyle(.checkbox)
                Toggle("M", isOn: $barMonth).toggleStyle(.checkbox)
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        try LoginItem.set(on)
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                    }
                    // The file is the source of truth; re-read it so a failed
                    // write cannot leave the switch lying.
                    launchAtLogin = LoginItem.enabled
                }

            if let loginError {
                Text(loginError).font(.system(size: 10)).foregroundStyle(.red)
            }

            // Menu bar apps have no other way out without Activity Monitor.
            HStack {
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .padding(.top, 2)
        }
        .font(.system(size: 11))
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .onChange(of: refreshMinutes) { _, _ in store.settingsChanged() }
    }
}

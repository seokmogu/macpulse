import AppKit
import Charts
import SwiftUI
import ServiceManagement

enum PulseStyle {
    static let cpu = Color(red: 0.43, green: 0.88, blue: 0.27)
    static let memory = Color(red: 0.29, green: 0.54, blue: 1)
    static let upload = Color(red: 0.65, green: 0.40, blue: 0.97)
    static let panel = Color(red: 0.12, green: 0.14, blue: 0.17)
    static let muted = Color(red: 0.69, green: 0.73, blue: 0.79)
    static let separator = Color.white.opacity(0.11)
}

struct PanelView: View {
    @ObservedObject var model: MonitorModel
    let openActivityMonitor: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.settingsVisible { settings } else { metrics }
        }
        .frame(width: 420)
        .foregroundStyle(.white)
        .background(PulseStyle.panel)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.settingsVisible ? "MacPulse 설정" : "Mac 리소스")
                    .font(.system(size: 20, weight: .semibold))
                Text(model.settingsVisible ? "나에게 맞는 모니터링" : "최근 60초")
                    .font(.system(size: 12)).foregroundStyle(PulseStyle.muted)
            }
            Spacer()
            Button { model.settingsVisible.toggle() } label: {
                Image(systemName: model.settingsVisible ? "xmark" : "gearshape")
                    .font(.system(size: 17)).foregroundStyle(PulseStyle.muted)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(model.settingsVisible ? "모니터로 돌아가기" : "설정")
            .accessibilityLabel(model.settingsVisible ? "설정 닫기" : "설정 열기")
        }
        .padding(16)
        .overlay(alignment: .bottom) { divider }
    }

    private var metrics: some View {
        VStack(spacing: 0) {
            chartSection(title: "CPU", percent: model.snapshot?.cpuPercent, subtitle: nil, color: PulseStyle.cpu, cpu: true)
            divider
            chartSection(title: "메모리", percent: model.memoryPercent,
                         subtitle: memoryDescription, color: PulseStyle.memory, cpu: false)
                .help("사용 중 메모리: 앱·유선·압축 메모리의 추정 합계. 파일 캐시는 제외합니다.")
            divider
            HStack(spacing: 0) {
                transfer(symbol: "arrow.down", value: model.snapshot?.networkDownloadBytesPerSecond, color: PulseStyle.memory, label: "다운로드")
                Rectangle().fill(PulseStyle.separator).frame(width: 1, height: 22)
                transfer(symbol: "arrow.up", value: model.snapshot?.networkUploadBytesPerSecond, color: PulseStyle.upload, label: "업로드")
            }
            .padding(.vertical, 14)
            .help("기본 네트워크 인터페이스: \(model.snapshot?.interfaceName ?? "연결 확인 중")")
            divider
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true))
            } label: {
                detailRow(symbol: "internaldrive", title: "저장 공간", value: diskDescription)
            }.buttonStyle(.plain).help("Finder에서 저장 장치 열기")
            divider.padding(.horizontal, 20)
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") { NSWorkspace.shared.open(url) }
            } label: {
                detailRow(symbol: "battery.75percent", title: "배터리", value: batteryDescription)
            }.buttonStyle(.plain).help("배터리 설정 열기")
            if let errors = model.snapshot?.errors, !errors.isEmpty {
                Text("일부 정보를 읽지 못했습니다")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .help(errors.joined(separator: "\n")).padding(.bottom, 8)
            }
            divider
            Button(action: openActivityMonitor) {
                Text("활성 상태 보기").font(.system(size: 12))
                    .foregroundStyle(PulseStyle.muted).frame(maxWidth: .infinity).padding(.vertical, 12)
            }.buttonStyle(.plain)
        }
    }

    private func chartSection(title: String, percent: Double?, subtitle: String?, color: Color, cpu: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 18, weight: .semibold))
                Spacer()
                Text(MonitorModel.percent(percent)).font(.system(size: 25, weight: .semibold)).monospacedDigit()
            }
            if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(PulseStyle.muted) }
            HistoryChart(points: model.history, cpu: cpu, color: color)
                .frame(height: 94)
                .accessibilityLabel("\(title) 최근 60초 사용량, 현재 \(MonitorModel.percent(percent))")
            HStack {
                Text("60초 전")
                Spacer()
                Text("지금")
            }.font(.system(size: 10)).foregroundStyle(PulseStyle.muted).padding(.leading, 31)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func transfer(symbol: String, value: Double?, color: Color, label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 21, weight: .medium)).foregroundStyle(color)
            Text(MonitorModel.rate(value)).font(.system(size: 16, weight: .semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label) \(MonitorModel.rate(value))")
    }

    private func detailRow(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18)).frame(width: 23)
            Text(title).font(.system(size: 12))
            Spacer(minLength: 4)
            Text(value).font(.system(size: 12)).monospacedDigit()
            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(PulseStyle.muted)
        }.foregroundStyle(Color.white.opacity(0.84)).padding(.horizontal, 20).padding(.vertical, 12)
            .contentShape(Rectangle())
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 22) {
            Picker("갱신 주기", selection: $model.interval) {
                Text("1초").tag(1.0)
                Text("2초").tag(2.0)
                Text("5초").tag(5.0)
            }.pickerStyle(.segmented)
            Toggle("로그인 시 자동 실행", isOn: Binding(get: { model.loginEnabled }, set: setLogin))
                .toggleStyle(.switch)
            if let loginMessage = model.loginMessage { Text(loginMessage).font(.system(size: 12)).foregroundStyle(.orange) }
            Text("MacPulse는 이 Mac의 시스템 정보만 읽습니다. 측정 데이터는 서버로 전송하거나 파일에 저장하지 않습니다.")
                .font(.system(size: 12)).foregroundStyle(PulseStyle.muted).fixedSize(horizontal: false, vertical: true)
            divider
            HStack {
                Text("MacPulse 1.0.0").font(.system(size: 12)).foregroundStyle(PulseStyle.muted)
                Spacer()
                Link("GitHub", destination: URL(string: "https://github.com/seokmogu/macpulse")!)
            }
            Button("MacPulse 종료") { NSApplication.shared.terminate(nil) }
                .frame(maxWidth: .infinity)
        }.padding(20).frame(height: 290, alignment: .top)
    }

    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            model.loginEnabled = SMAppService.mainApp.status == .enabled
            model.loginMessage = SMAppService.mainApp.status == .requiresApproval ? "시스템 설정 > 일반 > 로그인 항목에서 허용해 주세요." : nil
        } catch {
            model.loginEnabled = SMAppService.mainApp.status == .enabled
            model.loginMessage = "자동 실행 설정을 변경하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private var divider: some View { Rectangle().fill(PulseStyle.separator).frame(height: 1) }
    private var memoryDescription: String {
        guard let s = model.snapshot else { return "측정 중…" }
        guard let used = s.memoryUsedBytes else { return "측정 중…" }
        return String(format: "%.1f / %.0f GB", Double(used) / 1_073_741_824, Double(s.memoryTotalBytes) / 1_073_741_824)
    }
    private var diskDescription: String {
        guard let s = model.snapshot else { return "측정 중…" }
        return "\(MonitorModel.size(s.diskUsedBytes)) / \(MonitorModel.size(s.diskTotalBytes))"
    }
    private var batteryDescription: String {
        guard let s = model.snapshot else { return "측정 중…" }
        if let percent = s.batteryPercent { return "\(MonitorModel.percent(percent)) · \(s.batteryState)" }
        return s.batteryState
    }
}

struct HistoryChart: View {
    let points: [HistoryPoint]
    let cpu: Bool
    let color: Color
    private var end: Date { points.last?.date ?? Date() }
    var body: some View {
        Chart {
            ForEach(points) { point in
                if let value = cpu ? point.cpu : point.memory {
                    AreaMark(x: .value("시간", point.date), yStart: .value("기준", 0), yEnd: .value("사용량", value))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("시간", point.date), y: .value("사용량", value))
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.7))
                }
            }
            if let last = points.last, let value = cpu ? last.cpu : last.memory {
                PointMark(x: .value("시간", last.date), y: .value("사용량", value)).foregroundStyle(color).symbolSize(24)
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: end.addingTimeInterval(-60)...end)
        .chartXAxis {
            AxisMarks(values: .stride(by: .second, count: 10)) { _ in AxisGridLine().foregroundStyle(PulseStyle.separator) }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(PulseStyle.separator)
                AxisValueLabel {
                    if let n = value.as(Int.self) { Text("\(n)%").font(.system(size: 10)).foregroundStyle(PulseStyle.muted) }
                }
            }
        }
        .chartPlotStyle { $0.background(Color.white.opacity(0.015)) }
    }
}

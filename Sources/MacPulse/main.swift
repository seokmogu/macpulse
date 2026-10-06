import AppKit
import SwiftUI
import MacPulseCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let model = MonitorModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: 214)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.setAccessibilityLabel("MacPulse 리소스 모니터")
        popover.behavior = .transient
        popover.animates = false
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model, openActivityMonitor: openActivityMonitor))
        model.onUpdate = { [weak self] in self?.updateStatus() }
        updateStatus()
        model.start()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.popover.isShown == true {
                self?.popover.performClose(nil)
                return nil
            }
            return event
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.model.stop() })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.model.start(reset: true) })
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.showPopover() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover(); return true
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "MacPulse 열기", action: #selector(showPopover), keyEquivalent: "")
            menu.addItem(withTitle: "활성 상태 보기", action: #selector(openActivityMonitor), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "MacPulse 종료", action: #selector(quit), keyEquivalent: "q")
            menu.items.forEach { $0.target = self }
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    @objc func showPopover() {
        guard let button = statusItem?.button else { return }
        model.settingsVisible = false
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        popover.performClose(nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func updateStatus() {
        guard let button = statusItem.button else { return }
        let cpu = MonitorModel.percent(model.snapshot?.cpuPercent)
        let memory = MonitorModel.percent(model.memoryPercent)
        button.toolTip = "MacPulse · CPU \(cpu) · 메모리 \(memory)\n클릭: 상세 보기 · 오른쪽 클릭: 종료"
        button.setAccessibilityValue("CPU \(cpu), 메모리 \(memory)")
        let points = Array(model.history.suffix(30))
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            let result = NSImage(size: NSSize(width: 210, height: 22))
            result.lockFocus()
            func label(_ text: String, x: CGFloat, small: Bool = false) {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: small ? 10 : 11, weight: .medium),
                    .foregroundColor: NSColor.labelColor
                ]
                (text as NSString).draw(at: NSPoint(x: x, y: 4.5), withAttributes: attrs)
            }
            func spark(x: CGFloat, cpu: Bool, color: NSColor) {
                let values = points.map { cpu ? $0.cpu : $0.memory }
                let path = NSBezierPath()
                var continuing = false
                for (index, value) in values.enumerated() {
                    guard let value else { continuing = false; continue }
                    let px = x + CGFloat(index) / CGFloat(max(1, values.count - 1)) * 31
                    let py = 4 + CGFloat(max(0, min(100, value))) / 100 * 14
                    if continuing { path.line(to: NSPoint(x: px, y: py)) } else { path.move(to: NSPoint(x: px, y: py)); continuing = true }
                }
                color.setStroke(); path.lineWidth = 1.3; path.stroke()
            }
            label("CPU", x: 1, small: true)
            spark(x: 27, cpu: true, color: NSColor(red: 0.43, green: 0.88, blue: 0.27, alpha: 1))
            label(cpu, x: 64)
            label("MEM", x: 107, small: true)
            spark(x: 135, cpu: false, color: NSColor(red: 0.29, green: 0.54, blue: 1, alpha: 1))
            label(memory, x: 172)
            result.unlockFocus()
            button.image = result
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
}

if CommandLine.arguments.contains("--diagnose") {
    let sampler = MetricCollector()
    _ = sampler.sample()
    Thread.sleep(forTimeInterval: 1)
    let result = sampler.sample()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(result), let text = String(data: data, encoding: .utf8) { print(text) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

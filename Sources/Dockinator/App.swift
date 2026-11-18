import SwiftUI

// MARK: model

struct Screen: Identifiable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let bounds: CGRect
    let isMain: Bool
}

final class Model: ObservableObject {
    private let locker = Locker()
    private let store = UserDefaults.standard

    @Published var enabled: Bool { didSet { store.set(enabled, forKey: "enabled"); sync() } }
    @Published var edge: Edge { didSet { store.set(edge.rawValue, forKey: "edge"); applyOrientation(); sync() } }
    @Published var homeUUID: String? { didSet { store.set(homeUUID, forKey: "home"); sync() } }
    @Published var allowedUUIDs: Set<String> { didSet { store.set(Array(allowedUUIDs), forKey: "allowed"); sync() } }

    @Published private(set) var screens: [Screen] = []
    @Published private(set) var dockOn: CGDirectDisplayID?
    @Published private(set) var method: Locker.Method = .off
    @Published private(set) var accessibility = false
    @Published private(set) var separateSpaces = true
    @Published private(set) var launchAtLogin = false
    @Published var loginError: String?

    init() {
        enabled = store.object(forKey: "enabled") as? Bool ?? true
        edge = Edge(rawValue: store.string(forKey: "edge") ?? "") ?? dockOrientation()
        homeUUID = store.string(forKey: "home") ?? displayUUID(CGMainDisplayID())
        allowedUUIDs = Set(store.stringArray(forKey: "allowed") ?? [])
        refresh()
        applyOrientation()
        if !accessibility && !store.bool(forKey: "askedAccessibility") {  // first launch only; the panel has a Grant button
            store.set(true, forKey: "askedAccessibility")
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }

        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            refresh()
            applyOrientation()  // undo changes made in System Settings while locked
        }
    }

    var home: Screen? { screens.first { $0.uuid == homeUUID } }

    /// The display the Dock is on, when that display is blocked (after wake, a display change, or a new home).
    var strandedOn: Screen? {
        guard enabled, locksDisplays, let s = screens.first(where: { $0.id == dockOn }), role(of: s) == .blocked else { return nil }
        return s
    }
    var locksDisplays: Bool { edge == .bottom }

    var status: String {
        if !enabled { return "Paused" }
        if !locksDisplays { return "Side Dock stays put on its own" }
        guard let home else { return "Home display not connected" }
        return allowedUUIDs.isEmpty ? "Locked to \(home.name)" : "Home: \(home.name) + \(allowedUUIDs.count) allowed"
    }

    func role(of s: Screen) -> DisplayRole {
        s.uuid == homeUUID ? .home : allowedUUIDs.contains(s.uuid) ? .allowed : .blocked
    }

    func makeHome(_ s: Screen) {
        allowedUUIDs.remove(s.uuid)
        homeUUID = s.uuid
    }

    func toggleAllowed(_ s: Screen) {
        guard s.uuid != homeUUID else { return }
        if allowedUUIDs.contains(s.uuid) { allowedUUIDs.remove(s.uuid) } else { allowedUUIDs.insert(s.uuid) }
    }

    func toggleLaunchAtLogin() {
        do { try Checks.toggleLaunchAtLogin(); loginError = nil } catch { loginError = error.localizedDescription }
        refresh()
    }

    func refresh() {
        screens = activeDisplays().compactMap { d in
            displayUUID(d).map { Screen(id: d, uuid: $0, name: displayName(d), bounds: CGDisplayBounds(d),
                                        isMain: CGDisplayIsMain(d) != 0) }
        }
        accessibility = Checks.accessibility
        separateSpaces = Checks.separateSpaces
        launchAtLogin = Checks.launchAtLogin
        dockOn = dockDisplay()
        sync()
    }

    private func applyOrientation() { if enabled { setDockOrientation(edge) } }

    private func sync() {
        locker.enabled = enabled
        locker.edge = edge
        locker.home = home?.id
        locker.allowed = Set(screens.filter { allowedUUIDs.contains($0.uuid) }.map(\.id))
        locker.updateMethod()
        method = locker.method
    }
}

enum DisplayRole { case home, allowed, blocked }

// MARK: panel

struct PanelView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if model.locksDisplays {
                section("Displays") {
                    DisplayMap()
                        .frame(height: 150)
                        .opacity(model.enabled ? 1 : 0.45)
                    Text("Click a display to make it home. Right-click to allow the Dock there too.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let stranded = model.strandedOn, let home = model.home {
                        Label("The Dock is on \(stranded.name). Push the pointer down on \(home.name) to bring it back.",
                              systemImage: "arrow.down.to.line")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            section("Dock position") {
                Picker("Dock position", selection: $model.edge) {
                    Label("Left", systemImage: "rectangle.leadingthird.inset.filled").tag(Edge.left)
                    Label("Bottom", systemImage: "rectangle.bottomthird.inset.filled").tag(Edge.bottom)
                    Label("Right", systemImage: "rectangle.trailingthird.inset.filled").tag(Edge.right)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            section("Setup") {
                VStack(spacing: 0) {
                    CheckRow(icon: "accessibility", title: "Accessibility",
                             detail: model.accessibility ? "Blocks every pointer move and tracks the Dock"
                                                         : "Recommended. Tighter blocking; locking works without it",
                             ok: model.accessibility) {
                        Button("Grant") { Checks.requestAccessibility() }
                    }
                    Divider().padding(.leading, 40)
                    CheckRow(icon: "rectangle.split.3x1", title: "Separate Spaces per display",
                             detail: model.separateSpaces ? "On" : "Turn on in Desktop & Dock, then log out",
                             ok: model.separateSpaces) {
                        Button("Open") { Checks.openSettings("com.apple.Desktop-Settings.extension") }
                    }
                    Divider().padding(.leading, 40)
                    CheckRow(icon: "power", title: "Start at login",
                             detail: model.loginError ?? (model.launchAtLogin ? "Runs in the background" : "Off"),
                             ok: model.launchAtLogin, optional: true) {
                        Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: { _ in model.toggleLaunchAtLogin() }))
                            .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }
                }
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
            }
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    var header: some View {
        HStack(spacing: 10) {
            AppGlyph(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Dockinator").font(.headline)
                Text(model.status).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("Lock", isOn: $model.enabled).toggleStyle(.switch).labelsHidden()
        }
    }

    var footer: some View {
        HStack {
            Text(methodText).font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless).font(.caption).keyboardShortcut("q")
        }
    }

    var methodText: String {
        switch model.method {
        case .eventTap: "Blocking with event tap"
        case .polling: "Blocking with pointer polling"
        case .off: ""
        }
    }

    func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(0.6)
            content()
        }
    }
}

struct AppGlyph: View {
    var size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.55, blue: 1), Color(red: 0.1, green: 0.3, blue: 0.85)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(Image(systemName: "dock.rectangle").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
            .frame(width: size, height: size)
    }
}

struct CheckRow<Accessory: View>: View {
    let icon: String, title: String, detail: String, ok: Bool
    var optional = false
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15)).frame(width: 22).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title).font(.callout.weight(.medium))
                    if !optional {
                        Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(ok ? .green : .orange)
                    }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if optional || !ok { accessory().controlSize(.small) }
        }
        .padding(.vertical, 8)
    }
}

// MARK: display map

struct DisplayMap: View {
    @EnvironmentObject var model: Model

    var body: some View {
        GeometryReader { geo in
            let union = model.screens.map(\.bounds).reduce(CGRect.null) { $0.union($1) }
            let scale = union.isNull ? 1 : min(geo.size.width / union.width, geo.size.height / union.height) * 0.94
            let offset = CGPoint(x: (geo.size.width - union.width * scale) / 2 - union.minX * scale,
                                 y: (geo.size.height - union.height * scale) / 2 - union.minY * scale)
            ZStack(alignment: .topLeading) {
                ForEach(model.screens) { s in
                    let r = s.bounds
                    DisplayTile(screen: s, role: model.role(of: s), hasDock: s.id == (model.dockOn ?? model.home?.id))
                        .frame(width: r.width * scale - 3, height: r.height * scale - 3)
                        .offset(x: r.minX * scale + offset.x, y: r.minY * scale + offset.y)
                        .onTapGesture { model.makeHome(s) }
                        .contextMenu {
                            Button("Make Home") { model.makeHome(s) }
                            if model.role(of: s) != .home {
                                Button(model.role(of: s) == .allowed ? "Block Dock Here" : "Also Allow Dock Here") {
                                    model.toggleAllowed(s)
                                }
                            }
                        }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.homeUUID)
        .animation(.easeOut(duration: 0.2), value: model.allowedUUIDs)
    }
}

struct DisplayTile: View {
    let screen: Screen
    let role: DisplayRole
    let hasDock: Bool
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack {
            shape.fill(fill)
            shape.strokeBorder(stroke, lineWidth: role == .blocked ? 1 : 1.5)
            VStack(spacing: 2) {
                if role == .home {
                    Image(systemName: "house.fill").font(.system(size: 9))
                }
                Text(screen.name).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(role == .home ? Color.white : role == .allowed ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                if screen.isMain {  // menu bar
                    Rectangle().fill(.primary.opacity(role == .home ? 0 : 0.12)).frame(height: 3)
                        .overlay(Rectangle().fill(.white.opacity(role == .home ? 0.35 : 0)))
                }
                Spacer()
                if hasDock {
                    Capsule().fill(role == .home ? Color.white.opacity(0.9) : Color.orange)
                        .frame(width: 34, height: 4).padding(.bottom, 4)
                }
            }
            .clipShape(shape)
        }
        .brightness(hovering ? 0.06 : 0)
        .onHover { hovering = $0 }
        .help(help)
    }

    var fill: Color {
        switch role {
        case .home: .accentColor
        case .allowed: .accentColor.opacity(0.14)
        case .blocked: .gray.opacity(0.12)
        }
    }

    var stroke: Color {
        switch role {
        case .home: .accentColor
        case .allowed: .accentColor.opacity(0.8)
        case .blocked: .gray.opacity(0.3)
        }
    }

    var help: String {
        switch role {
        case .home: "\(screen.name): home. The Dock returns here."
        case .allowed: "\(screen.name): the Dock may move here."
        case .blocked: "\(screen.name): the Dock can't move here."
        }
    }
}

// MARK: app

@main
struct DockinatorApp: App {
    @StateObject private var model = Model()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        // `Dockinator --snapshot out.png [dark]` renders the panel for the README.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let view = PanelView().environmentObject(Model())
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, args.contains("dark") ? .dark : .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: args[i + 1]))
            }
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(model)
        } label: {
            Image(systemName: model.enabled ? "dock.rectangle" : "dock.arrow.down.rectangle")
        }
        .menuBarExtraStyle(.window)
    }
}

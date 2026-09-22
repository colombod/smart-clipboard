import SwiftUI

private typealias AboutState<Value> = SwiftUI.State<Value>

struct AboutView: View {
    var bundle: Bundle = .main
    @AboutState private var showsNotices = false

    private let project = URL(string: "https://github.com/colombod/smart-clipboard")!
    private var versionLabel: String {
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return "Development build"
        }
        if let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            return "Version \(version) · Build \(build)"
        }
        return "Version \(version)"
    }
    private var icon: NSImage? {
        bundle.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
    }
    private var notices: String? {
        guard let url = bundle.url(forResource: "ThirdPartyNotices", withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    var body: some View {
      ScrollView {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Group {
                    if let icon { Image(nsImage: icon).resizable() }
                    else { Image(systemName: "viewfinder").resizable().foregroundStyle(accent) }
                }
                .scaledToFit().frame(width: 72, height: 72).accessibilityHidden(true)
                Text("Smart Clipboard").font(.system(size: 25, weight: .semibold))
                Text(versionLabel).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            VStack(spacing: 6) {
                Text("Capture once. Use it anywhere.").font(.headline)
                Text("Capture a region or window, keep the image or turn it into editable content, then paste into your app.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.multilineTextAlignment(.center).frame(maxWidth: 430)

            Grid(horizontalSpacing: 22, verticalSpacing: 12) {
                GridRow {
                    Link(destination: project.appendingPathComponent("blob/main/README.md")) {
                        Label("Help & README", systemImage: "questionmark.circle")
                    }
                    Link(destination: project.appendingPathComponent("releases")) {
                        Label("Releases", systemImage: "arrow.down.circle")
                    }
                }
                GridRow {
                    Link(destination: project) { Label("Project on GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                    Link(destination: project.appendingPathComponent("issues/new")) {
                        Label("Report a Problem", systemImage: "bubble.left")
                    }
                }
            }.padding(.vertical, 4)

            if let notices {
                Button("Third-party notices") { showsNotices = true }
                    .tint(.primary)
                    .sheet(isPresented: $showsNotices) { ThirdPartyNoticesView(text: notices) }
            } else {
                Text("Third-party notices are unavailable in this build.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Smart Clipboard stays in your menu bar when you close its windows.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(28).frame(maxWidth: .infinity)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(accent)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ThirdPartyNoticesView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Third-party notices").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.tint(.primary).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                Text(text).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24).frame(width: 580, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

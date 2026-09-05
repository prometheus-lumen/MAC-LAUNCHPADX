import AppKit
import CoreServices
import Foundation
import Observation

protocol ApplicationDiscovering: Sendable {
    func scan(roots: [URL]) async -> [InstalledApplication]
}

struct ApplicationDiscoveryService: ApplicationDiscovering {
    static var defaultRoots: [URL] {
        let manager = FileManager.default
        let paths = [
            "/Applications",
            "/System/Applications",
            "/System/Cryptexes/App/System/Applications",
            NSHomeDirectory() + "/Applications"
        ]
        return paths.map(URL.init(fileURLWithPath:)).filter { manager.fileExists(atPath: $0.path) }
    }

    nonisolated func scan(roots: [URL]) async -> [InstalledApplication] {
        await Task.detached(priority: .background) {
            Self.scanSynchronously(roots: roots)
        }.value
    }

    nonisolated private static func scanSynchronously(roots: [URL]) -> [InstalledApplication] {
        let manager = FileManager.default
        let ownURL = Bundle.main.bundleURL.standardizedFileURL
        var result: [InstalledApplication] = []
        var seenPaths = Set<String>()
        for root in roots {
            guard let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isExecutableKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                let standardized = url.standardizedFileURL
                guard standardized != ownURL,
                      let app = parseApplication(at: standardized, root: root),
                      seenPaths.insert(app.normalizedPath).inserted else { continue }
                result.append(app)
            }
        }
        return result.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    nonisolated private static func parseApplication(at url: URL, root: URL) -> InstalledApplication? {
        guard let bundle = Bundle(url: url),
              let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let localizedInfo = bundle.localizedInfoDictionary ?? [:]
        guard info["LSUIElement"] as? Bool != true,
              info["LSBackgroundOnly"] as? Bool != true else { return nil }
        let name = localizedMetadataName(for: url)
            ?? (localizedInfo["CFBundleDisplayName"] as? String)
            ?? (localizedInfo["CFBundleName"] as? String)
            ?? (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApplication(
            bundleIdentifier: bundle.bundleIdentifier,
            displayName: name,
            bundleURL: url,
            version: info["CFBundleShortVersionString"] as? String,
            isSystemApplication: root.path.hasPrefix("/System")
        )
    }

    nonisolated private static func localizedMetadataName(for url: URL) -> String? {
        guard let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
              let name = MDItemCopyAttribute(item, kMDItemDisplayName) as? String else { return nil }
        let displayName = (name as NSString).deletingPathExtension
        return displayName.isEmpty ? nil : displayName
    }
}

protocol ApplicationLaunching: Sendable {
    func launch(_ application: InstalledApplication) async throws
}

struct ApplicationLauncherService: ApplicationLaunching {
    func launch(_ application: InstalledApplication) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: application.bundleURL, configuration: configuration)
    }
}

protocol IconProviding: Sendable {
    func icon(for application: InstalledApplication) -> NSImage
    func prewarm(_ applications: [InstalledApplication]) async
    func clearCache()
}

final class IconProvider: IconProviding, @unchecked Sendable {
    @Observable
    fileprivate final class Slot {
        var image: NSImage
        var task: Task<Void, Never>?
        let application: InstalledApplication
        init(image: NSImage, application: InstalledApplication) {
            self.image = image
            self.application = application
        }
    }

    private var slots: [String: Slot] = [:]
    private let placeholder = NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    // Serial IO keeps Launch Services from competing with itself during a cold scan.
    private let loader = DispatchQueue(label: "LaunchpadX.icon-loader", qos: .utility)

    private func slot(for application: InstalledApplication) -> Slot {
        let key = application.normalizedPath
        if let slot = slots[key] { return slot }
        let slot = Slot(image: placeholder, application: application)
        slots[key] = slot
        load(application, into: slot)
        return slot
    }

    private func load(_ application: InstalledApplication, into slot: Slot) {
        slot.task = Task { [loader] in
            let image: NSImage = await withCheckedContinuation { continuation in
                loader.async {
                    dispatchPrecondition(condition: .notOnQueue(.main))
                    let image = autoreleasepool {
                        let source = NSWorkspace.shared.icon(forFile: application.bundleURL.path)
                        var rect = CGRect(x: 0, y: 0, width: 256, height: 256)
                        guard let bitmap = source.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
                            return source
                        }
                        return NSImage(cgImage: bitmap, size: rect.size)
                    }
                    continuation.resume(returning: image)
                }
            }
            guard !Task.isCancelled else { return }
            // Publish the loaded image, never perform filesystem IO from a view body.
            slot.image = image
            slot.task = nil
        }
    }

    func icon(for application: InstalledApplication) -> NSImage {
        slot(for: application).image
    }

    func prewarm(_ applications: [InstalledApplication]) async {
        for application in applications {
            guard !Task.isCancelled else { return }
            await slot(for: application).task?.value
        }
    }

    func clearCache() {
        for slot in slots.values {
            slot.task?.cancel()
            load(slot.application, into: slot)
        }
    }
}

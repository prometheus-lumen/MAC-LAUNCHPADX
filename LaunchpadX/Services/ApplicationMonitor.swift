import Foundation
import Darwin

protocol ApplicationMonitoring: AnyObject {
    var onChange: (@Sendable () -> Void)? { get set }
    func start(roots: [URL])
    func stop()
}

@MainActor
final class ApplicationMonitor: ApplicationMonitoring, @unchecked Sendable {
    var onChange: (@Sendable () -> Void)?
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private var debounceWorkItem: DispatchWorkItem?

    func start(roots: [URL]) {
        stop()
        for root in roots {
            let descriptor = open(root.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            fileDescriptors.append(descriptor)
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete],
                queue: .main
            )
            source.setEventHandler { [weak self] in self?.scheduleChange() }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        sources.forEach { $0.cancel() }
        sources.removeAll()
        fileDescriptors.removeAll()
    }

    private func scheduleChange() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onChange?() }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(750), execute: item)
    }
}

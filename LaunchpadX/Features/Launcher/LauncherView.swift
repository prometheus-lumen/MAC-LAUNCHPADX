import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LauncherView: View {
    @Bindable var viewModel: LauncherViewModel
    @Bindable var settings: SettingsStore
    @FocusState private var searchFocused: Bool

    init(viewModel: LauncherViewModel, settings: SettingsStore) {
        self.viewModel = viewModel
        self.settings = settings
    }

    var body: some View {
        ZStack {
            LauncherBackgroundView(settings: settings)
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    handleBackgroundTap()
                }

            launcherCanvas

            if let folder = viewModel.openedFolder {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture { handleBackgroundTap() }
                    .onDrop(
                        of: [UTType.plainText],
                        delegate: FolderOutsideDropDelegate(viewModel: viewModel)
                    )
                FolderOverlayView(viewModel: viewModel, folder: folder)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .background(
            TrackpadGestureMonitor(
                reversesPageDirection: settings.reversePageDirection,
                handleGesture: viewModel.handleTrackpadGesture,
                onOptionPressed: viewModel.beginEditing,
                handleKeyDown: viewModel.handleKeyDown
            )
            .frame(width: 0, height: 0)
        )
        .onChange(of: viewModel.shouldFocusSearch) { _, shouldFocus in
            if shouldFocus {
                searchFocused = true
                viewModel.shouldFocusSearch = false
            }
        }
        .onKeyPress(.escape) {
            if viewModel.renamingFolderID != nil { viewModel.renamingFolderID = nil }
            else if viewModel.openedFolderID != nil { viewModel.closeFolder() }
            else if !viewModel.searchQuery.isEmpty { viewModel.searchQuery = "" }
            else if viewModel.isEditing { viewModel.endEditing() }
            else { viewModel.onDismiss?() }
            return .handled
        }
        .alert(String(localized: "LaunchpadX Error"), isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
        .accessibilityIdentifier("launcher.root")
        .accessibilityValue(viewModel.isEditing ? "editing" : "normal")
    }

    private var launcherCanvas: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.top, 48)
            Spacer(minLength: 24)
            if viewModel.searchQuery.isEmpty {
                PagedLauncherGrid(
                    viewModel: viewModel,
                    settings: settings,
                    onBackgroundTap: handleBackgroundTap,
                    entryView: entryView
                )
            } else {
                searchGrid
            }
            Spacer(minLength: 20)
            if viewModel.searchQuery.isEmpty, viewModel.pageCount > 1 {
                pageControl.padding(.bottom, 36)
            } else {
                Color.clear.frame(height: 44)
            }
        }
        .padding(.horizontal, 42)
        .foregroundStyle(.white)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
            TextField(String(localized: "Search applications"), text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
                .onSubmit { viewModel.launchSelectedSearchResult() }
                .onKeyPress(.downArrow) { viewModel.moveSearchSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { viewModel.moveSearchSelection(by: -1); return .handled }
            if !viewModel.searchQuery.isEmpty {
                Button { viewModel.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.54))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 380, height: 38)
        .background(.black.opacity(0.26), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 8, y: 2)
    }

    private var searchGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 102, maximum: 156), spacing: 30), count: settings.columns),
            spacing: 30
        ) {
            ForEach(Array(viewModel.searchResults.prefix(9).enumerated()), id: \.element.id) { index, result in
                SearchResultTile(
                    result: result,
                    image: viewModel.icon(for: result.application),
                    iconSize: settings.iconSize,
                    selected: index == viewModel.selectedSearchIndex
                ) {
                    viewModel.launch(result: result)
                }
            }
        }
        .frame(maxWidth: 1_280)
        .padding(.horizontal, 40)
        .transition(.opacity)
    }

    @ViewBuilder
    private func entryView(_ entry: LauncherEntry, isActivePage: Bool) -> some View {
        let isDraggedEntry = viewModel.isDragging(entry)
        let tile = AppTile(
            entry: entry,
            image: entry.application.map(viewModel.icon(for:)),
            folderImages: entry.childApplicationRecordIDs.prefix(9).compactMap { viewModel.snapshot.applications[$0].map(viewModel.icon(for:)) },
            groupingImages: viewModel.groupingPreviewImages(for: entry),
            showsGroupingPreview: viewModel.groupingTargetID == entry.id,
            iconSize: settings.iconSize,
            editing: viewModel.isEditing && isActivePage && !isDraggedEntry,
            onDragBegan: {
                viewModel.beginDraggingFromPress(entry)
            },
            onDragMoved: {
                viewModel.updateRootDragLocation($0, windowFrame: $1)
            },
            onDragEnded: {
                viewModel.completeDraggingFromSourceIfNeeded()
            }
        ) {
            viewModel.open(entry)
        } onLongPress: {
            viewModel.beginEditing()
        }
        .opacity(isDraggedEntry ? 0 : 1)
        .allowsHitTesting(!isDraggedEntry)
        .contextMenu { contextMenu(for: entry) }

        tile
            .onDrop(
                of: [UTType.plainText],
                delegate: LauncherEntryDropDelegate(
                    entry: entry,
                    iconSize: settings.iconSize,
                    viewModel: viewModel
                )
            )
    }

    @ViewBuilder private func contextMenu(for entry: LauncherEntry) -> some View {
        if viewModel.isEditing, entry.kind == .application {
            Button(String(localized: "Hide Application")) { viewModel.hide(entry: entry) }
            Button(String(localized: "Show in Finder")) { viewModel.reveal(entry: entry) }
        } else if viewModel.isEditing {
            Button(String(localized: "Rename Folder")) {
                viewModel.beginRenamingFolder(entry)
            }
        }
    }

    private func handleBackgroundTap() {
        if viewModel.isEditing {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                viewModel.endEditing()
            }
            if viewModel.openedFolderID != nil {
                viewModel.closeFolder()
            }
        } else if viewModel.openedFolderID != nil { viewModel.closeFolder() }
        else { viewModel.onDismiss?() }
    }

    private var pageControl: some View {
        HStack(spacing: 8) {
            ForEach(0..<viewModel.pageCount, id: \.self) { page in
                Circle()
                    .fill(page == viewModel.selectedPage ? .white.opacity(0.95) : .white.opacity(0.42))
                    .frame(width: page == viewModel.selectedPage ? 7 : 6, height: page == viewModel.selectedPage ? 7 : 6)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.selectedPage = page }
            }
        }
        .shadow(color: .black.opacity(0.38), radius: 3, y: 1)
    }
}

private struct PagedLauncherGrid<Content: View>: View {
    @Bindable var viewModel: LauncherViewModel
    @Bindable var settings: SettingsStore
    let onBackgroundTap: () -> Void
    let entryView: (LauncherEntry, Bool) -> Content
    @State private var stableEntryFrames: [UUID: CGRect] = [:]
    @State private var retainedPage: Int?
    @State private var pageReleaseTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                HStack(spacing: 0) {
                    ForEach(0..<viewModel.pageCount, id: \.self) { page in
                        Group {
                            if shouldRender(page: page) {
                                pageGrid(
                                    entries: viewModel.entries(forPage: page),
                                    isActivePage: page == viewModel.selectedPage
                                )
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .offset(x: -CGFloat(viewModel.selectedPage) * proxy.size.width)
                .animation(.interactiveSpring(response: 0.30, dampingFraction: 0.88), value: viewModel.selectedPage)
            }
            .simultaneousGesture(
                SpatialTapGesture().onEnded { tap in
                    guard !stableEntryFrames.values.contains(where: {
                        $0.contains(tap.location)
                    }) else { return }
                    onBackgroundTap()
                }
            )
        }
        .clipped()
        .coordinateSpace(name: LauncherGridCoordinateSpace.name)
        .onPreferenceChange(LauncherEntryFramePreferenceKey.self) { frames in
            guard !viewModel.isDraggingSession, !frames.isEmpty else { return }
            stableEntryFrames = frames
        }
        .onAppear {
            retainedPage = viewModel.selectedPage
        }
        .onChange(of: viewModel.selectedPage) { oldPage, newPage in
            retainedPage = oldPage
            pageReleaseTask?.cancel()
            pageReleaseTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(360))
                guard !Task.isCancelled, viewModel.selectedPage == newPage else { return }
                retainedPage = newPage
            }
        }
        .onDisappear {
            pageReleaseTask?.cancel()
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: LauncherGridBackgroundDropDelegate(
                viewModel: viewModel,
                stableEntryFrames: stableEntryFrames
            )
        )
    }

    private func shouldRender(page: Int) -> Bool {
        page == viewModel.selectedPage
            || page == retainedPage
            || (viewModel.isDraggingSession && abs(page - viewModel.selectedPage) <= 1)
    }

    private func pageGrid(entries: [LauncherEntry], isActivePage: Bool) -> some View {
        VStack {
            Spacer(minLength: 0)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 102, maximum: 156), spacing: 30), count: settings.columns),
                spacing: 30
            ) {
                ForEach(entries) { entry in
                    entryView(entry, isActivePage)
                        .background {
                            if isActivePage, !viewModel.isDraggingSession {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: LauncherEntryFramePreferenceKey.self,
                                        value: [
                                            entry.id: proxy.frame(
                                                in: .named(LauncherGridCoordinateSpace.name)
                                            )
                                        ]
                                    )
                                }
                            }
                        }
                }
            }
            .animation(isActivePage ? LaunchpadTheme.gridSpring : nil, value: entries.map(\.id))
            .frame(maxWidth: 1_280)
            .padding(.horizontal, 28)
            Spacer(minLength: 0)
        }
    }
}

private enum LauncherGridCoordinateSpace {
    static let name = "launcher.grid"
}

private struct LauncherEntryFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct AppTile: View {
    let entry: LauncherEntry
    let image: NSImage?
    let folderImages: [NSImage]
    let groupingImages: [NSImage]
    let showsGroupingPreview: Bool
    let iconSize: Double
    let editing: Bool
    let onDragBegan: () -> Void
    let onDragMoved: (NSPoint, CGRect) -> Void
    let onDragEnded: () -> Void
    let action: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        ZStack {
            Group {
                if editing {
                    tileContent
                        .phaseAnimator(wigglePhases) { content, phase in
                            content
                                .rotationEffect(.degrees(phase ? wiggleAngle : -wiggleAngle))
                                .offset(
                                    x: phase ? wiggleTravel : -wiggleTravel,
                                    y: phase ? -0.28 : 0.28
                                )
                        } animation: { _ in
                            .easeInOut(duration: wiggleDuration)
                        }
                } else {
                    tileContent
                }
            }

            AppTilePressSurface(
                longPressDuration: LaunchpadTheme.editingLongPressDuration,
                editing: editing,
                dragPayload: entry.id.uuidString,
                dragImage: image ?? folderImages.first,
                dragImageSize: iconSize,
                onTap: action,
                onLongPress: onLongPress,
                onDragBegan: onDragBegan,
                onDragMoved: onDragMoved,
                onDragEnded: onDragEnded
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: showsGroupingPreview)
        .accessibilityLabel(entry.title)
        .accessibilityIdentifier("launcher.tile")
        .accessibilityValue(editing ? "editing" : "normal")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) {
            action()
        }
    }

    private var tileContent: some View {
        VStack(spacing: 7) {
            ZStack {
                if entry.kind == .folder {
                    FolderPreview(images: folderImages, size: iconSize)
                } else {
                    Image(nsImage: image ?? NSImage())
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                }

                if showsGroupingPreview {
                    FolderPreview(images: groupingImages, size: iconSize)
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                }
            }
            .frame(width: iconSize, height: iconSize)
            .compositingGroup()

            Text(entry.title)
                .font(.system(size: 12, weight: .regular))
                .lineLimit(1)
                .shadow(color: .black.opacity(0.85), radius: 2, y: 1)
                .frame(width: iconSize + 40)
        }
        .scaleEffect(showsGroupingPreview ? 1.10 : 1)
    }

    private var wiggleSeed: Int {
        entry.id.uuidString.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0x7fff }
    }

    private var wiggleAngle: Double {
        0.72 + Double(wiggleSeed % 7) * 0.075
    }

    private var wiggleTravel: Double {
        0.22 + Double((wiggleSeed / 7) % 5) * 0.055
    }

    private var wiggleDuration: Double {
        0.115 + Double((wiggleSeed / 11) % 5) * 0.009
    }

    private var wigglePhases: [Bool] {
        if wiggleSeed.isMultiple(of: 2) {
            [false, true]
        } else {
            [true, false]
        }
    }
}

private struct AppTilePressSurface: NSViewRepresentable {
    let longPressDuration: TimeInterval
    let editing: Bool
    let dragPayload: String
    let dragImage: NSImage?
    let dragImageSize: CGFloat
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onDragBegan: () -> Void
    let onDragMoved: (NSPoint, CGRect) -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> AppTilePressView {
        let view = AppTilePressView()
        view.longPressDuration = longPressDuration
        view.editing = editing
        view.dragPayload = dragPayload
        view.dragImage = dragImage
        view.dragImageSize = dragImageSize
        view.onTap = onTap
        view.onLongPress = onLongPress
        view.onDragBegan = onDragBegan
        view.onDragMoved = onDragMoved
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: AppTilePressView, context: Context) {
        nsView.longPressDuration = longPressDuration
        nsView.editing = editing
        nsView.dragPayload = dragPayload
        nsView.dragImage = dragImage
        nsView.dragImageSize = dragImageSize
        nsView.onTap = onTap
        nsView.onLongPress = onLongPress
        nsView.onDragBegan = onDragBegan
        nsView.onDragMoved = onDragMoved
        nsView.onDragEnded = onDragEnded
    }
}

private final class AppTilePressView: NSView, NSDraggingSource {
    var longPressDuration: TimeInterval = LaunchpadTheme.editingLongPressDuration
    var editing = false
    var dragPayload = ""
    var dragImage: NSImage?
    var dragImageSize: CGFloat = 94
    var onTap: () -> Void = {}
    var onLongPress: () -> Void = {}
    var onDragBegan: () -> Void = {}
    var onDragMoved: (NSPoint, CGRect) -> Void = { _, _ in }
    var onDragEnded: () -> Void = {}

    private var isTrackingPress = false
    private var didTriggerLongPress = false
    private var isReadyToDrag = false
    private var didStartDragging = false
    private var pressOrigin = NSPoint.zero
    private var dragWindowFrame = NSRect.zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0 else { return }
        cancelPress()
        isTrackingPress = true
        pressOrigin = convert(event.locationInWindow, from: nil)
        if editing {
            isReadyToDrag = true
            return
        }
        perform(
            #selector(triggerLongPress),
            with: nil,
            afterDelay: longPressDuration,
            inModes: [.common]
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTrackingPress else { return }
        let location = convert(event.locationInWindow, from: nil)
        let distance = hypot(location.x - pressOrigin.x, location.y - pressOrigin.y)
        if isReadyToDrag, !didStartDragging, distance > 4 {
            beginDragging(with: event)
        } else if !isReadyToDrag, distance > 18 {
            cancelPress()
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isTrackingPress, !didStartDragging else { return }
        let shouldTap = !didTriggerLongPress
        cancelPress()
        if shouldTap {
            onTap()
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, !didStartDragging {
            cancelPress()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    @objc private func triggerLongPress() {
        guard isTrackingPress else { return }
        didTriggerLongPress = true
        isReadyToDrag = true
        onLongPress()
    }

    private func beginDragging(with event: NSEvent) {
        guard !dragPayload.isEmpty else { return }
        didStartDragging = true
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(triggerLongPress),
            object: nil
        )

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(
            dragPayload,
            forType: NSPasteboard.PasteboardType(UTType.plainText.identifier)
        )
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let size = min(dragImageSize, min(bounds.width, bounds.height))
        draggingItem.setDraggingFrame(
            NSRect(
                x: (bounds.width - size) / 2,
                y: (bounds.height - size) / 2,
                width: size,
                height: size
            ),
            contents: dragImage ?? NSImage()
        )
        dragWindowFrame = window?.frame ?? .zero
        onDragBegan()
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
        session.draggingFormation = .none
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        onDragMoved(screenPoint, dragWindowFrame)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        // The drop delegate normally commits first. This also clears or commits
        // sessions that AppKit reports as moved without invoking performDrop.
        onDragEnded()
        cancelPress()
    }

    private func cancelPress() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(triggerLongPress),
            object: nil
        )
        isTrackingPress = false
        didTriggerLongPress = false
        isReadyToDrag = false
        didStartDragging = false
        dragWindowFrame = .zero
    }
}

private struct SearchResultTile: View {
    let result: SearchResult
    let image: NSImage
    let iconSize: Double
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(nsImage: image)
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                Text(result.application.displayName)
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.85), radius: 2, y: 1)
                    .frame(width: iconSize + 40)
            }
            .padding(8)
            .background(selected ? .white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(result.application.displayName)
    }
}

private struct FolderPreview: View {
    let images: [NSImage]
    let size: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.20, style: .continuous)
                .fill(.white.opacity(0.20))
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.20, style: .continuous)
                        .stroke(.white.opacity(0.20), lineWidth: 0.5)
                }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                ForEach(Array(images.prefix(9).enumerated()), id: \.offset) { _, image in
                    Image(nsImage: image).resizable().scaledToFit()
                }
            }
            .padding(size * 0.12)
        }
        .frame(width: size, height: size)
    }
}

struct LauncherEntryDropDelegate: DropDelegate {
    let entry: LauncherEntry
    let iconSize: Double
    let viewModel: LauncherViewModel

    func dropEntered(info: DropInfo) {
        updateGroupingState(for: info)
    }

    func dropExited(info: DropInfo) {
        viewModel.dragExited(target: entry)
    }

    func performDrop(info: DropInfo) -> Bool {
        viewModel.performDrop(on: entry)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateGroupingState(for: info)
        return DropProposal(operation: .move)
    }

    nonisolated static func isGroupingLocation(_ location: CGPoint, iconSize: Double) -> Bool {
        let tileWidth = iconSize + 40
        let iconCenter = CGPoint(x: tileWidth / 2, y: iconSize / 2)
        let radius = iconSize * 0.38
        return hypot(location.x - iconCenter.x, location.y - iconCenter.y) <= radius
    }

    private func updateGroupingState(for info: DropInfo) {
        viewModel.dragMoved(
            over: entry,
            grouping: Self.isGroupingLocation(info.location, iconSize: iconSize)
        )
    }
}

private struct LauncherGridBackgroundDropDelegate: DropDelegate {
    let viewModel: LauncherViewModel
    let stableEntryFrames: [UUID: CGRect]

    func performDrop(info: DropInfo) -> Bool {
        if let targetID = nearestEntryID(to: info.location),
           let target = viewModel.snapshot.entries.first(where: { $0.id == targetID }) {
            viewModel.moveDraggedEntry(toOriginalSlotOf: target.id)
            return viewModel.performDrop(on: target)
        }
        return viewModel.performBackgroundDrop()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    private func nearestEntryID(to location: CGPoint) -> UUID? {
        stableEntryFrames.min { lhs, rhs in
            Self.distanceSquared(from: location, to: lhs.value)
                < Self.distanceSquared(from: location, to: rhs.value)
        }?.key
    }

    private static func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = point.x - rect.midX
        let dy = point.y - rect.midY
        return dx * dx + dy * dy
    }
}

private struct LauncherBackgroundView: View {
    @Bindable var settings: SettingsStore
    @State private var cachedImage: NSImage?
    @State private var loadedSourceKey: String?

    var body: some View {
        ZStack {
            if loadedSourceKey == sourceKey, let image = cachedImage {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [LaunchpadTheme.desktop, LaunchpadTheme.violet.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            Rectangle().fill(.black.opacity(0.43))
            Rectangle().fill(.white.opacity(0.025))
        }
        .ignoresSafeArea()
        .task(id: sourceKey) {
            let key = sourceKey
            cachedImage = await loadBackgroundImage()
            guard !Task.isCancelled, sourceKey == key else { return }
            loadedSourceKey = key
        }
    }

    private var sourceKey: String {
        switch settings.backgroundKind {
        case .brandGradient:
            "gradient"
        case .wallpaper:
            "wallpaper:\(NSScreen.main?.displayID ?? 0)"
        case .customImage:
            "custom:\(settings.customBackgroundPath ?? "")"
        }
    }

    private func loadBackgroundImage() async -> NSImage? {
        let url: URL?
        switch settings.backgroundKind {
        case .brandGradient:
            return nil
        case .wallpaper:
            url = NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        case .customImage:
            url = settings.customBackgroundPath.map(URL.init(fileURLWithPath:))
        }
        guard let url else { return nil }
        let data = await Task.detached(priority: .utility) {
            try? Data(contentsOf: url, options: .mappedIfSafe)
        }.value
        return data.flatMap(NSImage.init(data:))
    }
}

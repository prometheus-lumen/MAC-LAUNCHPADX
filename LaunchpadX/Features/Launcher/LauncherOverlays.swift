import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SearchResultsView: View {
    @Bindable var viewModel: LauncherViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Search Results").font(.headline)
                Spacer()
                Text("\(viewModel.searchResults.count) / 9")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(22)

            Divider().overlay(.white.opacity(0.15))
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(viewModel.searchResults.enumerated()), id: \.element.id) { index, result in
                        Button { viewModel.launch(result: result) } label: {
                            HStack(spacing: 14) {
                                Image(nsImage: viewModel.icon(for: result.application))
                                    .resizable().scaledToFit().frame(width: 42, height: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.application.displayName).fontWeight(.medium)
                                    Text(result.application.bundleIdentifier ?? result.application.bundleURL.path)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text("⌘\(index + 1)").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(index == viewModel.selectedSearchIndex ? LaunchpadTheme.accent.opacity(0.28) : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 410)
            HStack {
                Text("↑↓ Select")
                Text("↩ Open")
                Text("Esc Close")
                Spacer()
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 22).padding(.vertical, 15)
        }
        .frame(width: 780, height: 570)
        .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 28))
        .glassEffect(.regular.tint(.white.opacity(0.08)), in: RoundedRectangle(cornerRadius: 28))
        .shadow(color: .black.opacity(0.45), radius: 40, y: 16)
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard press.modifiers.contains(.command), let index = Int(press.characters), index > 0,
                  viewModel.searchResults.indices.contains(index - 1) else { return .ignored }
            viewModel.launch(result: viewModel.searchResults[index - 1])
            return .handled
        }
    }
}

struct FolderOverlayView: View {
    @Bindable var viewModel: LauncherViewModel
    let folder: LauncherEntry
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
                if viewModel.renamingFolderID == folder.id {
                    TextField(String(localized: "Folder name"), text: $draftName)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(.white.opacity(0.14), in: Capsule())
                        .frame(width: 260)
                        .focused($nameFocused)
                        .onSubmit { viewModel.saveFolderName(draftName) }
                        .onKeyPress(.escape) { viewModel.renamingFolderID = nil; return .handled }
                        .accessibilityIdentifier("folder.name.editor")
                } else {
                    Text(folder.title)
                        .font(.system(size: 20, weight: .regular))
                        .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            viewModel.beginRenamingFolder(folder)
                        }
                        .accessibilityIdentifier("folder.name.label")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(112), spacing: 30), count: 5), spacing: 30) {
                    ForEach(viewModel.openedFolderApplications, id: \.0) { recordID, app in
                        folderApplication(recordID: recordID, application: app)
                    }
                }
                .animation(LaunchpadTheme.gridSpring, value: viewModel.openedFolderApplications.map(\.0))
                .padding(.bottom, 6)
        }
        .padding(.horizontal, 54).padding(.vertical, 40)
        .frame(minWidth: 660, maxWidth: 800, minHeight: 360)
        .foregroundStyle(.white)
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.56), radius: 36, y: 18)
        .onDrop(
            of: [UTType.plainText],
            delegate: FolderGridBackgroundDropDelegate(viewModel: viewModel)
        )
        .onAppear {
            draftName = folder.title
            focusNameIfNeeded()
        }
        .onChange(of: viewModel.renamingFolderID) { _, _ in
            focusNameIfNeeded()
        }
    }

    private func focusNameIfNeeded() {
        guard viewModel.renamingFolderID == folder.id else { return }
        draftName = folder.title
        DispatchQueue.main.async { nameFocused = true }
    }

    @ViewBuilder
    private func folderApplication(
        recordID: UUID,
        application: InstalledApplication
    ) -> some View {
        let tile = FolderApplicationTile(
            title: application.displayName,
            image: viewModel.icon(for: application),
            editing: viewModel.isEditing
        )
        .opacity(viewModel.isDraggingFolderApplication(recordID: recordID) ? 0 : 1)
        .contextMenu {
            if viewModel.isEditing {
                Button(String(localized: "Remove from Folder")) {
                    viewModel.removeFromFolder(recordID: recordID)
                }
            }
            Button(String(localized: "Show in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([application.bundleURL])
            }
        }

        if viewModel.isEditing {
            tile
                .onDrag {
                    viewModel.folderDragProvider(recordID: recordID)
                } preview: {
                    Image(nsImage: viewModel.icon(for: application))
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 82, height: 82)
                        .scaleEffect(1.06)
                        .shadow(color: .black.opacity(0.32), radius: 12, y: 7)
                }
                .onDrop(
                    of: [UTType.plainText],
                    delegate: FolderApplicationDropDelegate(
                        recordID: recordID,
                        viewModel: viewModel
                    )
                )
        } else {
            Button {
                viewModel.launch(application: application, recordID: recordID)
            } label: {
                tile
            }
            .buttonStyle(.plain)
            .accessibilityLabel(application.displayName)
            .accessibilityIdentifier("folder.tile")
        }
    }
}

private struct FolderApplicationTile: View {
    let title: String
    let image: NSImage
    let editing: Bool
    @State private var isWiggling = false

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 82, height: 82)
            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(width: 112)
                .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
        }
        .rotationEffect(.degrees(editing ? (isWiggling ? 0.82 : -0.82) : 0))
        .offset(x: editing ? (isWiggling ? 0.34 : -0.34) : 0)
        .contentShape(Rectangle())
        .onAppear(perform: updateWiggle)
        .onChange(of: editing) { _, _ in updateWiggle() }
        .accessibilityLabel(title)
        .accessibilityIdentifier("folder.tile")
    }

    private func updateWiggle() {
        if editing {
            isWiggling = false
            withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true)) {
                isWiggling = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.12)) {
                isWiggling = false
            }
        }
    }
}

private struct FolderApplicationDropDelegate: DropDelegate {
    let recordID: UUID
    let viewModel: LauncherViewModel

    func dropEntered(info: DropInfo) {
        viewModel.folderDragMoved(over: recordID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        viewModel.folderDragMoved(over: recordID)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        viewModel.performFolderDrop(on: recordID)
    }
}

private struct FolderGridBackgroundDropDelegate: DropDelegate {
    let viewModel: LauncherViewModel

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        viewModel.performFolderBackgroundDrop()
    }
}

struct FolderOutsideDropDelegate: DropDelegate {
    let viewModel: LauncherViewModel

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        viewModel.performFolderDropOutside()
    }
}

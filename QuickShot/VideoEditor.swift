//
//  VideoEditor.swift
//  QuickShot
//

import AVKit
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// One recording open for trimming and export.
@MainActor
final class VideoEditorModel: ObservableObject {
    let sourceURL: URL
    let player: AVPlayer
    let baseName: String
    @Published private(set) var duration: Double = 0
    @Published private(set) var trimStart: Double = 0
    @Published private(set) var trimEnd: Double = 0
    @Published private(set) var hasAudio = false
    @Published var includesAudio = true
    /// A Copy or Save is running. Only one runs at a time, and the window stays open
    /// until it ends, because it is still reading the recording.
    @Published private(set) var isBusy = false
    /// The player view's trim handles are showing; its own Trim and Cancel buttons apply.
    @Published private(set) var isTrimming = false
    /// Nil while exporting means the progress is unknown.
    @Published private(set) var progress: Double?
    @Published var statusMessage: String?
    /// True until the recording has been copied or saved once.
    @Published private(set) var hasUnsavedChanges = true
    /// The recording's length and tracks are known, so it can be trimmed and exported.
    @Published private(set) var isLoaded = false

    weak var playerView: AVPlayerView?
    private let settings: AppSettings
    private var lastExport: (key: ExportKey, url: URL)?
    /// Every folder this editor exported into, so a discarded recording leaves nothing behind.
    private var exportFolders: [URL] = []

    /// The export choices, read once when Copy or Save starts. Editors share the
    /// settings, so reading them again later could mix one editor's format with another's.
    struct ExportRequest: Hashable {
        let format: VideoFormat
        let frameRate: Int
        let width: Int
    }

    private struct ExportKey: Hashable {
        let edit: VideoEdit
        let request: ExportRequest
    }

    init(url: URL, settings: AppSettings) {
        sourceURL = url
        baseName = url.deletingPathExtension().lastPathComponent
        player = AVPlayer(url: url)
        self.settings = settings
        Task { await load() }
    }

    var isTrimmed: Bool { trimStart > 0.01 || (duration > 0 && trimEnd < duration - 0.01) }
    var selectedDuration: Double { max(0, trimEnd - trimStart) }

    private func load() async {
        let asset = AVURLAsset(url: sourceURL)
        do {
            let seconds = try await asset.load(.duration).seconds
            let audio = try await asset.loadTracks(withMediaType: .audio)
            guard seconds.isFinite, seconds > 0 else { throw VideoExportError.emptyRange }
            duration = seconds
            trimEnd = seconds
            hasAudio = !audio.isEmpty
            isLoaded = true
        } catch {
            statusMessage = "QuickShot could not open this recording."
        }
    }

    // MARK: Trimming

    func beginTrim() {
        guard isLoaded, let playerView, playerView.canBeginTrimming else { return }
        isTrimming = true
        playerView.beginTrimming { [weak self] result in
            MainActor.assumeIsolated {
                self?.isTrimming = false
                guard result == .okButton else { return }
                self?.readTrim()
            }
        }
    }

    func resetTrim() {
        player.currentItem?.reversePlaybackEndTime = .invalid
        player.currentItem?.forwardPlaybackEndTime = .invalid
        readTrim()
    }

    /// The player view stores the trim on the item as its playback end times.
    private func readTrim() {
        guard let item = player.currentItem else { return }
        let start = item.reversePlaybackEndTime
        let end = item.forwardPlaybackEndTime
        trimStart = start.isValid && start.isNumeric ? max(0, start.seconds) : 0
        trimEnd = end.isValid && end.isNumeric ? min(duration, end.seconds) : duration
        statusMessage = nil
    }

    // MARK: Export

    var summary: String {
        var parts = [RecordingGeometry.timecode(selectedDuration) + (isTrimmed ? " of " + RecordingGeometry.timecode(duration) : "")]
        switch settings.videoFormat {
        case .mov:
            parts.append(hasAudio ? (includesAudio ? "with sound" : "no sound") : "no sound recorded")
        case .gif:
            parts.append("\(settings.gifFrameRate) fps, \(GIFOptions.widthTitle(settings.gifMaxWidth).lowercased())")
        }
        return parts.joined(separator: " · ")
    }

    func currentRequest() -> ExportRequest {
        ExportRequest(format: settings.videoFormat, frameRate: settings.gifFrameRate, width: settings.gifMaxWidth)
    }

    /// Exports with the given choices, reusing the last file when nothing has changed.
    func export(_ request: ExportRequest) async throws -> URL {
        guard isLoaded else { throw VideoExportError.failed("The recording is still opening.") }
        let format = request.format
        let edit = VideoEdit(start: trimStart, end: trimEnd, includesAudio: includesAudio && hasAudio && format == .mov)
        let key = ExportKey(edit: edit, request: request)
        if let lastExport, lastExport.key == key, FileManager.default.fileExists(atPath: lastExport.url.path) {
            return lastExport.url
        }

        let folder = RecordingController.recordingsFolder.appendingPathComponent("Exports/\(UUID().uuidString)", isDirectory: true)
        let destination = folder.appendingPathComponent(baseName).appendingPathExtension(format.fileExtension)

        progress = format == .gif ? 0 : nil
        statusMessage = format == .gif ? "Making GIF…" : "Exporting movie…"
        defer { progress = nil }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            exportFolders.append(folder)
            switch format {
            case .mov:
                try await VideoExporter.exportMovie(from: sourceURL, edit: edit, to: destination)
            case .gif:
                let relay = ProgressRelay { [weak self] fraction in self?.progress = fraction }
                try await VideoExporter.exportGIF(
                    from: sourceURL, start: edit.start, end: edit.end,
                    frameRate: request.frameRate, maxWidth: request.width, to: destination
                ) { fraction in
                    relay.send(fraction)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            statusMessage = error.localizedDescription
            throw error
        }
        statusMessage = nil
        lastExport = (key, destination)
        return destination
    }

    func markSaved() { hasUnsavedChanges = false }

    /// Claims the editor for one Copy or Save. Returns false while another is running.
    func beginWork() -> Bool {
        guard isLoaded, !isBusy else { return false }
        isBusy = true
        return true
    }

    func endWork() {
        isBusy = false
        progress = nil
    }

    /// Deletes this editor's exports, except a file the clipboard still offers for pasting.
    func removeExports() {
        let onClipboard = (NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        for folder in exportFolders {
            let inUse = onClipboard.contains { $0.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/") }
            if !inUse { try? FileManager.default.removeItem(at: folder) }
        }
        exportFolders = []
        lastExport = nil
    }

    func fileSizeDescription(of url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// Carries export progress from a background task to the editor.
private final class ProgressRelay: @unchecked Sendable {
    private let apply: @MainActor (Double) -> Void

    init(_ apply: @escaping @MainActor (Double) -> Void) {
        self.apply = apply
    }

    nonisolated func send(_ value: Double) {
        Task { @MainActor in self.apply(value) }
    }
}

struct VideoEditorCommands {
    var copy: () -> Void
    var save: (_ askWhere: Bool) -> Void
    var close: () -> Void
}

struct VideoEditorView: View {
    @ObservedObject var model: VideoEditorModel
    @ObservedObject var settings: AppSettings
    let commands: VideoEditorCommands

    var body: some View {
        VStack(spacing: 0) {
            PlayerView(model: model)
                .frame(minWidth: 560, minHeight: 300)
            Divider()
            VStack(spacing: 10) {
                editRow
                actionRow
            }
            .padding(12)
            // While trimming, Return and Esc belong to the player's Trim and Cancel buttons.
            .disabled(model.isBusy || model.isTrimming)
        }
    }

    private var editRow: some View {
        HStack(spacing: 14) {
            Button(action: model.beginTrim) {
                Label("Trim", systemImage: "timeline.selection")
            }
            .disabled(!model.isLoaded)
            .keyboardShortcut("t", modifiers: .command)
            .help("Drag the yellow handles to keep only part of the recording (⌘T)")
            if model.isTrimmed {
                Button("Reset Trim", action: model.resetTrim)
            }

            Toggle("Sound", isOn: $model.includesAudio)
                .toggleStyle(.checkbox)
                .disabled(!model.hasAudio || settings.videoFormat == .gif)
                .help(model.hasAudio ? "Keep or remove the recorded sound" : "This recording has no sound")

            Spacer(minLength: 8)

            Picker("Format", selection: $settings.videoFormat) {
                Text("MOV").tag(VideoFormat.mov)
                Text("GIF").tag(VideoFormat.gif)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Export as a movie or an animated GIF")

            if settings.videoFormat == .gif {
                Picker("Frame rate", selection: $settings.gifFrameRate) {
                    ForEach(GIFOptions.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Picker("Size", selection: $settings.gifMaxWidth) {
                    ForEach(GIFOptions.widths, id: \.self) { Text(GIFOptions.widthTitle($0)).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button("Close", action: commands.close)
                .keyboardShortcut(.cancelAction)
            if model.isBusy {
                if let progress = model.progress {
                    ProgressView(value: progress).frame(width: 90)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            Text(model.statusMessage ?? model.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Group {
                Button("Copy") { commands.copy() }
                    .keyboardShortcut("c", modifiers: .command)
                    .help("Copy the \(settings.videoFormat == .gif ? "GIF" : "movie") to paste into another app (⌘C)")
                Button("Save As…") { commands.save(true) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Save") { commands.save(false) }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .help(settings.saveFolderURL == nil ? "Choose where to save (⌘S)" : "Save to \(settings.saveFolderName ?? "the save folder") (⌘S)")
            }
            .disabled(!model.isLoaded)
        }
    }
}

private struct PlayerView: NSViewRepresentable {
    let model: VideoEditorModel

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = model.player
        view.controlsStyle = .inline
        view.showsFrameSteppingButtons = true
        view.showsFullScreenToggleButton = false
        view.videoGravity = .resizeAspect
        model.playerView = view
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}
}

final class VideoEditorWindowController: NSWindowController, NSWindowDelegate {
    private let model: VideoEditorModel
    private let settings: AppSettings
    private var discardConfirmed = false
    var onClose: (() -> Void)?

    init(recording url: URL, settings: AppSettings) {
        model = VideoEditorModel(url: url, settings: settings)
        self.settings = settings

        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: min(1_040, visible.width - 40), height: min(720, visible.height - 60)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuickShot — Recording"
        window.minSize = NSSize(width: 680, height: 440)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: VideoEditorView(
            model: model,
            settings: settings,
            commands: VideoEditorCommands(
                copy: { [weak self] in self?.copy() },
                save: { [weak self] askWhere in self?.save(askWhere: askWhere) },
                close: { [weak self] in self?.window?.performClose(nil) }
            )
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        model.player.play()
    }

    var hasUnsavedRecording: Bool { model.hasUnsavedChanges }
    /// A Copy or Save is still running.
    var isBusy: Bool { model.isBusy }

    /// Closes without asking; used once the user has agreed to discard, for example at Quit.
    func discardAndClose() {
        discardConfirmed = true
        window?.close()
    }

    /// A recording that was never copied or saved is not thrown away without asking, and
    /// the window stays open while an export is still reading the recording.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.isBusy {
            NSSound.beep()
            model.statusMessage = "Wait for the copy or save to finish, then close."
            return false
        }
        guard model.hasUnsavedChanges, !discardConfirmed else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Discard this recording?"
        alert.informativeText = "It has not been copied or saved."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: sender) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.discardConfirmed = true
            sender.close()
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        model.player.pause()
        model.player.replaceCurrentItem(with: nil)
        try? FileManager.default.removeItem(at: model.sourceURL)
        model.removeExports()
        onClose?()
        onClose = nil
    }

    // MARK: Commands

    private func copy() {
        let request = model.currentRequest()
        let format = request.format
        guard model.beginWork() else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.model.endWork() }
            guard let url = try? await self.model.export(request) else { return }
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            // Apps that take pasted images, but not files, still get the animation.
            if format == .gif, let data = try? Data(contentsOf: url) {
                item.setData(data, forType: NSPasteboard.PasteboardType(UTType.gif.identifier))
            }
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.writeObjects([item]) {
                self.model.markSaved()
                HUD.show(format == .gif ? "Copied GIF (\(self.model.fileSizeDescription(of: url)))" : "Copied movie",
                         symbol: "doc.on.clipboard.fill")
            } else {
                self.model.statusMessage = "QuickShot could not copy the file."
            }
        }
    }

    /// Saves to the chosen folder in one step, or asks where with a save panel.
    private func save(askWhere: Bool) {
        let request = model.currentRequest()
        let format = request.format
        let base = model.baseName
        if !askWhere, settings.saveFolderURL != nil {
            guard model.beginWork() else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let exported = try? await self.model.export(request) else {
                    self.model.endWork()
                    return
                }
                self.model.statusMessage = "Saving…"
                let saved = try? await self.settings.withSaveFolder { folder -> URL in
                    let destination = AppSettings.uniqueFileURL(in: folder, base: base, fileExtension: format.fileExtension)
                    try await Self.placeInBackground(exported, at: destination)
                    return destination
                }
                self.model.statusMessage = nil
                self.model.endWork()
                if let destination = saved ?? nil {
                    self.finishSave(destination, message: "Saved to \(self.settings.saveFolderName ?? "folder")")
                } else {
                    // The folder has gone or refused the file; ask instead.
                    self.save(askWhere: true)
                }
            }
            return
        }

        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveFolderURL
            ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        panel.nameFieldStringValue = "\(base).\(format.fileExtension)"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self, self.model.beginWork() else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.model.endWork() }
                guard let exported = try? await self.model.export(request) else { return }
                self.model.statusMessage = "Saving…"
                do {
                    try await Self.placeInBackground(exported, at: url)
                    self.model.statusMessage = nil
                    self.finishSave(url, message: "Saved \(url.lastPathComponent)")
                } catch {
                    self.model.statusMessage = "Could not save: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Copies away from the main thread, so a large movie going to a slow disk does not
    /// freeze the editor.
    private static func placeInBackground(_ exported: URL, at destination: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try place(exported, at: destination)
        }.value
    }

    /// Copies the export to `destination`. An existing file there (the save panel has
    /// already asked about replacing it) is swapped out only once the new copy is complete,
    /// so a failed save leaves it untouched. The copy is staged in the system's replacement
    /// folder for the destination's volume, which the sandbox allows and which lets the
    /// swap happen within one volume.
    nonisolated private static func place(_ exported: URL, at destination: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: destination.path) else {
            try manager.copyItem(at: exported, to: destination)
            return
        }
        let replacementFolder = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                appropriateFor: destination, create: true)
        defer { try? manager.removeItem(at: replacementFolder) }
        let staged = replacementFolder.appendingPathComponent("QuickShot-save-\(UUID().uuidString)")
            .appendingPathExtension(destination.pathExtension)
        try manager.copyItem(at: exported, to: staged)
        _ = try manager.replaceItemAt(destination, withItemAt: staged)
    }

    private func finishSave(_ url: URL, message: String) {
        model.markSaved()
        if settings.copyPathMode {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
            HUD.show("Saved, path copied", symbol: "square.and.arrow.down.fill")
        } else {
            HUD.show(message, symbol: "square.and.arrow.down.fill")
        }
    }
}

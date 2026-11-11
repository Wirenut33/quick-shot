//
//  AnnotationEditorView.swift
//  QuickShot
//

import AppKit
import SwiftUI

/// What the editor's buttons do. The window controller supplies these so the buttons
/// and the keyboard shortcuts run the same code.
struct EditorCommands {
    var copyAndClose: () -> Void = {}
    var save: (_ askWhere: Bool) -> Void = { _ in }
    var addToCollection: () -> Void = {}
    var copyText: () -> Void = {}
    var close: () -> Void = {}
}

struct AnnotationEditorView: View {
    @ObservedObject var document: AnnotationDocument
    @ObservedObject var settings: AppSettings
    let commands: EditorCommands
    @State private var shownScale: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            toolBar
            styleBar
            Divider()
            canvas
            Divider()
            descriptionArea
            Divider()
            actionBar
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private var canvas: some View {
        GeometryReader { proxy in
            let scale = document.displayScale(fitting: CGSize(width: proxy.size.width - 48, height: proxy.size.height - 48))
            ScrollView([.horizontal, .vertical]) {
                AnnotationCanvasView(document: document, displayScale: scale)
                    .frame(
                        width: document.canvasSize.width * scale,
                        height: document.canvasSize.height * scale
                    )
                    .background(Color.white)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                    .padding(24)
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
            .onAppear { shownScale = scale }
            .onChange(of: scale) { _, value in shownScale = value }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Tools

    private var toolBar: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationTool.allCases) { tool in
                let selected = document.selectedTool == tool
                Button {
                    document.selectedTool = tool
                } label: {
                    Image(systemName: tool.symbolName)
                        .frame(width: 32, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? Color.accentColor.opacity(0.25) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1)
                )
                .help("\(tool.rawValue) (\(tool.shortcutKey))")
                .accessibilityLabel(tool.rawValue)
                .accessibilityHint("Shortcut \(tool.shortcutKey)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }

            Spacer(minLength: 12)

            iconButton("Undo", "arrow.uturn.backward", help: "Undo (⌘Z)") { document.undo() }
                .disabled(!document.canUndo)
                .keyboardShortcut("z", modifiers: .command)
            iconButton("Redo", "arrow.uturn.forward", help: "Redo (⇧⌘Z)") { document.redo() }
                .disabled(!document.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            iconButton("Delete Selected Mark", "delete.left", help: "Delete the selected mark (⌫)") { document.deleteSelected() }
                .disabled(document.selectedMark == nil)
            iconButton("Clear All Marks", "trash", help: "Remove every mark") { document.clear() }
                .disabled(document.annotations.isEmpty)
            iconButton("Expand Canvas", "arrow.up.left.and.arrow.down.right", help: "Add room around the screenshot") {
                document.expandCanvas()
            }
            .disabled(document.canvasPadding >= 360)

            Divider().frame(height: 18).padding(.horizontal, 4)

            iconButton("Zoom Out", "minus.magnifyingglass", help: "Zoom out (⌘−)") { document.zoomOut() }
            Menu {
                Button("Fit to Window (⌘1)") { document.zoomToFit() }
                Button("Actual Size (⌘0)") { document.zoomToActualSize() }
            } label: {
                Text(document.zoom == .fit ? "Fit" : "\(Int((shownScale * document.backingScale * 100).rounded()))%")
                    .monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Zoom level")
            .accessibilityLabel("Zoom")
            iconButton("Zoom In", "plus.magnifyingglass", help: "Zoom in (⌘+)") { document.zoomIn() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func iconButton(_ label: String, _ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 22, height: 20)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(label)
    }

    // MARK: Style

    private func styleBinding<Value>(_ key: WritableKeyPath<AnnotationStyle, Value>) -> Binding<Value> {
        Binding(get: { document.style[keyPath: key] }, set: { value in
            var style = document.style; style[keyPath: key] = value; document.applyStyle(style)
        })
    }

    /// The tool whose options are showing: the selected mark's, or the active tool's.
    private var activeTool: AnnotationTool {
        document.selectedMark?.tool ?? document.selectedTool
    }

    private var styleBar: some View {
        HStack(spacing: 14) {
            if activeTool == .select {
                Text("Pick a tool, or click a mark to change it.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 3) {
                    ForEach(AnnotationColor.allCases) { color in
                        let selected = document.style.color == color
                        Button {
                            var style = document.style; style.color = color; document.applyStyle(style)
                        } label: {
                            Circle()
                                .fill(Color(nsColor: color.nsColor))
                                .frame(width: 18, height: 18)
                                .overlay(Circle().stroke(Color.primary.opacity(selected ? 0.9 : 0.25), lineWidth: selected ? 2 : 1))
                                .padding(3)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(color.rawValue)
                        .accessibilityLabel("\(color.rawValue) colour")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .disabled(activeTool == .redact && document.style.pixelate)

                switch activeTool {
                case .rectangle, .arrow, .line, .polyline:
                    Picker("Stroke", selection: styleBinding(\.width)) {
                        Text("Thin").tag(CGFloat(3)); Text("Medium").tag(CGFloat(6)); Text("Thick").tag(CGFloat(12))
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .accessibilityLabel("Stroke width")
                    Toggle("Dashed", isOn: styleBinding(\.dashed))
                case .text:
                    Stepper("Size \(Int(document.style.fontSize))", value: styleBinding(\.fontSize), in: 12...144, step: 4)
                        .fixedSize()
                    Toggle("Bold", isOn: styleBinding(\.bold))
                case .redact:
                    Picker("Redaction", selection: styleBinding(\.pixelate)) {
                        Text("Solid").tag(false); Text("Pixelate").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .accessibilityLabel("Redaction style")
                    Text(document.style.pixelate ? "Pixelation can sometimes be reversed. Use Solid for secrets." : "Solid fully hides what is underneath.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                default:
                    EmptyView()
                }
            }
            Spacer(minLength: 0)
            if document.selectedMark != nil {
                Text("Editing selected mark").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: Description and actions

    private var descriptionArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Describe the requested change (optional)")
                .font(.headline)
            TextEditor(text: $document.descriptionText)
                .font(.body)
                .frame(height: 48)
                .padding(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                )
                .accessibilityLabel("Description")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Text(document.statusMessage)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(-1)
                .accessibilityLabel("Status: \(document.statusMessage)")

            Button("Copy Text", action: commands.copyText)
                .help("Copy the text and QR codes in this image")

            Button("Add to Collection", action: commands.addToCollection)

            Button("Close", action: commands.close)

            Button {
                commands.save(false)
            } label: {
                Label(settings.copyPathMode ? "Save & Copy Path" : "Save", systemImage: "square.and.arrow.down")
            }
            .help(settings.saveFolderURL == nil
                  ? "Save as PNG (⌘S)"
                  : "Save to \(settings.saveFolderName ?? "the save folder") (⌘S). ⇧⌘S asks where.")

            Button(action: commands.copyAndClose) {
                Label("Copy & Close", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Copy the image and close (⌘↩)")
        }
        .padding(14)
    }
}

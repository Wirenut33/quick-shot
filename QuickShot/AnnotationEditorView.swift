//
//  AnnotationEditorView.swift
//  QuickShot
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AnnotationEditorView: View {
    @ObservedObject var document: AnnotationDocument
    let screenshotManager: ScreenshotManager
    let collection: SnapshotCollection
    let closeWindow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolBar
            styleBar
            Divider()

            ScrollView([.horizontal, .vertical]) {
                AnnotationCanvasView(document: document, displayScale: document.displayScale)
                    .frame(
                        width: document.canvasSize.width * document.displayScale,
                        height: document.canvasSize.height * document.displayScale
                    )
                    .background(Color.white)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                    .padding(24)
            }
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()
            descriptionArea
            Divider()
            actionBar
        }
        .frame(minWidth: 1040, minHeight: 620)
    }

    private var toolBar: some View {
        HStack(spacing: 12) {
            Picker("Tool", selection: $document.selectedTool) {
                ForEach(AnnotationTool.allCases) { tool in
                    Label(tool.rawValue, systemImage: tool.symbolName).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 440)

            Spacer()

            Button {
                document.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!document.canUndo)
            .keyboardShortcut("z", modifiers: .command)

            Button("Redo") { document.redo() }
                .disabled(!document.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            Button("Delete") { document.deleteSelected() }
                .disabled(document.selectedMark == nil)

            Button {
                document.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(document.annotations.isEmpty)

            Button {
                document.expandCanvas()
            } label: {
                Label("Expand Canvas", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .disabled(document.canvasPadding >= 360)
        }
        .padding(14)
    }

    private func styleBinding<Value>(_ key: WritableKeyPath<AnnotationStyle, Value>) -> Binding<Value> {
        Binding(get: { document.style[keyPath: key] }, set: { value in
            var style = document.style; style[keyPath: key] = value; document.applyStyle(style)
        })
    }

    private var editingText: Bool {
        if document.selectedTool == .text { return true }
        if case .text = document.selectedMark?.kind { return true }
        return false
    }

    private var strokeApplicable: Bool {
        !editingText && document.selectedTool != .highlight && document.selectedMark?.kind != .highlight
    }

    private var styleBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Picker("Color", selection: styleBinding(\.color)) {
                    ForEach(AnnotationColor.allCases) { color in Text(color.rawValue).tag(color) }
                }.frame(width: 150)
                Picker("Stroke", selection: styleBinding(\.width)) {
                    Text("Thin").tag(CGFloat(3)); Text("Medium").tag(CGFloat(6)); Text("Thick").tag(CGFloat(12))
                }.frame(width: 180).disabled(!strokeApplicable)
                Toggle("Dashed", isOn: styleBinding(\.dashed))
                    .disabled(!strokeApplicable)
                Spacer()
                Text(document.selectedMark == nil ? "Style for new marks" : "Style for selected mark")
                    .foregroundStyle(.secondary)
            }
            if editingText {
                HStack {
                    TextField("Text to place", text: $document.textDraft)
                        .textFieldStyle(.roundedBorder)
                    Stepper("Size \(Int(document.style.fontSize))", value: styleBinding(\.fontSize), in: 12...144, step: 4)
                        .frame(width: 150)
                    Toggle("Bold", isOn: styleBinding(\.bold))
                    if document.selectedMark != nil {
                        Button("Apply Text") { document.updateText() }
                    }
                }
            }
            Text("Select a mark to move it. Drag corner handles to resize; drag an arrow’s middle handle to curve it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.bottom, 10)
        .onChange(of: document.selectedTool) { _, tool in
            if tool != .select {
                document.select(nil)
                if tool == .highlight { var style = document.style; style.color = .yellow; document.applyStyle(style) }
            }
        }
    }

    private var descriptionArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Describe the requested change (optional)")
                .font(.headline)
            TextEditor(text: $document.descriptionText)
                .font(.body)
                .frame(height: 62)
                .padding(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
            Text(document.statusMessage)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button("Add to Collection") {
                if let image = document.renderedImage(), collection.add(image) {
                    closeWindow()
                } else {
                    document.statusMessage = collection.message
                }
            }

            Button("Close") {
                closeWindow()
            }

            Button {
                savePNG()
            } label: {
                Label(
                    screenshotManager.copyPathMode ? "Save & Copy Path" : "Save PNG",
                    systemImage: "square.and.arrow.down"
                )
            }

            Button {
                if document.copyToClipboard() {
                    closeWindow()
                }
            } label: {
                Label("Copy & Close", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(14)
    }

    private func savePNG() {
        let suggestedURL = screenshotManager.suggestedSaveURL()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.directoryURL = suggestedURL.deletingLastPathComponent()
        panel.nameFieldStringValue = suggestedURL.lastPathComponent

        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = document.save(to: url, copyPath: screenshotManager.copyPathMode)
    }
}

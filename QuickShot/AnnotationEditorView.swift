//
//  AnnotationEditorView.swift
//  QuickShot
//

import SwiftUI

struct AnnotationEditorView: View {
    @ObservedObject var document: AnnotationDocument
    let finishTitle: String
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { geometry in
                let zoom = fitZoom(in: geometry.size)
                ScrollView([.horizontal, .vertical]) {
                    AnnotationCanvasView(document: document, zoom: zoom)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                        .padding(20)
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                }
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            descriptionBar
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Tool", selection: $document.tool) {
                ForEach(AnnotationTool.allCases) { tool in
                    Image(systemName: tool.symbolName)
                        .help(tool.help)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            .help("Select (V), Rectangle (R), Arrow (A), Text (T)")

            Divider().frame(height: 20)

            Button {
                document.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!document.canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo (⌘Z)")

            Button {
                document.deleteSelected()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(document.selectedID == nil)
            .help("Delete selected (⌫)")

            Button("Clear") {
                document.clearAll()
            }
            .disabled(document.annotations.isEmpty)
            .help("Remove all marks")

            Spacer()

            HStack(spacing: 6) {
                Text("Expand canvas")
                Stepper(value: $document.margin, in: 0...400, step: 20) {
                    Text("\(Int(document.margin)) pt")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .help("Adds white space around the screenshot so you can draw or write outside it")

            Spacer()

            Button("Cancel", action: onCancel)
                .keyboardShortcut("w", modifiers: .command)
                .help("Discard (⌘W)")

            Button(finishTitle, action: onFinish)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .help("\(finishTitle) (⌘↩)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var descriptionBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Describe what you want — this is added below the screenshot")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Drag to draw · Click a mark to select · ⌫ deletes · Double-click text to edit")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            TextEditor(text: $document.descriptionText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 72)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                )
        }
        .padding(12)
    }

    private func fitZoom(in available: CGSize) -> CGFloat {
        let size = document.canvasSize
        guard size.width > 0, size.height > 0 else { return 1 }
        let padding: CGFloat = 40
        let zoomX = (available.width - padding) / size.width
        let zoomY = (available.height - padding) / size.height
        return max(0.05, min(1, zoomX, zoomY))
    }
}

/// The interactive canvas: draws the document at `zoom` and turns mouse/keyboard input into edits.
struct AnnotationCanvasView: View {
    @ObservedObject var document: AnnotationDocument
    let zoom: CGFloat

    private struct DragSession {
        let snapshot: [Annotation]
        let startPoint: CGPoint
        var lastPoint: CGPoint
        var draftID: UUID?
        var movingID: UUID?
        var moved = false
    }

    @State private var session: DragSession?
    @FocusState private var canvasFocused: Bool
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        let size = document.canvasSize
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                context.scaleBy(x: zoom, y: zoom)
                document.draw(in: &context, showSelection: true)
            }
            .frame(width: size.width * zoom, height: size.height * zoom)
            .gesture(dragGesture)
            .simultaneousGesture(doubleClickGesture)
            .focusable()
            .focusEffectDisabled()
            .focused($canvasFocused)
            .onKeyPress(.delete) { deleteSelected() }
            .onKeyPress(.deleteForward) { deleteSelected() }
            .onKeyPress(.escape) {
                document.selectedID = nil
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "vrat"), phases: .down) { press in
                guard press.modifiers.isEmpty else { return .ignored }
                switch press.characters {
                case "v": document.tool = .select
                case "r": document.tool = .rectangle
                case "a": document.tool = .arrow
                case "t": document.tool = .text
                default: return .ignored
                }
                return .handled
            }

            if let id = document.editingTextID, let editing = document.annotation(with: id) {
                textField(for: id)
                    .offset(x: (editing.start.x + document.margin) * zoom,
                            y: (editing.start.y + document.margin) * zoom)
            }
        }
        .frame(width: size.width * zoom, height: size.height * zoom)
        .onAppear { canvasFocused = true }
    }

    private func textField(for id: UUID) -> some View {
        let binding = Binding<String>(
            get: { document.annotation(with: id)?.text ?? "" },
            set: { newValue in
                if let idx = document.index(of: id) {
                    document.annotations[idx].text = newValue
                }
            }
        )
        return TextField("Type text", text: binding)
            .textFieldStyle(.plain)
            .font(.system(size: AnnotationStyle.textFontSize * zoom, weight: .semibold))
            .foregroundStyle(AnnotationStyle.red)
            .fixedSize()
            .frame(minWidth: 120, alignment: .leading)
            .focused($textFieldFocused)
            .onSubmit {
                document.finishTextEditing()
                canvasFocused = true
            }
            .onKeyPress(.escape) {
                document.finishTextEditing(cancel: true)
                canvasFocused = true
                return .handled
            }
            .onAppear {
                DispatchQueue.main.async { textFieldFocused = true }
            }
            .onChange(of: textFieldFocused) { _, focused in
                if !focused, document.editingTextID == id {
                    document.finishTextEditing()
                }
            }
    }

    // MARK: - Input

    private func imagePoint(_ location: CGPoint) -> CGPoint {
        CGPoint(x: location.x / zoom - document.margin, y: location.y / zoom - document.margin)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = imagePoint(value.location)
                if session == nil {
                    beginDrag(at: point)
                } else {
                    updateDrag(to: point)
                }
            }
            .onEnded { value in
                let point = imagePoint(value.location)
                updateDrag(to: point)
                endDrag(at: point)
            }
    }

    private var doubleClickGesture: some Gesture {
        SpatialTapGesture(count: 2, coordinateSpace: .local)
            .onEnded { value in
                guard document.tool == .select else { return }
                let point = imagePoint(value.location)
                if let hit = document.hitTest(point), document.annotation(with: hit)?.kind == .text {
                    document.beginTextEditing(id: hit)
                }
            }
    }

    private func beginDrag(at point: CGPoint) {
        canvasFocused = true
        if document.editingTextID != nil {
            document.finishTextEditing()
        }

        var newSession = DragSession(snapshot: document.annotations, startPoint: point, lastPoint: point)
        switch document.tool {
        case .select:
            let hit = document.hitTest(point)
            document.selectedID = hit
            newSession.movingID = hit
        case .rectangle, .arrow:
            let annotation = Annotation(kind: document.tool == .rectangle ? .rectangle : .arrow,
                                        start: point, end: point)
            document.annotations.append(annotation)
            document.selectedID = nil
            newSession.draftID = annotation.id
        case .text:
            break
        }
        session = newSession
    }

    private func updateDrag(to point: CGPoint) {
        guard var current = session else { return }
        if let id = current.draftID, let idx = document.index(of: id) {
            document.annotations[idx].end = point
            current.moved = true
        } else if let id = current.movingID, let idx = document.index(of: id) {
            document.annotations[idx].move(byX: point.x - current.lastPoint.x, y: point.y - current.lastPoint.y)
            current.moved = true
        }
        current.lastPoint = point
        session = current
    }

    private func endDrag(at point: CGPoint) {
        guard let current = session else { return }
        session = nil

        switch document.tool {
        case .rectangle, .arrow:
            guard let id = current.draftID, let idx = document.index(of: id) else { return }
            let drawn = document.annotations[idx]
            let extent = drawn.rect.size
            let tooSmall = drawn.kind == .rectangle
                ? (extent.width < 4 && extent.height < 4)
                : hypot(extent.width, extent.height) < 4
            if tooSmall {
                document.annotations.remove(at: idx)
            } else {
                document.pushUndo(current.snapshot)
                document.selectedID = id
            }
        case .select:
            if current.moved, current.movingID != nil {
                document.pushUndo(current.snapshot)
            }
        case .text:
            if let hit = document.hitTest(current.startPoint), document.annotation(with: hit)?.kind == .text {
                document.beginTextEditing(id: hit)
            } else {
                document.beginTextEditing(at: current.startPoint)
            }
        }
    }

    private func deleteSelected() -> KeyPress.Result {
        guard document.selectedID != nil else { return .ignored }
        document.deleteSelected()
        return .handled
    }
}

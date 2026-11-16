import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import MandalaCore

struct CellEditor: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.words) private var words
    @State private var action: ActionRequest?
    @State private var links = false
    @State private var selection = ""

    var body: some View {
        if let draft = workspace.draft {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(words("cell.body")).font(.headline)
                    Spacer()
                    CellColorMenu(color: draft.cell.color) { color in
                        workspace.changeDraft { $0.cell.color = color }
                    }
                }
                PlainEditor(label: words("cell.body"), text: bodyText, selection: { selection = $0 })
                    .frame(height: 235)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.45)) }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(draft.cell.actions ?? [], id: \.id) { item in
                        HStack {
                            Button(item.title) { action = ActionRequest(item: item) }
                                .accessibilityIdentifier("edit-action")
                            Spacer()
                            Button(role: .destructive) {
                                workspace.changeDraft {
                                    let values = ($0.cell.actions ?? []).filter { $0.id != item.id }
                                    $0.cell.actions = values.isEmpty ? nil : values
                                }
                            } label: {
                                Image(systemName: "minus.circle").accessibilityLabel(words("remove"))
                            }.buttonStyle(.borderless)
                        }
                    }
                    Button(words("action.add")) { action = ActionRequest() }
                        .buttonStyle(.bordered).accessibilityIdentifier("add-action")
                    if !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(words("action.fromSelection")) {
                            action = ActionRequest(selection: selection)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(words("resource.heading")).font(.headline)
                    ForEach(Array((draft.cell.resources ?? []).enumerated()), id: \.offset) { index, resource in
                        HStack {
                            ResourceLabel(resource: resource)
                                .accessibilityIdentifier("editor-resource")
                            Spacer()
                            Button(role: .destructive) {
                                workspace.changeDraft {
                                    var values = $0.cell.resources ?? []
                                    values.remove(at: index)
                                    $0.cell.resources = values.isEmpty ? nil : values
                                }
                            } label: {
                                Image(systemName: "minus.circle").accessibilityLabel(words("remove"))
                            }.buttonStyle(.borderless)
                        }
                    }
                    MediaImportControls(draftID: draft.id)
                    Button(words("resource.addLink")) { links = true }
                        .buttonStyle(.bordered)
                }
                SaveIndicator()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(draft.id)
            .onChange(of: draft.id) { _, _ in selection = "" }
            .sheet(isPresented: $links) { LinkEditor() }
            .sheet(item: $action) { ActionEditor(request: $0) }
        }
    }

    private var bodyText: Binding<String> {
        Binding(get: { workspace.draft?.cell.body ?? "" },
                set: { text in workspace.changeDraft { $0.cell.body = text } })
    }
}

private struct PlainEditor: UIViewRepresentable {
    let label: String
    @Binding var text: String
    let selection: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 11, left: 10, bottom: 11, right: 10)
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.editor = self
        view.accessibilityIdentifier = "cell-body"
        view.accessibilityLabel = label
        if view.markedTextRange == nil, !(view.text ?? "").utf8.elementsEqual(text.utf8) {
            let previous = view.selectedRange
            view.text = text
            if NSMaxRange(previous) <= (text as NSString).length { view.selectedRange = previous }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var editor: PlainEditor
        init(_ editor: PlainEditor) { self.editor = editor }

        func textViewDidChange(_ view: UITextView) {
            guard view.markedTextRange == nil else { return }
            editor.text = view.text ?? ""
        }

        func textViewDidEndEditing(_ view: UITextView) {
            let value = view.text ?? ""
            if view.markedTextRange == nil, !value.utf8.elementsEqual(editor.text.utf8) { editor.text = value }
        }

        func textViewDidChangeSelection(_ view: UITextView) {
            guard view.markedTextRange == nil,
                  let range = Range(view.selectedRange, in: view.text ?? "") else { return }
            let selected = String((view.text ?? "")[range])
            DispatchQueue.main.async { [weak self] in self?.editor.selection(selected) }
        }

    }
}

private struct LinkEditor: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.words) private var words
    @Environment(\.dismiss) private var dismiss
    @State private var kind = CellResource.Kind.link
    @State private var title = ""
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker(words("resource.kind"), selection: $kind) {
                    ForEach(CellResource.Kind.allCases, id: \.self) { kind in
                        Text(words("resource." + kind.rawValue)).tag(kind)
                    }
                }
                TextField(words("resource.name"), text: $title)
                TextField(words("resource.url"), text: $url)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .navigationTitle(words("resource.addLink"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(words("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(words("add")) {
                        workspace.changeDraft {
                            $0.cell.resources = ($0.cell.resources ?? []) +
                                [CellResource(kind: kind, url: url, title: title.isEmpty ? nil : title)]
                        }
                        dismiss()
                    }.disabled(!CellResource.isWebURL(url))
                }
            }
        }
    }
}

private struct ActionRequest: Identifiable {
    let id = UUID()
    var item: CellAction?
    var selection = ""
}

private struct ActionEditor: View {
    let request: ActionRequest
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.words) private var words
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String
    @State private var dueEnabled: Bool
    @State private var timed: Bool
    @State private var date: String
    @State private var time: String
    @State private var timeZone: String
    @State private var savedActionID: String?
    @State private var reminderWorking = false

    init(request: ActionRequest) {
        self.request = request
        let selected = request.selection.trimmingCharacters(in: .whitespacesAndNewlines)
        _title = State(initialValue: request.item?.title ?? selected.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
        _notes = State(initialValue: request.item?.notes ?? "")
        let due = request.item?.due
        _dueEnabled = State(initialValue: due != nil)
        _timed = State(initialValue: due?.time != nil)
        let today = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: .now)
        _date = State(initialValue: due?.date ?? String(format: "%04d-%02d-%02d", today.year ?? 2026, today.month ?? 1, today.day ?? 1))
        _time = State(initialValue: due?.time ?? "09:00")
        let zone = TimeZone.current.identifier
        _timeZone = State(initialValue: due?.timeZone ?? (TimeZone.knownTimeZoneIdentifiers.contains(zone) ? zone : "Etc/UTC"))
        _savedActionID = State(initialValue: request.item?.id)
    }

    private var due: ActionDue? {
        dueEnabled ? ActionDue(date: date, time: timed ? time : nil, timeZone: timed ? timeZone : nil) : nil
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (due == nil || (try? due?.components()) != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(words("action.name"), text: $title)
                        .accessibilityIdentifier("action-name")
                    TextField(words("action.notes"), text: $notes, axis: .vertical)
                    Toggle(words("action.due"), isOn: $dueEnabled)
                    if dueEnabled {
                        TextField("YYYY-MM-DD", text: $date).keyboardType(.numbersAndPunctuation)
                            .accessibilityLabel(words("action.date"))
                        Toggle(words("action.timed"), isOn: $timed)
                        if timed {
                            TextField("HH:mm", text: $time).keyboardType(.numbersAndPunctuation)
                                .accessibilityLabel(words("action.time"))
                            Picker(words("action.zone"), selection: $timeZone) {
                                ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                            }
                        }
                        if let due, (try? due.components()) == nil {
                            Text(words("action.invalidDue")).font(.footnote).foregroundStyle(.red)
                        }
                    }
                }
                .disabled(reminderWorking)
                ReminderControls(actionID: savedActionID, isReady: isValid, working: $reminderWorking,
                                 prepare: prepareReminder)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(words(request.item == nil ? "action.add" : "action.edit"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(words("cancel")) { dismiss() }.disabled(reminderWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(words("done")) { if saveAction() != nil { dismiss() } }
                        .accessibilityIdentifier("confirm-action")
                        .disabled(!isValid || reminderWorking)
                }
            }
            .interactiveDismissDisabled(reminderWorking)
        }
    }

    private func prepareReminder() async -> ReminderRequest? {
        guard let draftID = workspace.draft?.id, let action = saveAction(),
              await workspace.flush(), workspace.draft?.id == draftID,
              let cellID = workspace.draft?.cellID else { return nil }
        return ReminderRequest(cellID: cellID, action: action)
    }

    private func saveAction() -> CellAction? {
        guard workspace.draft != nil, isValid else { return nil }
        do {
            let existing = workspace.project?.actionIDs ?? []
            let draft = Set((workspace.draft?.cell.actions ?? []).map(\.id))
            let id = try savedActionID ?? ShortID.generate(excluding: existing.union(draft))
            let item = CellAction(id: id, title: title, notes: notes.isEmpty ? nil : notes, due: due)
            workspace.changeDraft {
                var actions = $0.cell.actions ?? []
                if let index = actions.firstIndex(where: { $0.id == id }) { actions[index] = item }
                else { actions.append(item) }
                $0.cell.actions = actions
            }
            savedActionID = id
            return item
        } catch {
            workspace.error = error
            return nil
        }
    }
}

struct CellDetail: View {
    let id: String
    let onEdit: () -> Void
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.words) private var words
    @Environment(\.openURL) private var openURL
    @State private var reminder: ReminderRequest?
    @State private var preview: ResourcePreview?

    var body: some View {
        if let cell = workspace.project?.cells[id] {
            let resources = Array((cell.resources ?? []).enumerated())
            let inlineImages = cell.previewLine == nil ? resources.compactMap { index, resource in
                cellImage(resource).map { (index, resource, $0) }
            } : []
            let inlineIndices = Set(inlineImages.map { $0.0 })
            let remainingResources = resources.filter { !inlineIndices.contains($0.offset) }
            let cover = workspace.legacyCover(for: id).flatMap { UIImage(data: $0) }

            VStack(alignment: .leading, spacing: 14) {
                Button(words("cell.edit"), action: onEdit)
                    .buttonStyle(.bordered).accessibilityIdentifier("edit-cell")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if cell.previewText != nil || !inlineImages.isEmpty || cover != nil {
                    VStack(alignment: .leading, spacing: 14) {
                        if let cover, cell.previewLine == nil { coverView(cover) }
                        ForEach(inlineImages, id: \.0) { _, resource, image in
                            Button { open(resource) } label: {
                                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 320)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(resource.title ?? resource.caption ?? words("resource.image"))
                            .accessibilityIdentifier("cell-detail-inline-image")
                            if let caption = resource.caption { Text(verbatim: caption).font(.footnote) }
                        }
                        if cell.previewLine != nil {
                            Text(verbatim: cell.body)
                                .textSelection(.enabled).accessibilityIdentifier("cell-detail-body")
                        }
                        ForEach(cell.actions ?? [], id: \.id) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: item.title)
                                    .fontWeight(.semibold).textSelection(.enabled)
                                    .accessibilityIdentifier("cell-detail-action")
                                if let notes = item.notes { Text(verbatim: notes).textSelection(.enabled) }
                                if let due = item.due {
                                    Text([due.date, due.time, due.timeZone].compactMap { $0 }.joined(separator: " "))
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                let created = workspace.project?.reminderLinks[item.id]?.state == .created
                                Button(words(created ? "reminder.openSystem" : "reminder.open")) {
                                    if created {
                                        Task { await workspace.openSystemReminder(for: item, cellID: id, words: words) }
                                    } else {
                                        reminder = ReminderRequest(cellID: id, action: item)
                                    }
                                }.buttonStyle(.bordered)
                            }.id(item.id)
                        }
                    }
                }
                if let cover, cell.previewLine != nil { coverView(cover) }
                if !remainingResources.isEmpty {
                    Text(words("resource.heading")).font(.headline)
                    ForEach(remainingResources, id: \.offset) { _, resource in
                        Button { open(resource) } label: {
                            VStack(alignment: .leading) {
                                if let image = cellImage(resource) {
                                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).accessibilityHidden(true)
                                }
                                ResourceLabel(resource: resource)
                            }
                        }.buttonStyle(.plain)
                        if let caption = resource.caption { Text(verbatim: caption).font(.footnote) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(item: $reminder) { ReminderScreen(request: $0) }
            .sheet(item: $preview, onDismiss: { preview = nil }) { item in
                NavigationStack {
                    QuickLook(url: item.url)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(words("done")) { preview = nil } } }
                }.onDisappear { try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent()) }
            }
        }
    }

    private func coverView(_ cover: UIImage) -> some View {
        Image(uiImage: cover).resizable().scaledToFit().frame(maxHeight: 240)
            .accessibilityLabel(words("project.cover"))
    }

    private func cellImage(_ resource: CellResource) -> UIImage? {
        guard resource.kind == .image, let data = workspace.asset(at: resource.path) else { return nil }
        return UIImage(data: data)
    }

    private func open(_ resource: CellResource) {
        if let link = resource.url, let url = URL(string: link) { openURL(url); return }
        guard let path = resource.path, let bytes = workspace.asset(at: path) else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let generatedName = (path as NSString).lastPathComponent
        let original = resource.originalFilename
        let name = original.flatMap { candidate in
            candidate == (candidate as NSString).lastPathComponent && !["", ".", ".."].contains(candidate) ? candidate : nil
        } ?? generatedName
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            try bytes.write(to: url, options: .atomic)
            preview = ResourcePreview(url: url)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            workspace.error = error
        }
    }
}

private struct ResourceLabel: View {
    let resource: CellResource
    @Environment(\.words) private var words

    var body: some View {
        Label(resource.title ?? resource.originalFilename ?? resource.url ?? words("resource." + resource.kind.rawValue),
              systemImage: resource.url == nil ? "paperclip" : "link")
            .lineLimit(2)
    }
}

private struct ResourcePreview: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct QuickLook: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}

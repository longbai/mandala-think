import ImageIO
import SwiftUI
import UIKit
import MandalaCore

struct BoardScreen: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.words) private var words
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var horizontalSize
    @ScaledMetric(relativeTo: .subheadline) private var compactTileHeight: CGFloat = 100
    @State private var detail = false
    @State private var editAfterDetail: String?
    @State private var compactEdit = false
    @State private var overview = false
    @State private var zoomReset = 0
    @State private var zoomInteraction = BoardZoomInteraction()
    @AppStorage("mandala.board-layout") private var layout = BoardLayout.three
    @State private var compatibility = false
    @State private var moving: MoveRequest?

    private enum BoardLayout: String { case three, nine, list }

    var body: some View {
        GeometryReader { geometry in
            let paneWidth = min(geometry.size.width, 1180) - 62
            let minimumBoard: CGFloat = 300
            let minimumDetail: CGFloat = 240
            let wide = horizontalSize == .regular &&
                paneWidth >= minimumBoard + minimumDetail && !typeSize.isAccessibilitySize
            let boardWidth = max(minimumBoard, min(paneWidth * 0.56, paneWidth - minimumDetail))
            Group {
                if layout == .nine {
                    VStack(spacing: 8) {
                        header
                        expandedGrid
                    }
                    .padding(20)
                    .frame(maxWidth: 1180)
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            header
                            if wide {
                                HStack(alignment: .top, spacing: 22) {
                                    grid(wide: true)
                                        .frame(width: workspace.draft != nil || workspace.selectedID != nil ? boardWidth : nil)
                                    if workspace.draft != nil {
                                        VStack(alignment: .leading, spacing: 12) {
                                            Button(words("done")) { Task { await workspace.finishEditor() } }
                                                .accessibilityIdentifier("finish-sidebar-editing")
                                            CellEditor()
                                        }
                                    } else if let id = workspace.selectedID {
                                        CellDetail(id: id, onEdit: { edit(id: id, wide: true) })
                                    }
                                }
                            } else {
                                grid(wide: false)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: 1180)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .onChange(of: wide) { wasWide, isWide in
                guard layout != .nine else { return }
                if wasWide && !isWide {
                    if workspace.draft != nil { compactEdit = true }
                    else if workspace.selectedID != nil { detail = true }
                }
                if !wasWide && isWide {
                    compactEdit = false
                    if workspace.reminderDestination == nil { detail = false }
                }
            }
        }
        .toolbar {
            if let parent = workspace.path.dropLast().last {
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await workspace.navigate(to: parent) } } label: {
                        Label(words("grid.up"), systemImage: "arrow.up.left").labelStyle(.iconOnly)
                    }.accessibilityIdentifier("level-up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { overview = true } label: { Label(words("grid.overview"), systemImage: "list.bullet.indent") }
                    Section(words("export")) {
                        Button(words("export.share")) { Task { await workspace.export(legacy: false) } }
                        Button(words("export.backup")) { Task { await workspace.export(legacy: false, backup: true) } }
                        Button(words("export.legacy")) {
                            Task { if await workspace.flush() { compatibility = true } }
                        }
                    }
                } label: { Label(words("grid.tools"), systemImage: "ellipsis.circle") }
                .accessibilityIdentifier("board-tools")
            }
        }
        .onChange(of: workspace.reminderDestination, initial: true) { _, destination in
            guard destination != nil else { return }
            if compactEdit { compactEdit = false }
            else { detail = true }
        }
        .sheet(isPresented: $detail, onDismiss: finishDetail) {
            if let id = workspace.selectedID, workspace.project?.cells[id] != nil {
                let destination = workspace.reminderDestination
                let actionID = destination?.cellID == id ? destination?.actionID : nil
                NavigationStack {
                    ScrollViewReader { scroll in
                        ScrollView {
                            CellDetail(id: id).padding(18)
                        }
                        .task(id: actionID) {
                            guard let actionID else { return }
                            await Task.yield()
                            scroll.scrollTo(actionID, anchor: .top)
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(words("done")) { detail = false }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                editAfterDetail = id
                                detail = false
                            } label: {
                                Label(words("cell.edit"), systemImage: "pencil")
                                    .labelStyle(.iconOnly)
                            }
                            .accessibilityIdentifier("edit-cell")
                        }
                    }
                }
                .presentationDetents(actionID == nil ? [.medium, .large] : [.large])
            }
        }
        .fullScreenCover(isPresented: $compactEdit, onDismiss: {
            if workspace.reminderDestination != nil { detail = true }
        }) {
            NavigationStack {
                ScrollView { CellEditor().padding(18) }
                    .scrollDismissesKeyboard(.interactively)
                    .background(Color.mandalaPaper)
                    .navigationTitle(words("cell.edit"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(words("done")) {
                                Task { if await workspace.finishEditor() { compactEdit = false } }
                            }.accessibilityIdentifier("finish-editing")
                        }
                    }
            }
        }
        .sheet(isPresented: $overview) { overviewSheet }
        .sheet(isPresented: $compatibility) { LegacyExportScreen() }
        .sheet(item: $moving) { MoveScreen(request: $0) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if workspace.path.count > 2 {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(workspace.path.dropLast().enumerated()), id: \.element) { index, id in
                            if index > 0 { Image(systemName: "chevron.right").font(.caption2).accessibilityHidden(true) }
                            Button(index == 0 ? words("grid.root") : cellPreview(id)) {
                                Task { await workspace.navigate(to: id) }
                            }
                        }
                    }.font(.subheadline)
                }.scrollIndicators(.hidden)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    layoutControls
                    Spacer(minLength: 8)
                    SaveIndicator().fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    layoutControls
                    SaveIndicator()
                }
            }
            .font(.footnote)
        }
        .padding(.horizontal, 2)
    }

    private var layoutControls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                layoutButton(.three, identifier: "board-size-three") { Text(verbatim: "3×3") }
                layoutButton(.nine, identifier: "board-size-nine") { Text(verbatim: "9×9") }
                layoutButton(.list, identifier: "board-size-list") {
                    Label(words("list.show"), systemImage: "list.bullet").labelStyle(.iconOnly)
                }
            }
            .padding(.horizontal, 4)
            .background(Color.mandalaCard, in: Capsule())
            if layout == .nine {
                Button { zoomReset += 1 } label: {
                    Label(words("grid.fit"), systemImage: "arrow.down.right.and.arrow.up.left")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                        .background(Color.mandalaCard, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.mandalaInk)
                .accessibilityIdentifier("board-fit")
            }
        }
    }

    private func layoutButton<Label: View>(_ mode: BoardLayout, identifier: String,
                                          @ViewBuilder label: () -> Label) -> some View {
        let selected = layout == mode
        return Button {
            layout = mode
        } label: {
            label()
                .fontWeight(.semibold)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color(uiColor: .systemBackground) : Color.mandalaInk)
                .background(selected ? Color.mandalaInk : Color.clear, in: Capsule())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private func grid(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if layout == .list || typeSize.isAccessibilitySize {
                VStack(spacing: 6) {
                    ForEach(Array(Slot.layout.enumerated()), id: \.offset) { _, position in
                        tile(position, wide: wide, asList: true)
                    }
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(Array(Slot.layout.enumerated()), id: \.offset) { _, position in tile(position, wide: wide) }
                }
            }
            if let extras = workspace.currentCell?.legacyChildren, !extras.isEmpty {
                Text(words("grid.extra")).font(.headline)
                ForEach(extras.keys.sorted(), id: \.self) { key in
                    if let id = extras[key] {
                        HStack {
                            Button(cellPreview(id)) { inspect(id: id, wide: wide) }
                            Spacer()
                            Button { Task { await workspace.navigate(to: id) } } label: {
                                Image(systemName: "arrow.down.right.square")
                            }.accessibilityLabel(words("grid.expand"))
                        }
                        .padding(12)
                        .modifier(CellSurface(color: workspace.project?.cells[id]?.color, center: false,
                                              selected: workspace.selectedID == id, radius: 12))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var expandedGrid: some View {
        let side: CGFloat = typeSize.isAccessibilitySize ? 80 : 58
        let blockSide = side * 3 + 14
        let boardSide = blockSide * 3 + 16
        return ZoomableBoard(side: boardSide, resetToken: zoomReset, interaction: zoomInteraction) {
            VStack(spacing: 8) {
                ForEach(0..<3) { row in
                    HStack(spacing: 8) {
                        ForEach(0..<3) { column in
                            let block = row * 3 + column
                            expandedBlock(block, side: side)
                                .frame(width: blockSide, height: blockSide)
                                .background(block == 4 ? Color.mandalaInk.opacity(0.18) : Color.primary.opacity(0.07),
                                            in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
            .frame(width: boardSide, height: boardSide)
            .environmentObject(workspace)
            .environment(\.words, words)
            .environment(\.dynamicTypeSize, typeSize)
        }
        .id(workspace.currentID.map { "\($0)-\(side)" })
    }

    private func expandedBlock(_ block: Int, side: CGFloat) -> some View {
        let outerSlot = Slot.layout[block]
        let parent = outerSlot == nil ? workspace.currentID : outerSlot.flatMap { workspace.currentCell?.child(at: $0) }
        return VStack(spacing: 3) {
            ForEach(0..<3) { row in
                HStack(spacing: 3) {
                    ForEach(0..<3) { column in
                        let index = row * 3 + column
                        let position = Slot.layout[index]
                        let id = if let position {
                            parent.flatMap { workspace.project?.cells[$0]?.child(at: position) }
                        } else {
                            parent
                        }
                        let parentID = position == nil ? workspace.currentID : parent
                        let insertion = position ?? outerSlot
                        expandedTile(id: id, parent: parentID, insertion: insertion, outer: outerSlot,
                                     position: position, at: "expanded-\(block)-\(index)", side: side)
                    }
                }
            }
        }
        .padding(4)
    }

    private func expandedTile(id: String?, parent: String?, insertion: Slot?, outer: Slot?,
                              position: Slot?, at identifier: String, side: CGFloat) -> some View {
        let cell = id.flatMap { workspace.project?.cells[$0] }
        let thumbnail = id.flatMap(imagePreview)
        let canAdd = parent != nil && insertion != nil
        let canExpand = id != nil && id != workspace.currentID
        let firstAction = cell?.actions?.first
        let directReminder = cell?.previewLine == nil && thumbnail == nil &&
            firstAction.map { workspace.project?.reminderLinks[$0.id]?.state == .created } == true
        let positionName = slotName(outer) + ", " + slotName(position)
        return Button {
            guard zoomInteraction.allowsSelection else { return }
            if let id, let firstAction, directReminder {
                Task { await workspace.openSystemReminder(for: firstAction, cellID: id, words: words) }
            } else if let id {
                inspect(id: id, wide: false)
            } else if let parent, let insertion {
                Task {
                    await workspace.beginEmpty(slot: insertion, in: parent)
                    compactEdit = workspace.draft != nil
                }
            }
        } label: {
            Group {
                if let thumbnail {
                    filledPhoto(thumbnail, height: side, action: nil)
                } else if let preview = cell?.previewText {
                    Text(verbatim: preview)
                        .font(.caption2)
                        .multilineTextAlignment(.center).lineLimit(3)
                        .padding(4)
                        .padding(.top, canExpand ? 17 : 0)
                } else if id == nil && canAdd {
                    Image(systemName: "plus").font(.caption).foregroundStyle(Color.mandalaInk)
                } else {
                    Color.clear
                }
            }
            .frame(width: side, height: side)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(id == nil && !canAdd)
        .accessibilityAddTraits(id != nil && id == workspace.selectedID ? .isSelected : [])
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(id.map { positionName + ", " + cellPreview($0) } ??
                            words.described("cell.addAt", positionName))
        .contextMenu {
            if let id {
                Button(words("cell.view")) { inspect(id: id, wide: false) }
                Button(words("cell.edit")) { edit(id: id, wide: false) }
                if canExpand {
                    Button(words("grid.expand")) { Task { await workspace.navigate(to: id) } }
                    Button(words("cell.move")) { moving = MoveRequest(id: id, parent: parent) }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .modifier(CellSurface(color: cell?.color, center: position == nil,
                              selected: id != nil && id == workspace.selectedID, radius: 7, empty: id == nil))
        .overlay(alignment: .topTrailing) {
            if canExpand, let id {
                Button {
                    guard zoomInteraction.allowsSelection else { return }
                    Task { await workspace.navigate(to: id) }
                } label: {
                    Image(systemName: "arrow.down.right.square")
                        .font(.caption2)
                        .foregroundStyle(thumbnail == nil ? Color.mandalaInk : .white)
                        .padding(4)
                        .background(thumbnail == nil ? Color.clear : .black.opacity(0.65), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(words.described("grid.expandNamed", cellPreview(id)))
                .accessibilityIdentifier(identifier + "-expand")
            }
        }
    }

    private func slotName(_ position: Slot?) -> String {
        words(position.map { "slot." + $0.rawValue } ?? "slot.center")
    }

    private func tile(_ position: Slot?, wide: Bool, asList: Bool = false) -> some View {
        let id = position == nil ? workspace.currentID : position.flatMap { workspace.currentCell?.child(at: $0) }
        let positionName = words(position.map { "slot." + $0.rawValue } ?? "slot.center")
        let name = id.map(cellPreview)
        let cell = id.flatMap { workspace.project?.cells[$0] }
        let textPreview = cell?.previewText
        let thumbnail = id.flatMap(imagePreview)
        let photoFillsTile = thumbnail != nil && !asList
        let tileHeight = compactTileHeight + (wide ? 12 : 0)
        let firstAction = cell?.actions?.first
        let actionPreview = firstAction?.title
        let linkedAction = cell?.actions?.first { workspace.project?.reminderLinks[$0.id]?.state == .created }
        let actionIsPreview = linkedAction != nil && linkedAction?.id == firstAction?.id &&
            cell?.previewLine == nil && thumbnail == nil
        let hint = position.flatMap(templateHint)
        let centerHint = centerPrompt(position)
        let selected = id != nil && id == workspace.selectedID
        let center = position == nil
        let hasGridExpand = !asList && id != nil && !center
        return VStack(alignment: .leading, spacing: 3) {
            if asList {
                HStack {
                    Text(verbatim: positionName).font(.caption2)
                        .foregroundStyle(center ? Color.mandalaInk : Color.secondary)
                        .accessibilityHidden(true)
                    Spacer(minLength: 2)
                    if let id, !center {
                        expandButton(id, position: position)
                    }
                }
                .frame(minHeight: 32)
            }
            Button {
                if let id, let linkedAction, actionIsPreview {
                    Task { await workspace.openSystemReminder(for: linkedAction, cellID: id, words: words) }
                } else if let id { inspect(id: id, wide: wide) }
                else if let position {
                    Task {
                        await workspace.beginEmpty(slot: position)
                        if !wide && workspace.draft != nil { compactEdit = true }
                    }
                }
            } label: {
                Group {
                    if let thumbnail, photoFillsTile {
                        filledPhoto(thumbnail, height: tileHeight, action: linkedAction == nil ? actionPreview : nil)
                    } else {
                        HStack {
                            if let thumbnail {
                                VStack(spacing: 4) {
                                    Image(uiImage: thumbnail)
                                        .resizable().scaledToFit()
                                        .frame(height: 50)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .accessibilityHidden(true)
                                    if let actionPreview, linkedAction == nil {
                                        Text(verbatim: actionPreview).font(.caption).lineLimit(1)
                                    }
                                }
                            } else if let preview = centerHint ?? textPreview ?? (asList ? name : nil) {
                                if actionIsPreview {
                                    Label { Text(verbatim: preview) } icon: { Image(systemName: "bell") }
                                        .foregroundStyle(Color.mandalaInk)
                                        .lineLimit(2)
                                } else {
                                    Text(verbatim: preview)
                                        .font(center ? .headline : .subheadline.weight(.semibold))
                                        .multilineTextAlignment(asList ? .leading : .center)
                                        .lineLimit(asList ? nil : 3)
                                }
                            } else if id == nil {
                                VStack(spacing: 5) {
                                    Image(systemName: "plus")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.mandalaInk)
                                    if let hint {
                                        Text(verbatim: hint).font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: asList ? .leading : .center)
                        .padding(.vertical, 6)
                        .padding(.top, hasGridExpand ? 24 : 0)
                        .frame(minHeight: 44, maxHeight: .infinity)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityLabel(name.map { positionName + ", " + $0 } ?? words.described("cell.addAt", positionName))
            .accessibilityIdentifier("slot-" + (position?.rawValue ?? "center"))
            .contextMenu {
                if let id {
                    if actionIsPreview {
                        Button(words("cell.view")) { inspect(id: id, wide: wide) }
                    }
                    Button(words("cell.edit")) { edit(id: id, wide: wide) }
                    if !center { Button(words("cell.move")) { moving = MoveRequest(id: id) } }
                }
            }
            if let id, let linkedAction, !actionIsPreview, !photoFillsTile {
                reminderButton(linkedAction, cellID: id, onPhoto: false)
            }
        }
        .padding(.horizontal, photoFillsTile ? 0 : 10)
        .padding(.bottom, photoFillsTile ? 0 : 6)
        .frame(minHeight: asList ? 66 : tileHeight)
        .overlay(alignment: .bottom) {
            if photoFillsTile, let id, let linkedAction {
                reminderButton(linkedAction, cellID: id, onPhoto: true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(alignment: .topTrailing) {
            if hasGridExpand, let id {
                expandButton(id, position: position, onPhoto: photoFillsTile)
            }
        }
        .modifier(CellSurface(color: cell?.color, center: center, selected: selected, radius: 15, empty: id == nil))
        .onDrag {
            guard let id, !center else { return NSItemProvider() }
            return NSItemProvider(object: ("mandala-cell:" + id) as NSString)
        }
        .dropDestination(for: String.self) { values, _ in
            guard wide, let position, let parent = workspace.currentID,
                  let value = values.first, value.hasPrefix("mandala-cell:") else { return false }
            let source = String(value.dropFirst("mandala-cell:".count))
            guard Slot.allCases.contains(where: { workspace.currentCell?.child(at: $0) == source }) else { return false }
            if id == nil { Task { await workspace.move(source, to: parent, slot: position) } }
            else { moving = MoveRequest(id: source, parent: parent, slot: position) }
            return true
        }
    }

    private func reminderButton(_ action: CellAction, cellID: String, onPhoto: Bool) -> some View {
        Button {
            Task { await workspace.openSystemReminder(for: action, cellID: cellID, words: words) }
        } label: {
            Label { Text(verbatim: action.title) } icon: { Image(systemName: "bell") }
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(onPhoto ? Color.white : Color.mandalaInk)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .background(onPhoto ? Color.black.opacity(0.65) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(words("reminder.openSystem"))
        .accessibilityIdentifier("grid-reminder-" + action.id)
    }

    private func filledPhoto(_ image: UIImage, height: CGFloat, action: String?) -> some View {
        Color.clear
            .frame(height: height)
            .overlay {
                GeometryReader { bounds in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: bounds.size.width, height: bounds.size.height)
                        .clipped()
                }
                .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomLeading) {
                if let action {
                    Text(verbatim: action)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.65))
                }
            }
    }

    private func expandButton(_ id: String, position: Slot?, onPhoto: Bool = false) -> some View {
        Button { Task { await workspace.navigate(to: id) } } label: {
            Image(systemName: "arrow.down.right.square")
                .font(.subheadline)
                .foregroundStyle(onPhoto ? Color.white : Color.mandalaInk)
                .padding(7)
                .background(onPhoto ? Color.black.opacity(0.65) : Color.clear, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(words.described("grid.expandNamed", cellPreview(id)))
        .accessibilityIdentifier("expand-" + (position?.rawValue ?? "center"))
    }

    private func centerPrompt(_ position: Slot?) -> String? {
        guard position == nil, workspace.currentID == workspace.project?.manifest.rootCellID,
              workspace.project?.manifest.template == .fiveW, workspace.currentCell?.previewText == nil,
              let id = workspace.currentID, cellPreview(id) == words("cell.noBody") else { return nil }
        return words("template.who")
    }

    private func templateHint(_ slot: Slot) -> String? {
        guard workspace.path.count == 1, let template = workspace.project?.manifest.template else { return nil }
        switch (template, slot) {
        case (.fiveW, .top): return words("template.what")
        case (.fiveW, .left): return words("template.where")
        case (.fiveW, .right): return words("template.when")
        case (.fiveW, .bottom): return words("template.why")
        case (.time, .top): return words("template.year")
        case (.time, .left): return words("template.month")
        case (.time, .right): return words("template.week")
        default: return nil
        }
    }

    private func cellPreview(_ id: String) -> String {
        guard let cell = workspace.project?.cells[id] else { return words("cell.noBody") }
        if let preview = cell.previewText { return preview }
        if cell.resources?.contains(where: { $0.kind == .image && $0.path != nil }) == true ||
            workspace.legacyCover(for: id) != nil { return words("resource.image") }
        return words("cell.noBody")
    }

    private func imagePreview(_ id: String) -> UIImage? {
        guard let cell = workspace.project?.cells[id], cell.previewLine == nil else { return nil }
        for resource in cell.resources ?? [] where resource.kind == .image {
            if let data = workspace.asset(at: resource.path), let image = thumbnail(from: data) { return image }
        }
        return workspace.legacyCover(for: id).flatMap(thumbnail(from:))
    }

    private func thumbnail(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 360
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    private func inspect(id: String, wide: Bool) {
        Task {
            await workspace.select(id)
            if !wide && workspace.draft == nil { detail = true }
        }
    }

    private func edit(id: String, wide: Bool) {
        Task {
            if await workspace.beginEdit(id: id), !wide { compactEdit = true }
        }
    }

    private func finishDetail() {
        workspace.reminderDestination = nil
        if let id = editAfterDetail {
            editAfterDetail = nil
            edit(id: id, wide: false)
        }
    }

    private var overviewSheet: some View {
        NavigationStack {
            List(outline, id: \.id) { row in
                Button {
                    Task { await workspace.navigate(to: row.id); overview = false }
                } label: {
                    Label(cellPreview(row.id), systemImage: row.depth == 0 ? "square.grid.3x3" : "arrow.turn.down.right")
                        .padding(.leading, Double(min(row.depth, 12) * 12))
                }
            }
            .navigationTitle(words("grid.overview"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(words("done")) { overview = false } } }
        }
    }

    private var outline: [(id: String, depth: Int)] {
        guard let project = workspace.project else { return [] }
        var result = [(String, Int)]()
        var pending = [(project.manifest.rootCellID, 0)]
        while let (id, depth) = pending.popLast(), let cell = project.cells[id] {
            result.append((id, depth))
            let ids = Slot.allCases.compactMap { cell.child(at: $0) } +
                (cell.legacyChildren ?? [:]).sorted(by: { $0.key < $1.key }).map(\.value)
            pending.append(contentsOf: ids.reversed().map { ($0, depth + 1) })
        }
        return result
    }
}

struct SaveIndicator: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.words) private var words

    var body: some View {
        HStack(spacing: 6) {
            switch workspace.saveState {
            case .clean:
                Text(words(workspace.waitingForSync ? "save.sync" : "save.clean")).foregroundStyle(.secondary)
            case .saving:
                ProgressView().controlSize(.small)
                Text(words("save.saving"))
            case .failed:
                Button(words("save.retry")) { Task { await workspace.flush() } }
            case .conflict:
                Button(words("save.recover")) { Task { await workspace.recoverAsCopy() } }
            }
        }.accessibilityIdentifier("save-state")
    }
}

struct MoveRequest: Identifiable {
    let id: String
    var parent: String?
    var slot: Slot?
}

struct MoveScreen: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.words) private var words
    @Environment(\.dismiss) private var dismiss
    let request: MoveRequest
    @State private var parent = ""
    @State private var slot = Slot.topLeft

    private var possible: [String] {
        guard let project = workspace.project else { return [] }
        return project.cells.keys.filter { !(project.path(to: $0)?.contains(request.id) ?? true) }
            .sorted { title($0).localizedStandardCompare(title($1)) == .orderedAscending }
    }

    private var occupant: String? {
        guard let id = workspace.project?.cells[parent]?.child(at: slot), id != request.id else { return nil }
        return id
    }

    private var sameParent: Bool {
        workspace.project?.path(to: request.id)?.dropLast().last == parent
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker(words("move.parent"), selection: $parent) {
                    ForEach(possible, id: \.self) { id in Text(title(id)).tag(id) }
                }
                Picker(words("move.slot"), selection: $slot) {
                    ForEach(Slot.allCases, id: \.self) { value in Text(words("slot." + value.rawValue)).tag(value) }
                }
                if let occupant {
                    if sameParent {
                        Text(words.described("move.swap", title(occupant))).foregroundStyle(.secondary)
                    } else {
                        Text(words("move.occupied")).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(words("cell.move"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(words("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(words("confirm")) {
                        Task {
                            await workspace.move(request.id, to: parent, slot: slot)
                            if workspace.error == nil { dismiss() }
                        }
                    }.disabled(parent.isEmpty || (occupant != nil && !sameParent))
                }
            }
            .onAppear {
                parent = request.parent ?? workspace.currentID ?? possible.first ?? ""
                slot = request.slot ?? .topLeft
            }
        }
    }

    private func title(_ id: String) -> String {
        let value = workspace.project?.cells[id]?.previewText ?? ""
        return value.isEmpty ? words("cell.noBody") : value
    }
}

struct LegacyExportScreen: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.words) private var words
    @Environment(\.dismiss) private var dismiss
    @State private var includeLinks = false
    @State private var notices: [LegacyNotice] = []
    @State private var ready = false

    var body: some View {
        NavigationStack {
            Form {
                Section { Toggle(words("export.links"), isOn: $includeLinks) }
                Section(words("file.compatibility")) {
                    if !ready { ProgressView() }
                    else if notices.isEmpty { Text(words("export.ready")) }
                    else if let project = workspace.project {
                        ForEach(notices, id: \.self) { notice in Text(verbatim: words.notice(notice, project: project)) }
                    }
                }
            }
            .navigationTitle(words("export.legacy"))
            .task(id: includeLinks) {
                ready = false
                if let project = workspace.project {
                    let links = includeLinks
                    let items = await Task.detached { LegacyMandala.notices(for: project, includeLinks: links) }.value
                    if !Task.isCancelled { notices = items; ready = true }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(words("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(words("export")) {
                        dismiss()
                        Task { await workspace.export(legacy: true, includeLinks: includeLinks) }
                    }.disabled(!ready)
                }
            }
        }
    }
}

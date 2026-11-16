import EventKit
import SwiftUI
import UIKit
import MandalaCore

struct ReminderRequest: Identifiable {
    let cellID: String
    let action: CellAction
    var id: String { action.id }
}

struct ReminderScreen: View {
    let request: ReminderRequest
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.words) private var words
    @Environment(\.dismiss) private var dismiss
    @State private var store = EKEventStore()
    @State private var calendars: [EKCalendar] = []
    @State private var calendarID = ""
    @State private var working = false
    @State private var authorized = false
    @State private var status: String?

    private var receipt: ReminderLink? { workspace.project?.reminderLinks[request.action.id] }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: request.action.title).font(.headline)
                    if let notes = request.action.notes { Text(verbatim: notes) }
                    if let due = request.action.due {
                        Text([due.date, due.time, due.timeZone].compactMap { $0 }.joined(separator: " "))
                    }
                }
                if receipt?.state == .created {
                    Button(words("reminder.openSystem")) {
                        Task { await workspace.openSystemReminder(for: request.action, cellID: request.cellID, words: words) }
                    }
                } else if authorized && !calendars.isEmpty {
                    Picker(words("reminder.list"), selection: $calendarID) {
                        ForEach(calendars, id: \.calendarIdentifier) { calendar in
                            Text(verbatim: calendar.title).tag(calendar.calendarIdentifier)
                        }
                    }
                    Text(words(receipt == nil ? "reminder.confirm" : "reminder.retry")).font(.footnote)
                    Button(words(receipt == nil ? "reminder.create" : "reminder.check")) {
                        Task { await create(allowRetry: receipt == nil) }
                    }.disabled(working || calendarID.isEmpty)
                } else if !authorized {
                    Button(words("reminder.access")) { Task { await load(requestAccess: true) } }
                        .disabled(working)
                }
                if let status {
                    Text(words(status)).font(.footnote)
                    if status == "reminder.missing" {
                        Button(words("reminder.create")) { Task { await create(allowRetry: true) } }
                            .disabled(working || calendarID.isEmpty)
                    }
                }
                if working { ProgressView() }
            }
            .navigationTitle(words("reminder.heading"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(words("done")) { dismiss() }.disabled(working)
                }
            }
            .interactiveDismissDisabled(working)
            .task { await load(requestAccess: false) }
        }
    }

    private func load(requestAccess: Bool) async {
        guard receipt?.state != .created else { return }
        working = true
        defer { working = false }
        do {
            authorized = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
            if !authorized && requestAccess { authorized = try await store.requestFullAccessToReminders() }
            guard authorized else {
                if requestAccess { status = "reminder.denied" }
                return
            }
            calendars = store.calendars(for: .reminder).filter(\.allowsContentModifications)
            calendarID = store.defaultCalendarForNewReminders()?.calendarIdentifier ?? ""
            if !calendars.contains(where: { $0.calendarIdentifier == calendarID }) {
                calendarID = calendars.first?.calendarIdentifier ?? ""
            }
            status = calendars.isEmpty ? "reminder.noLists" : nil
        } catch { status = "reminder.failed" }
    }

    private func create(allowRetry: Bool) async {
        guard !working, receipt?.state != .created,
              let calendar = calendars.first(where: { $0.calendarIdentifier == calendarID }),
              let project = workspace.project,
              let source = SystemReminders.sourceURL(projectID: project.manifest.projectID,
                                                     cellID: request.cellID, actionID: request.id) else { return }
        working = true
        status = nil
        defer { working = false }
        do {
            let previous = receipt
            var link = try previous ?? ReminderLink(projectID: project.manifest.projectID, cellID: request.cellID,
                                                    state: .pending, operationID: ShortID.generate())
            if previous != nil {
                let existing = try await SystemReminders.find(in: store, source: source, itemID: previous?.systemItemID)
                if let existing {
                    link.state = .created
                    link.systemItemID = existing.calendarItemIdentifier
                    link.systemExternalID = existing.calendarItemExternalIdentifier
                    try SystemReminders.addSource(to: existing, in: store, source: source, label: words("reminder.source"))
                    link.listHint = existing.calendar.title
                    if !(await workspace.setReminderLink(link, for: request.id)) { status = "reminder.failed" }
                    return
                }
                guard allowRetry else { status = "reminder.missing"; return }
            }
            link.state = .pending
            link.listHint = calendar.title
            guard await workspace.setReminderLink(link, for: request.id) else { status = "reminder.failed"; return }
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar
            reminder.title = request.action.title
            reminder.notes = SystemReminders.notes(request.action.notes, source: source, label: words("reminder.source"))
            reminder.dueDateComponents = try request.action.due?.components()
            reminder.url = source
            do {
                try store.save(reminder, commit: true)
            } catch {
                link.state = .uncertain
                await workspace.setReminderLink(link, for: request.id)
                throw error
            }
            link.state = .created
            link.systemItemID = reminder.calendarItemIdentifier
            link.systemExternalID = reminder.calendarItemExternalIdentifier
            if !(await workspace.setReminderLink(link, for: request.id)) { status = "reminder.savedCheck" }
        } catch { status = "reminder.failed" }
    }
}

@MainActor
private enum SystemReminders {
    static func sourceURL(projectID: String, cellID: String, actionID: String) -> URL? {
        URL(string: "mandala-think://project/\(projectID)/cell/\(cellID)/\(actionID)")
    }

    static func notes(_ original: String?, source: URL, label: String) -> String {
        let original = original ?? ""
        if containsSource(original, source: source) { return original }
        let addition = label + "\n" + source.absoluteString
        return original.isEmpty ? addition : original + "\n\n" + addition
    }

    private static func containsSource(_ notes: String?, source: URL) -> Bool {
        notes?.split(whereSeparator: \.isNewline).contains { $0 == source.absoluteString } == true
    }

    static func addSource(to reminder: EKReminder, in store: EKEventStore, source: URL, label: String) throws {
        let updated = notes(reminder.notes, source: source, label: label)
        guard updated != reminder.notes else { return }
        reminder.notes = updated
        try store.save(reminder, commit: true)
    }

    static func find(in store: EKEventStore, source: URL, itemID: String?) async throws -> EKReminder? {
        if let itemID, let reminder = store.calendarItem(withIdentifier: itemID) as? EKReminder,
           reminder.url == source || containsSource(reminder.notes, source: source) {
            return reminder
        }
        let predicate = store.predicateForReminders(in: nil)
        return try await withCheckedThrowingContinuation { continuation in
            _ = store.fetchReminders(matching: predicate) { reminders in
                guard let reminders else {
                    continuation.resume(throwing: ProjectError.invalidDocument("reminder_links"))
                    return
                }
                continuation.resume(returning: reminders.first {
                    $0.url == source || containsSource($0.notes, source: source)
                })
            }
        }
    }

    static func itemURL(externalID: String?, localID: String?) -> URL? {
        guard let id = [externalID, localID].compactMap({ $0.flatMap(UUID.init(uuidString:)) }).first else { return nil }
        return URL(string: "x-apple-reminderkit://REMCDReminder/\(id.uuidString)/details")
    }
}

extension Workspace {
    func openSystemReminder(for action: CellAction, cellID: String, words: Words) async {
        guard let project, var receipt = project.reminderLinks[action.id], receipt.state == .created,
              let source = SystemReminders.sourceURL(projectID: project.manifest.projectID,
                                                     cellID: cellID, actionID: action.id) else { return }
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            let store = EKEventStore()
            if let reminder = try? await SystemReminders.find(in: store, source: source, itemID: receipt.systemItemID) {
                try? SystemReminders.addSource(to: reminder, in: store, source: source, label: words("reminder.source"))
                let previous = receipt
                receipt.systemItemID = reminder.calendarItemIdentifier
                receipt.systemExternalID = reminder.calendarItemExternalIdentifier
                if previous != receipt, self.project?.manifest.projectID == receipt.projectID {
                    await setReminderLink(receipt, for: action.id)
                }
            }
        }
        if let itemURL = SystemReminders.itemURL(externalID: receipt.systemExternalID, localID: receipt.systemItemID),
           await UIApplication.shared.open(itemURL) { return }
        if let appURL = URL(string: "x-apple-reminderkit://"), await UIApplication.shared.open(appURL) { return }
        error = ProjectError.invalidDocument("Reminders")
    }
}

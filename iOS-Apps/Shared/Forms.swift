import SwiftUI

struct FormField: Identifiable {
    let id: String
    let title: String
    var required: Bool = false
    var choices: [String] = []
    var numeric: Bool = false
    var secret: Bool = false
    init(_ id: String, _ title: String, required: Bool = false, choices: [String] = [], numeric: Bool = false, secret: Bool = false) {
        self.id = id; self.title = title; self.required = required; self.choices = choices; self.numeric = numeric; self.secret = secret
    }
}
struct APIForm: View {
    let title: String
    let path: String
    var method = "POST"
    let fields: [FormField]
    var initial = Row()
    var onSaved: () async -> Void = {}
    @EnvironmentObject var api: API
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var busy = false
    @State private var error: String?
    private func binding(_ key: String) -> Binding<String> { Binding(get: { values[key] ?? "" }, set: { values[key] = $0 }) }
    var body: some View {
        Form {
            ForEach(fields) { field in
                Section(field.title + (field.required ? " *" : "")) {
                    if !field.choices.isEmpty {
                        Picker(field.title, selection: binding(field.id)) { ForEach(field.choices, id: \.self) { Text($0).tag($0) } }
                    } else if field.secret { SecureField(field.title, text: binding(field.id)).textContentType(.newPassword) }
                    else if field.id.contains("date") || field.id == "sia_expiry" {
                        DatePicker(field.title, selection: dateBinding(field.id), displayedComponents: .date).environment(\.timeZone, UKTime.zone)
                        if !field.required { Button("Clear") { values[field.id] = "" } }
                    } else if field.id.contains("time") {
                        DatePicker(field.title, selection: timeBinding(field.id), displayedComponents: .hourAndMinute).environment(\.timeZone, UKTime.zone)
                    } else {
                        TextField(field.title, text: binding(field.id), axis: field.id == "description" || field.id == "notes" ? .vertical : .horizontal)
                            .keyboardType(field.numeric ? .decimalPad : field.id == "email" ? .emailAddress : .default)
                            .textInputAutocapitalization(field.id == "email" ? .never : .sentences).autocorrectionDisabled(field.id == "email")
                    }
                }
            }
            if let error { Section { Notice(text: error) } }
            Section { PrimaryButton(title: busy ? "Saving…" : "Save changes", symbol: "checkmark", enabled: !busy) { Task { await save() } } }
        }.scrollContentBackground(.hidden).background(Palette.background).navigationTitle(title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
            .onAppear {
                guard values.isEmpty else { return }
                for field in fields {
                    var value = initial.text(field.id, fallback: field.choices.first ?? "")
                    if value.isEmpty && (field.required || field.id.contains("time")) {
                        if field.id.contains("date") { value = UKTime.day() }
                        else if field.id.contains("time") { value = "09:00" }
                    }
                    values[field.id] = value
                }
            }.interactiveDismissDisabled(busy)
    }
    private func dateBinding(_ key: String) -> Binding<Date> {
        Binding(get: { UKTime.formatter("yyyy-MM-dd").date(from: values[key] ?? "") ?? Date() }, set: { values[key] = UKTime.day($0) })
    }
    private func timeBinding(_ key: String) -> Binding<Date> {
        Binding(get: { UKTime.parse(UKTime.day() + "T" + String((values[key] ?? "09:00").prefix(5)) + ":00") ?? Date() }, set: { values[key] = UKTime.formatter("HH:mm").string(from: $0) })
    }
    private func save() async {
        error = nil
        for field in fields where field.required && (values[field.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error = "\(field.title) is required."; return }
        var payload: [String: Any] = [:]
        for field in fields {
            let value = values[field.id] ?? ""
            if !field.required && value.isEmpty {
                if !initial.text(field.id).isEmpty && field.id != "email" && field.id != "password" {
                    payload[field.id] = field.id == "sia_expiry" || field.id == "end_date" ? NSNull() as Any : ""
                }
                continue
            }
            if field.numeric {
                guard let number = Double(value), number.isFinite, number >= 0 else { error = "Enter a valid \(field.title.lowercased())."; return }
                payload[field.id] = number
            } else { payload[field.id] = value }
        }
        busy = true; defer { busy = false }
        do { _ = try await api.call(path, method: method, body: payload); await onSaved(); dismiss() } catch { self.error = error.localizedDescription }
    }
}
struct Timesheets: View {
    let staff: Bool
    @EnvironmentObject var api: API
    @State private var start = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var end = Date()
    @State private var rows: [Row] = []
    @State private var error: String?
    @State private var busy = false
    @State private var exportURL: URL?
    var body: some View {
        Screen {
            DatePicker("From", selection: $start, displayedComponents: .date).environment(\.timeZone, UKTime.zone)
            DatePicker("To", selection: $end, displayedComponents: .date).environment(\.timeZone, UKTime.zone)
            PrimaryButton(title: "Load timesheets", symbol: "clock", enabled: !busy && start <= end) { Task { await load() } }
            if let error { Notice(text: error) }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Panel { Text(row.text("event_name")).font(.headline); Text([row.text("first_name"), row.text("last_name")].joined(separator: " ")); Text(row.text("shift_date")).foregroundStyle(Palette.muted); HStack { Text("\(row.text("computed_hours")) hours"); Spacer(); Text("£\(row.text("total_pay"))").foregroundStyle(Palette.green) } }
            }
            LoadingRows(empty: rows.isEmpty, busy: busy)
            if !staff { Button("Export CSV") { Task { await export() } }.buttonStyle(.bordered) }
            if let exportURL { ShareLink(item: exportURL) { Label("Save or share CSV", systemImage: "square.and.arrow.up") } }
        }.navigationTitle("Timesheets").task { await load() }
    }
    private var query: String { "?start=\(UKTime.day(start))&end=\(UKTime.day(end))" }
    private func load() async { busy = true; defer { busy = false }; do { rows = try await api.call((staff ? "/api/timesheet/my" : "/api/timesheet") + query).rows("timesheets"); error = nil } catch { self.error = error.localizedDescription } }
    private func export() async { do { let data = try await api.data("/api/timesheet/export" + query); let url = FileManager.default.temporaryDirectory.appendingPathComponent("SISS-timesheets-\(UKTime.day()).csv"); try data.write(to: url, options: .atomic); exportURL = url } catch { self.error = error.localizedDescription } }
}

import SwiftUI

struct AdminRoot: View {
    var body: some View {
        TabView {
            NavigationStack { AdminDashboard() }.tabItem { Label("Home", systemImage: "square.grid.2x2") }
            NavigationStack { PeopleScreen() }.tabItem { Label("People", systemImage: "person.2") }
            NavigationStack { EventsScreen() }.tabItem { Label("Events", systemImage: "calendar") }
            NavigationStack { ScanScreen() }.tabItem { Label("Scan", systemImage: "qrcode.viewfinder") }
            NavigationStack { FinanceScreen() }.tabItem { Label("Finance", systemImage: "sterlingsign.circle") }
        }
    }
}
struct AdminDashboard: View {
    @EnvironmentObject var api: API
    @State private var stats = Row()
    @State private var error: String?
    var body: some View {
        Screen {
            Text("Welcome back, \(api.user?.name ?? "")").font(.title2.bold())
            if let error { Notice(text: error) }
            NavigationLink { EventsScreen() } label: { StatGrid(values: [("Active shifts", stats.text("activeShifts", fallback: "0"))]) }.buttonStyle(.plain)
            NavigationLink { PeopleScreen() } label: { StatGrid(values: [("Active staff", stats.text("activeStaff", fallback: "0")), ("Pending applications", stats.text("pendingApplications", fallback: "0"))]) }.buttonStyle(.plain)
            NavigationLink { AdminDocuments() } label: { StatGrid(values: [("Document approvals", stats.text("pendingDocApprovals", fallback: "0"))]) }.buttonStyle(.plain)
            Panel { Text("Messages today").foregroundStyle(Palette.muted); Text(stats.text("messagesToday", fallback: "0")).font(.largeTitle.bold()) }
            NavigationLink { Timesheets(staff: false) } label: { Panel { Label("Timesheets", systemImage: "clock") } }.buttonStyle(.plain)
            NavigationLink { AccountScreen() } label: { Panel { Label("Settings & sign out", systemImage: "gearshape") } }.buttonStyle(.plain)
        }.navigationTitle("Dashboard").task { await load() }.refreshable { await load() }
    }
    private func load() async { do { stats = try await api.call("/api/dashboard/stats"); error = nil } catch { self.error = error.localizedDescription } }
}
enum AdminFields {
    static let people = [FormField("first_name", "First name", required: true), FormField("last_name", "Last name", required: true), FormField("email", "Email", required: true), FormField("phone", "Phone"), FormField("position", "Position", required: true), FormField("location", "Location", required: true), FormField("role", "Portal access", choices: ["staff", "moderator", "admin"]), FormField("status", "Status", choices: ["active", "inactive", "pending_docs", "suspended"]), FormField("sia_number", "SIA number"), FormField("sia_expiry", "SIA expiry"), FormField("bank_account_name", "Account name"), FormField("bank_account_number", "Account number"), FormField("bank_sort_code", "Sort code")]
    static let event = [FormField("name", "Event name", required: true), FormField("venue", "Venue", required: true), FormField("type", "Type", choices: ["Event", "Festival", "Concert", "Sport", "Other"]), FormField("description", "Description"), FormField("start_date", "Start date", required: true), FormField("end_date", "End date")]
    static let shift = [FormField("role", "Shift title", required: true), FormField("required_right", "Required job role", choices: ["Any"] + AppKind.jobs), FormField("location", "Location"), FormField("description", "Instructions"), FormField("shift_date", "Shift date", required: true), FormField("start_time", "Start time", required: true), FormField("end_time", "End time", required: true), FormField("pay_rate", "Pay per hour", required: true, numeric: true)]
}
struct PeopleScreen: View {
    @EnvironmentObject var api: API
    @State private var mode = "Staff"
    @State private var people: [Row] = []
    @State private var search = ""
    @State private var error: String?
    @State private var busy = false
    @State private var adding = false
    @State private var reject: Row?
    var body: some View {
        Screen {
            Picker("People", selection: $mode) { Text("Staff").tag("Staff"); Text("Applications").tag("Applications"); Text("Pending docs").tag("Pending docs") }.pickerStyle(.segmented)
            if let error { Notice(text: error) }
            ForEach(people.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.text("email").localizedCaseInsensitiveContains(search) }) { person in
                if mode == "Staff" {
                    NavigationLink { PersonDetail(id: person.id) } label: { personCard(person) }.buttonStyle(.plain)
                } else {
                    Panel {
                        Text(person.name).font(.headline); Text(person.text("email")).foregroundStyle(Palette.muted)
                        if mode == "Pending docs" { NavigationLink("Review documents") { PersonDetail(id: person.id) } }
                        HStack { Button("Approve") { Task { await approve(person) } }.buttonStyle(.borderedProminent); Button("Reject", role: .destructive) { reject = person }.buttonStyle(.bordered) }.disabled(busy)
                    }
                }
            }
            LoadingRows(empty: people.isEmpty, busy: busy)
        }.navigationTitle("People & Staff").searchable(text: $search).task(id: mode) { await load() }.refreshable { await load() }
            .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $adding) { NavigationStack { APIForm(title: "New staff member", path: "/api/people/staff", fields: AdminFields.people + [FormField("password", "Password (optional)", secret: true)]) { await load() } } }
            .sheet(item: $reject) { person in NavigationStack { APIForm(title: "Reject \(person.name)", path: mode == "Applications" ? "/api/people/applications/\(person.id)/reject" : "/api/people/doc-approvals/\(person.id)/reject", fields: [FormField("reason", "Reason")]) { await load() } } }
    }
    private func personCard(_ person: Row) -> some View { Panel { HStack { Text(person.name).font(.headline); Spacer(); Badge(text: person.text("status")) }; Text(person.text("email")).font(.subheadline).foregroundStyle(Palette.muted); Text(person.text("position")).foregroundStyle(Palette.blue) } }
    private func load() async {
        busy = true; defer { busy = false }
        do {
            let path = mode == "Staff" ? "/api/people/staff" : mode == "Applications" ? "/api/people/applications" : "/api/people/doc-approvals"
            let key = mode == "Staff" ? "staff" : mode == "Applications" ? "applications" : "users"
            people = try await api.call(path).rows(key); error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func approve(_ person: Row) async {
        busy = true; defer { busy = false }
        do { _ = try await api.call(mode == "Applications" ? "/api/people/applications/\(person.id)/approve" : "/api/people/doc-approvals/\(person.id)/approve", method: "POST"); await load() } catch { self.error = error.localizedDescription }
    }
}
struct PersonDetail: View {
    let id: Int
    @EnvironmentObject var api: API
    @Environment(\.dismiss) private var dismiss
    @State private var detail = Row()
    @State private var error: String?
    @State private var edit = false
    @State private var busy = false
    @State private var delete = false
    @State private var reset = false
    @State private var password: String?
    private var roles: [String] { detail.object("user").text("rights").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } }
    var body: some View {
        Screen {
            if let error { Notice(text: error) }
            Panel { let user = detail.object("user"); Text(user.name).font(.title2.bold()); Text(user.text("email")).foregroundStyle(Palette.muted); Badge(text: user.text("status")); PrimaryButton(title: "Edit staff", symbol: "pencil") { edit = true } }
            Panel {
                Text("Job roles").font(.headline)
                Text("Choose every role this person can work.").font(.subheadline).foregroundStyle(Palette.muted)
                ForEach(AppKind.jobs, id: \.self) { role in
                    Toggle(role, isOn: Binding(get: { roles.contains(role) }, set: { enabled in Task { await toggle(role, enabled) } })).disabled(busy)
                }
            }
            ForEach(detail.rows("docs")) { doc in DocumentCard(doc: doc) }
            Button("Reset password") { reset = true }.buttonStyle(.bordered).disabled(busy)
            if let password { Panel { Text("New password").font(.headline); Text(password).textSelection(.enabled); Text("Share this securely with the staff member.").font(.caption).foregroundStyle(Palette.muted) } }
            Button("Delete staff member", role: .destructive) { delete = true }.buttonStyle(.bordered).disabled(busy)
        }.navigationTitle("Staff details").task { await load() }.refreshable { await load() }
            .sheet(isPresented: $edit) { NavigationStack { APIForm(title: "Edit staff", path: "/api/people/staff/\(id)", method: "PUT", fields: AdminFields.people, initial: detail.object("user")) { await load() } } }
            .confirmationDialog("Delete this staff member?", isPresented: $delete, titleVisibility: .visible) { Button("Delete staff", role: .destructive) { Task { do { _ = try await api.call("/api/people/staff/\(id)", method: "DELETE"); dismiss() } catch { self.error = error.localizedDescription } } } }
            .confirmationDialog("Reset this staff member's password?", isPresented: $reset, titleVisibility: .visible) { Button("Reset password", role: .destructive) { Task { do { password = try await api.call("/api/people/staff/\(id)/reset-password", method: "POST").text("password") } catch { self.error = error.localizedDescription } } } }
    }
    private func load() async { do { detail = try await api.call("/api/people/staff/\(id)"); error = nil } catch { self.error = error.localizedDescription } }
    private func toggle(_ role: String, _ enabled: Bool) async {
        busy = true; defer { busy = false }; var selected = roles.filter { $0 != role }; if enabled { selected.append(role) }
        do { _ = try await api.call("/api/people/staff/\(id)/rights", method: "PUT", body: ["rights": selected]); await load() } catch { self.error = error.localizedDescription }
    }
}
struct EventsScreen: View {
    @EnvironmentObject var api: API
    @State private var events: [Row] = []
    @State private var busy = false
    @State private var error: String?
    @State private var adding = false
    @State private var search = ""
    var body: some View {
        Screen {
            if let error { Notice(text: error) }
            ForEach(events.filter { search.isEmpty || $0.text("name").localizedCaseInsensitiveContains(search) }) { event in
                NavigationLink { EventDetail(id: event.id) } label: { Panel { Text(event.text("name")).font(.headline); Label(event.text("venue"), systemImage: "mappin.and.ellipse").foregroundStyle(Palette.muted); Text(event.text("start_date")).font(.subheadline); Badge(text: event.text("status", fallback: "active")) } }.buttonStyle(.plain)
            }
            LoadingRows(empty: events.isEmpty, busy: busy)
        }.navigationTitle("Events & shifts").searchable(text: $search).task { await load() }.refreshable { await load() }
            .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $adding) { NavigationStack { APIForm(title: "New event", path: "/api/events", fields: AdminFields.event) { await load() } } }
    }
    private func load() async { busy = true; defer { busy = false }; do { events = try await api.call("/api/events").rows("events"); error = nil } catch { self.error = error.localizedDescription } }
}
struct EventDetail: View {
    let id: Int
    @EnvironmentObject var api: API
    @State private var event = Row()
    @State private var error: String?
    @State private var adding = false
    var body: some View {
        Screen {
            Panel { Text(event.text("name")).font(.title2.bold()); Text(event.text("venue")).foregroundStyle(Palette.muted); Text(event.text("description")) }
            if let error { Notice(text: error) }
            PrimaryButton(title: "Add shift", symbol: "plus") { adding = true }
            ForEach(event.rows("shifts")) { shift in NavigationLink { AdminShiftDetail(initial: shift) } label: { ShiftSummary(shift: shift) }.buttonStyle(.plain) }
        }.navigationTitle("Event").task { await load() }.refreshable { await load() }
            .sheet(isPresented: $adding) { NavigationStack { APIForm(title: "New shift", path: "/api/events/\(id)/shifts", fields: AdminFields.shift, initial: Row(["shift_date": event.text("start_date"), "pay_rate": "0"])) { await load() } } }
    }
    private func load() async { do { event = try await api.call("/api/events/\(id)").object("event"); error = nil } catch { self.error = error.localizedDescription } }
}
struct AdminShiftDetail: View {
    let initial: Row
    @EnvironmentObject var api: API
    @Environment(\.dismiss) private var dismiss
    @State private var shift = Row()
    @State private var people: [Row] = []
    @State private var edit = false
    @State private var error: String?
    @State private var busy = false
    @State private var selected = 0
    @State private var destructive: String?
    private var current: Row { shift.id > 0 ? shift : initial }
    var body: some View {
        Screen {
            ShiftSummary(shift: current)
            if let error { Notice(text: error) }
            Panel { Text("Required job role: \(current.text("required_right", fallback: "Any"))"); Text("Allocated to: \(current.text("assignee_name", fallback: "Unallocated"))"); Text("£\(current.text("pay_rate"))/hour"); PrimaryButton(title: "Edit shift", symbol: "pencil", enabled: !busy) { edit = true } }
            Panel {
                Text("Allocate staff").font(.headline)
                Picker("Staff member", selection: $selected) { Text("Choose staff").tag(0); ForEach(people) { Text($0.name).tag($0.id) } }
                PrimaryButton(title: "Allocate", symbol: "person.badge.plus", enabled: selected > 0 && !busy) { Task { await action("allocate", body: ["user_id": selected]) } }
                Button("Cancel allocation", role: .destructive) { destructive = "cancel" }.disabled(busy)
                Button("Delete shift", role: .destructive) { destructive = "delete" }.disabled(busy)
            }
        }.navigationTitle("Shift details").task { await load() }.refreshable { await load() }
            .sheet(isPresented: $edit) { NavigationStack { APIForm(title: "Edit shift", path: "/api/events/shifts/\(initial.id)", method: "PUT", fields: AdminFields.shift + [FormField("end_date", "End date"), FormField("status", "Status", choices: ["open", "pending", "filled", "cancelled", "emergency"])], initial: current) { await load() } } }
            .confirmationDialog("Confirm \(destructive ?? "")?", isPresented: Binding(get: { destructive != nil }, set: { if !$0 { destructive = nil } }), titleVisibility: .visible) { Button("Confirm", role: .destructive) { let value = destructive ?? ""; destructive = nil; Task { await action(value) } } }
    }
    private func load() async { do { shift = try await api.call("/api/events/shifts/\(initial.id)").object("shift"); people = try await api.call("/api/people/staff/all").rows("staff"); error = nil } catch { self.error = error.localizedDescription } }
    private func action(_ action: String, body: [String: Any]? = nil) async {
        busy = true; defer { busy = false }
        do { _ = try await api.call("/api/events/shifts/\(initial.id)" + (action == "delete" ? "" : "/\(action)"), method: action == "delete" ? "DELETE" : "POST", body: body); if action == "delete" { dismiss() } else { await load() } } catch { self.error = error.localizedDescription }
    }
}
struct AdminDocuments: View {
    @EnvironmentObject var api: API
    @State private var docs: [Row] = []
    @State private var error: String?
    @State private var reject: Row?
    @State private var busy = false
    var body: some View {
        Screen {
            NavigationLink("Pending document submissions") { PeopleScreen() }
            if let error { Notice(text: error) }
            ForEach(docs) { doc in
                DocumentCard(doc: doc)
                HStack { Button("Approve") { Task { await approve(doc) } }.buttonStyle(.borderedProminent); Button("Reject", role: .destructive) { reject = doc }.buttonStyle(.bordered) }.disabled(busy)
            }
            LoadingRows(empty: docs.isEmpty, busy: busy)
        }.navigationTitle("Document updates").task { await load() }.refreshable { await load() }
            .sheet(item: $reject) { doc in NavigationStack { APIForm(title: "Reject document", path: "/api/people/doc-updates/\(doc.id)/reject", fields: [FormField("reason", "Reason")]) { await load() } } }
    }
    private func load() async { busy = true; defer { busy = false }; do { docs = try await api.call("/api/people/doc-updates").rows("docs"); error = nil } catch { self.error = error.localizedDescription } }
    private func approve(_ doc: Row) async { busy = true; defer { busy = false }; do { _ = try await api.call("/api/people/doc-updates/\(doc.id)/approve", method: "POST"); await load() } catch { self.error = error.localizedDescription } }
}
struct DocumentCard: View {
    let doc: Row
    @EnvironmentObject var api: API
    @State private var file: URL?
    @State private var error: String?
    var body: some View {
        Panel {
            Text(doc.text("title", fallback: doc.text("doc_type"))).font(.headline)
            Text(doc.text("file_name")).foregroundStyle(Palette.muted); Badge(text: doc.text("status"))
            if let error { Notice(text: error) }
            Button("Download document") { Task { await download() } }.buttonStyle(.bordered)
            if let file { ShareLink(item: file) { Label("Open or share", systemImage: "square.and.arrow.up") } }
        }
    }
    private func download() async {
        do {
            let bytes = try await api.data("/api/documents/\(doc.id)/download")
            let filename = URL(fileURLWithPath: doc.text("file_name", fallback: "document.pdf")).lastPathComponent
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(filename); try bytes.write(to: url, options: .atomic); file = url
        } catch { self.error = error.localizedDescription }
    }
}
struct FinanceScreen: View {
    @EnvironmentObject var api: API
    @State private var mode = "Invoices"
    @State private var clients: [Row] = []
    @State private var invoices: [Row] = []
    @State private var error: String?
    @State private var adding = false
    var body: some View {
        Screen {
            Picker("Finance", selection: $mode) { Text("Invoices").tag("Invoices"); Text("Clients").tag("Clients") }.pickerStyle(.segmented)
            if let error { Notice(text: error) }
            ForEach(mode == "Invoices" ? invoices : clients) { row in
                Panel {
                    Text(row.text(mode == "Invoices" ? "ref" : "name")).font(.headline)
                    if mode == "Invoices" { Text(row.text("client_name")).foregroundStyle(Palette.muted); Text("£\(row.text("amount"))").font(.title3.bold()); Badge(text: row.text("status")); Text("Due \(row.text("due_date"))").font(.caption) }
                    else { Text(row.text("contact")); Text(row.text("email")).foregroundStyle(Palette.muted); Text(row.text("phone")).foregroundStyle(Palette.muted) }
                }
            }
            LoadingRows(empty: (mode == "Invoices" ? invoices : clients).isEmpty, busy: false)
        }.navigationTitle("Finance").task { await load() }.refreshable { await load() }
            .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $adding) {
                NavigationStack {
                    if mode == "Clients" { APIForm(title: "New client", path: "/api/invoicing/clients", fields: [FormField("name", "Client name", required: true), FormField("contact", "Contact"), FormField("email", "Email"), FormField("phone", "Phone"), FormField("address", "Address")]) { await load() } }
                    else { InvoiceForm(clients: clients) { await load() } }
                }
            }
    }
    private func load() async { do { clients = try await api.call("/api/invoicing/clients").rows("clients"); invoices = try await api.call("/api/invoicing/invoices").rows("invoices"); error = nil } catch { self.error = error.localizedDescription } }
}
struct InvoiceForm: View {
    let clients: [Row]
    let saved: () async -> Void
    @State private var client = 0
    var body: some View {
        VStack {
            Picker("Client", selection: $client) { Text("Select client").tag(0); ForEach(clients) { Text($0.text("name")).tag($0.id) } }.padding()
            if client > 0 {
                APIForm(title: "New invoice", path: "/api/invoicing/invoices", fields: [FormField("client_id", "Client ID", required: true, numeric: true), FormField("ref", "Reference", required: true), FormField("amount", "Amount", required: true, numeric: true), FormField("vat", "VAT", numeric: true), FormField("issued_date", "Issued date", required: true), FormField("due_date", "Due date", required: true), FormField("notes", "Notes")], initial: Row(["client_id": client, "vat": "0"]), onSaved: saved).id(client)
            } else { ContentUnavailableView("Choose a client", systemImage: "person.crop.rectangle") }
        }.navigationTitle("New invoice").background(Palette.background)
    }
}

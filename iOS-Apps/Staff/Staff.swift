import SwiftUI
import UIKit

struct StaffRoot: View {
    var body: some View {
        TabView {
            NavigationStack { StaffDashboard() }.tabItem { Label("Home", systemImage: "square.grid.2x2") }
            NavigationStack { StaffShifts() }.tabItem { Label("Shifts", systemImage: "calendar") }
            NavigationStack { StaffProfile() }.tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}
struct StaffDashboard: View {
    @EnvironmentObject var api: API
    @Environment(\.scenePhase) private var phase
    @State private var dashboard = Row()
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        Screen {
            Text("Welcome back, \(api.user?.name ?? "")").font(.title2.bold())
            Text("Here's what's happening with your shifts.").foregroundStyle(Palette.muted)
            if let error { Notice(text: error) }
            let stats = dashboard.object("stats")
            StatGrid(values: [("Upcoming shifts", stats.text("upcomingShifts", fallback: "0")), ("Completed", stats.text("completedShifts", fallback: "0")), ("Hours worked", stats.text("totalHours", fallback: "0")), ("Earnings", "£" + stats.text("totalPay", fallback: "0"))])
            Text("Upcoming shifts").font(.title3.bold())
            ForEach(dashboard.rows("upcomingShifts")) { shift in
                NavigationLink { StaffShiftDetail(initial: shift) } label: { ShiftSummary(shift: shift) }.buttonStyle(.plain)
            }
            LoadingRows(empty: dashboard.rows("upcomingShifts").isEmpty, busy: busy)
            NavigationLink { StaffShifts() } label: { Label("View all shifts", systemImage: "calendar") }.buttonStyle(.bordered)
        }.navigationTitle("Dashboard").task { await load() }.refreshable { await load() }
            .onChange(of: phase) { _, value in if value == .active { Task { await load() } } }
    }
    private func load() async {
        busy = true; defer { busy = false }; error = nil
        do { dashboard = try await api.call("/api/dashboard/staff") } catch { self.error = error.localizedDescription }
    }
}
struct StaffShifts: View {
    @EnvironmentObject var api: API
    @State private var available = false
    @State private var shifts: [Row] = []
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        Screen {
            Picker("Shifts", selection: $available) { Text("My shifts").tag(false); Text("Available").tag(true) }.pickerStyle(.segmented)
            if let error { Notice(text: error) }
            ForEach(shifts) { shift in
                NavigationLink { StaffShiftDetail(initial: shift) } label: { ShiftSummary(shift: shift) }.buttonStyle(.plain)
            }
            LoadingRows(empty: shifts.isEmpty, busy: busy)
        }.navigationTitle("Shifts").task(id: available) { await load() }.refreshable { await load() }
    }
    private func load() async {
        busy = true; defer { busy = false }; error = nil
        do { shifts = try await api.call(available ? "/api/events/shifts/available" : "/api/events/my/shifts").rows("shifts") } catch { self.error = error.localizedDescription }
    }
}
struct StaffShiftDetail: View {
    let initial: Row
    @EnvironmentObject var api: API
    @State private var shift = Row()
    @State private var image: UIImage?
    @State private var error: String?
    @State private var busy = false
    private var current: Row { shift.id > 0 ? shift : initial }
    private var assigned: Bool { current.flag("allocated_to_me") || current.integer("assigned_to") == api.user?.id }
    var body: some View {
        Screen {
            ShiftSummary(shift: current)
            Panel {
                Text("Shift details").font(.headline)
                Text(current.text("description", fallback: "No additional instructions."))
                Text("£\(current.text("pay_rate", fallback: "0"))/hour").foregroundStyle(Palette.green)
                if !current.text("end_date").isEmpty { Text("Ends \(current.text("end_date"))").foregroundStyle(Palette.muted) }
                if !current.text("signed_in_at").isEmpty { Badge(text: "Signed in \(current.text("signed_in_at"))") }
            }
            if let error { Notice(text: error) }
            if assigned {
                Panel {
                    Text("Your shift QR code").font(.headline)
                    if let image { Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 280).padding(10).background(.white).clipShape(RoundedRectangle(cornerRadius: 12)).frame(maxWidth: .infinity) }
                    Text("Show your QR to Admin for attendance or to your supervisor for the team record.").font(.subheadline).foregroundStyle(Palette.muted)
                    PrimaryButton(title: image == nil ? "Load QR code" : "Refresh QR code", symbol: "qrcode", enabled: !busy) { Task { await qr() } }
                }
            } else if current.text("status") == "open" {
                PrimaryButton(title: current.flag("interested") ? "Interest expressed" : "Express interest", enabled: !busy && !current.flag("interested")) {
                    busy = true
                    Task {
                        defer { busy = false }
                        do { _ = try await api.call("/api/events/shifts/\(current.id)/interest", method: "POST"); await load() } catch { self.error = error.localizedDescription }
                    }
                }
            }
            if busy { ProgressView() }
        }.navigationTitle("Shift details").task { await load(); if assigned { await qr() } }.refreshable { await load() }
    }
    private func load() async { do { shift = try await api.call("/api/events/shifts/\(initial.id)").object("shift") } catch { self.error = error.localizedDescription } }
    private func qr() async {
        busy = true; error = nil; defer { busy = false }
        do {
            let data = try await api.data("/api/qr/shift/\(current.id)")
            guard let decoded = UIImage(data: data) else { throw ServerError(status: 0, message: "The server did not return a QR image.") }
            image = decoded
        } catch { self.error = error.localizedDescription }
    }
}
struct StaffProfile: View {
    @EnvironmentObject var api: API
    @State private var profile = Row()
    @State private var edit = false
    @State private var error: String?
    private let fields = [FormField("first_name", "First name", required: true), FormField("last_name", "Last name", required: true), FormField("phone", "Phone"), FormField("location", "Location"), FormField("bank_account_name", "Account name"), FormField("bank_account_number", "Account number"), FormField("bank_sort_code", "Sort code")]
    var body: some View {
        Screen {
            if let error { Notice(text: error) }
            Panel {
                let user = profile.object("user")
                Text(user.id > 0 ? user.name : api.user?.name ?? "").font(.title2.bold())
                ForEach(["email", "phone", "position", "location", "sia_number", "sia_expiry"], id: \.self) { key in
                    if !user.text(key).isEmpty { HStack { Text(key.replacingOccurrences(of: "_", with: " ").capitalized).foregroundStyle(Palette.muted); Spacer(); Text(user.text(key)) } }
                }
                PrimaryButton(title: "Edit profile", symbol: "pencil") { edit = true }
            }
            NavigationLink { StaffDocuments() } label: { Panel { Label("My documents", systemImage: "doc.text"); Text("Track document submissions and approval").font(.subheadline).foregroundStyle(Palette.muted) } }.buttonStyle(.plain)
            NavigationLink { Timesheets(staff: true) } label: { Panel { Label("Timesheets", systemImage: "clock") } }.buttonStyle(.plain)
            NavigationLink { AccountScreen() } label: { Panel { Label("Account & sign out", systemImage: "person.crop.circle") } }.buttonStyle(.plain)
        }.navigationTitle("Profile").task { await load() }.refreshable { await load() }
            .sheet(isPresented: $edit) { NavigationStack { APIForm(title: "Edit profile", path: "/api/people/profile", method: "PUT", fields: fields, initial: profile.object("user")) { await load() } } }
    }
    private func load() async { do { profile = try await api.call("/api/people/profile") } catch { self.error = error.localizedDescription } }
}
struct StaffDocuments: View {
    @EnvironmentObject var api: API
    @State private var docs: [Row] = []
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        Screen {
            Text("Track your document submissions").foregroundStyle(Palette.muted)
            if let error { Notice(text: error) }
            ForEach(docs) { doc in Panel { Text(doc.text("title", fallback: doc.text("doc_type"))).font(.headline); Text(doc.text("file_name")).font(.subheadline).foregroundStyle(Palette.muted); Badge(text: doc.text("status")) } }
            LoadingRows(empty: docs.isEmpty, busy: busy)
            Text("Upload documents using the web portal, as in the Android Staff app.").font(.caption).foregroundStyle(Palette.muted)
            Link("Open web portal", destination: API.base.appendingPathComponent("login")).buttonStyle(.bordered)
        }.navigationTitle("My documents").task { await load() }.refreshable { await load() }
    }
    private func load() async { busy = true; defer { busy = false }; do { docs = try await api.call("/api/people/profile").rows("documents"); error = nil } catch { self.error = error.localizedDescription } }
}

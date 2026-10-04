import SwiftUI

struct SupervisorRoot: View {
    @StateObject private var model = SupervisorModel()
    var body: some View { NavigationStack { SupervisorHome(model: model) } }
}
struct SupervisorHome: View {
    @ObservedObject var model: SupervisorModel
    @EnvironmentObject var api: API
    @Environment(\.scenePhase) private var phase
    @State private var choose = false
    var body: some View {
        Screen {
            HStack { VStack(alignment: .leading) { Text("Hello, \(api.user?.name ?? "Supervisor")").font(.title2.bold()); Text("Your shift workspace").font(.subheadline).foregroundStyle(Palette.muted) }; Spacer(); NavigationLink { AccountScreen() } label: { Image(systemName: "person.crop.circle").font(.title2) } }
            if let error = model.error { Notice(text: error) }
            if let notice = model.notice { Notice(text: notice) }
            if model.selected > 0 {
                Panel {
                    HStack { Text("YOUR SHIFT").font(.caption.bold()).foregroundStyle(Palette.blue); Spacer(); Button("Change") { choose = true }.disabled(model.busy || model.entryDraft != nil || model.finishDraft != nil) }
                    Text(model.shift.shiftTitle).font(.title2.bold())
                    Label(model.shift.text("venue"), systemImage: "mappin.and.ellipse").foregroundStyle(Palette.muted)
                    Text(model.shift.timing).font(.subheadline).foregroundStyle(Palette.muted)
                    Badge(text: model.signed ? "Report signed" : model.live ? "On shift" : "Assigned")
                }
                HStack(alignment: .top, spacing: 12) {
                    NavigationLink { SupervisorReport(model: model) } label: { tool("Supervisor report", model.signed ? "Review signed report" : "Keep your shift log", "doc.text", Palette.blue) }.buttonStyle(.plain)
                    NavigationLink { ScanScreen(path: model.path + "/scan", supervisor: true) { await model.refresh() } } label: { tool("Staff sign in", "Record your allocated team", "qrcode.viewfinder", Palette.green) }.buttonStyle(.plain).disabled(!model.canScan)
                }
                StatGrid(values: [("Allocated staff", String(model.allocated.count)), ("Recorded staff", String(model.records.count)), ("Log entries", String(model.entries.count))])
                Text("Your team").font(.title3.bold())
                ForEach(model.allocated, id: \.rawStaffID) { person in
                    Panel { HStack { Text(person.text("staff_name")).font(.headline); Spacer(); if model.records.contains(where: { $0.integer("staff_shift_id") == person.integer("staff_shift_id") }) { Badge(text: "Recorded") } }; Text(person.text("staff_role")).foregroundStyle(Palette.muted) }
                }
                if !model.canScan { Text("Staff recording opens when your shift starts and closes at the end of the event day.").font(.caption).foregroundStyle(Palette.muted) }
            } else { ContentUnavailableView("No supervisor shifts", systemImage: "calendar", description: Text("Ask Admin to allocate a Supervisor shift to you.")) }
            if model.busy { ProgressView().frame(maxWidth: .infinity) }
        }.navigationTitle("Siss-Supervisor").navigationBarTitleDisplayMode(.inline).task { await model.refresh() }.refreshable { await model.refresh() }
            .onChange(of: phase) { _, value in if value == .active { Task { await model.refresh() } } }
            .sheet(isPresented: $choose) {
                NavigationStack {
                    Screen { ForEach(model.shifts) { shift in Button { choose = false; Task { await model.select(shift.id) } } label: { ShiftSummary(shift: shift) }.buttonStyle(.plain) } }.navigationTitle("Choose shift").toolbar { Button("Done") { choose = false } }
                }
            }
    }
    private func tool(_ title: String, _ subtitle: String, _ icon: String, _ colour: Color) -> some View {
        Panel { Image(systemName: icon).font(.title2).foregroundStyle(colour); Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(Palette.muted); Image(systemName: "arrow.right").foregroundStyle(colour) }.frame(maxWidth: .infinity)
    }
}
extension Row { var rawStaffID: Int { integer("staff_shift_id") } }
enum ReportActivity {
    static let options = [("staff_briefed", "Staff briefed"), ("gates_opened", "Gate opened for public"), ("bag_searches", "Bag searches done"), ("staff_breaks", "Staff breaks started"), ("incident", "Incident"), ("other", "Other")]
    static let incidents = [("medical", "Medical incident"), ("ejection", "Ejection"), ("fire", "Fire"), ("security", "Security incident"), ("other", "Other")]
    static func title(_ key: String) -> String { options.first(where: { $0.0 == key })?.1 ?? key }
}
struct SupervisorReport: View {
    @ObservedObject var model: SupervisorModel
    @State private var add = false
    @State private var sign = false
    var body: some View {
        Screen {
            Panel {
                Text("Supervisor report").font(.title2.bold())
                Text(model.report.text("event_name", fallback: model.shift.shiftTitle)).font(.headline)
                Text(model.report.text("venue", fallback: model.shift.text("venue"))).foregroundStyle(Palette.muted)
                Text(reportTiming).font(.subheadline).foregroundStyle(Palette.muted)
                Badge(text: model.signed ? "Signed" : "Draft")
            }
            if let error = model.error { Notice(text: error) }
            if !model.signed {
                PrimaryButton(title: model.entryDraft != nil ? "Retry pending entry" : "Add log entry", symbol: "plus", enabled: !model.busy && (model.live || model.entryDraft != nil)) {
                    if let pending = model.entryDraft { Task { _ = await model.appendEntry(pending) } } else { add = true }
                }
                if !model.live { Text("New entries are available during your shift only.").font(.caption).foregroundStyle(Palette.muted) }
            }
            ForEach(model.entries) { entry in
                Panel {
                    HStack { Text(String(entry.text("entry_time").suffix(8).prefix(5))).font(.title3.monospacedDigit().bold()).foregroundStyle(Palette.blue); Spacer(); Text(ReportActivity.title(entry.text("activity"))).font(.headline) }
                    if !entry.text("incident_type").isEmpty { Badge(text: entry.text("incident_type")) }
                    if !entry.text("notes").isEmpty { Text(entry.text("notes")) }
                }
            }
            if model.signed {
                Panel {
                    Text("Signed by \(model.report.text("supervisor_name"))").font(.headline)
                    if let data = try? JSONSerialization.data(withJSONObject: model.report.object("signature").raw), let ink = try? JSONDecoder().decode(InkSignature.self, from: data) { SignatureDisplay(signature: ink) }
                    Text(model.report.text("signed_at")).font(.caption).foregroundStyle(Palette.muted)
                    Text("Your report is submitted. Admin can download the signed PDF from Supervisor Records on the website.").font(.subheadline).foregroundStyle(Palette.muted)
                }
            } else {
                PrimaryButton(title: model.finishDraft != nil ? "Retry report submission" : "Finish & sign report", symbol: "signature", enabled: !model.busy && (model.canFinish || model.finishDraft != nil)) { sign = true }
            }
        }.navigationTitle("Shift log").refreshable { await model.refresh() }
            .sheet(isPresented: $add) { NavigationStack { EntryEditor(model: model) } }
            .sheet(isPresented: $sign) { NavigationStack { SignReport(model: model) } }
    }
    private var reportTiming: String {
        guard model.signed else { return model.shift.timing }
        return Row(["shift_date": model.report.text("shift_date", fallback: model.shift.text("shift_date")), "start_time": model.report.text("start_time", fallback: model.shift.text("start_time")), "end_time": model.report.text("end_time", fallback: model.shift.text("end_time"))]).timing
    }
}
struct EntryEditor: View {
    @ObservedObject var model: SupervisorModel
    @Environment(\.dismiss) private var dismiss
    @State private var activity = "staff_briefed"
    @State private var incident = "medical"
    @State private var notes = ""
    @State private var time = Date()
    @State private var clientID = UUID().uuidString
    private var valid: Bool { notes.count <= 10000 && (!["incident", "other"].contains(activity) || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    var body: some View {
        Form {
            Group {
            Section("Activity") { Picker("What happened?", selection: $activity) { ForEach(ReportActivity.options, id: \.0) { Text($0.1).tag($0.0) } } }
            if activity == "incident" { Section("Incident type") { Picker("Incident", selection: $incident) { ForEach(ReportActivity.incidents, id: \.0) { Text($0.1).tag($0.0) } } } }
            Section("When did it happen? · UK time") {
                if let (start, end) = UKTime.interval(model.shift) { DatePicker("Entry time", selection: $time, in: start...end.addingTimeInterval(-1), displayedComponents: [.date, .hourAndMinute]).environment(\.timeZone, UKTime.zone) }
            }
            Section("Notes") { TextEditor(text: $notes).frame(minHeight: 150); Text("\(notes.count)/10000").font(.caption).foregroundStyle(Palette.muted) }
            }.disabled(model.busy || model.entryDraft != nil)
            if let error = model.error { Notice(text: error) }
            PrimaryButton(title: model.entryDraft == nil ? "Save entry" : "Retry same entry", symbol: "checkmark", enabled: !model.busy && (model.entryDraft != nil || valid && model.live)) {
                Task {
                    let payload: [String: Any] = ["client_id": clientID, "activity": activity, "incident_type": activity == "incident" ? incident as Any : NSNull(), "entry_time": UKTime.formatter("yyyy-MM-dd'T'HH:mm':00'").string(from: time), "notes": notes]
                    if await model.appendEntry(payload) { dismiss() }
                }
            }
        }.disabled(model.busy).scrollContentBackground(.hidden).background(Palette.background).navigationTitle("Add log entry")
            .toolbar { Button("Cancel") { dismiss() }.disabled(model.busy) }
            .interactiveDismissDisabled(model.busy || model.entryDraft != nil)
            .onAppear { if let (start, end) = UKTime.interval(model.shift) { time = max(start, min(API.shared.now, end.addingTimeInterval(-60))) } }
    }
}
struct SignReport: View {
    @ObservedObject var model: SupervisorModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false
    var body: some View {
        Screen {
            Text("Finish your report").font(.title.bold())
            Text("Sign with your finger in the white box below.").foregroundStyle(Palette.muted)
            SignaturePad(signature: $model.signature, enabled: !model.busy && model.finishDraft == nil) { model.attested = false }
            HStack {
                Button("Undo") { if !model.signature.strokes.isEmpty { model.signature.strokes.removeLast(); model.attested = false } }
                Spacer(); Button("Clear", role: .destructive) { model.signature = InkSignature(); model.attested = false }
            }.disabled(model.busy || model.finishDraft != nil)
            Toggle("I confirm this report is complete and accurate.", isOn: $model.attested).disabled(model.busy || model.finishDraft != nil)
            if let error = model.error { Notice(text: error) }
            PrimaryButton(title: model.busy ? "Submitting…" : model.finishDraft == nil ? "Sign & submit" : "Retry submission", symbol: "signature", enabled: !model.busy && (model.finishDraft != nil || model.canFinish && model.signature.valid && model.attested)) {
                if model.finishDraft != nil { Task { if await model.finish() { dismiss() } } } else { confirm = true }
            }
            Text("Signing locks the report. Admin receives the report and your signature for the PDF.").font(.caption).foregroundStyle(Palette.muted)
        }.navigationTitle("Supervisor signature").toolbar { Button("Close") { dismiss() }.disabled(model.busy) }
            .interactiveDismissDisabled(model.busy)
            .confirmationDialog("Submit your signed report? It cannot be edited after signing.", isPresented: $confirm, titleVisibility: .visible) { Button("Sign & submit") { Task { if await model.finish() { dismiss() } } } }
    }
}
struct SignatureDisplay: View {
    let signature: InkSignature
    var body: some View {
        Canvas { context, size in
            for stroke in signature.strokes {
                var path = Path()
                for (index, point) in stroke.enumerated() { let value = CGPoint(x: CGFloat(point.x) * size.width, y: CGFloat(point.y) * size.height); if index == 0 { path.move(to: value) } else { path.addLine(to: value) } }
                context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }.aspectRatio(signature.aspect_ratio, contentMode: .fit).background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
struct SignaturePad: View {
    @Binding var signature: InkSignature
    let enabled: Bool
    var changed: () -> Void
    @State private var drawing = false
    var body: some View {
        GeometryReader { geometry in
            SignatureDisplay(signature: signature).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard enabled, signature.pointCount < 6000, geometry.size.width > 0, geometry.size.height > 0 else { return }
                        let point = InkPoint(x: Double((min(1, max(0, value.location.x / geometry.size.width)) * 10000).rounded() / 10000), y: Double((min(1, max(0, value.location.y / geometry.size.height)) * 10000).rounded() / 10000))
                        if !drawing {
                            guard signature.strokes.count < 80 else { return }
                            signature.strokes.append([point]); drawing = true
                        } else { signature.strokes[signature.strokes.count - 1].append(point) }
                        changed()
                    }.onEnded { _ in drawing = false })
        }.aspectRatio(1.6, contentMode: .fit).accessibilityLabel("Supervisor signature canvas")
    }
}

import Foundation
import Combine

struct InkPoint: Codable, Equatable {
    let x: Double
    let y: Double
}
struct InkSignature: Codable, Equatable {
    var version = 1
    var strokes: [[InkPoint]] = []
    var aspect_ratio = 1.6
    var pointCount: Int { strokes.reduce(0) { $0 + $1.count } }
    var valid: Bool {
        let points = strokes.flatMap { $0 }
        guard strokes.count <= 80, points.count >= 12, points.count <= 6000,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { return false }
        let xs = points.map(\.x); let ys = points.map(\.y)
        guard (xs.max()! - xs.min()! >= 0.03) || (ys.max()! - ys.min()! >= 0.03) else { return false }
        let travel = strokes.reduce(0.0) { total, stroke in total + zip(stroke, stroke.dropFirst()).reduce(0.0) { result, pair in result + hypot(pair.0.x - pair.1.x, pair.0.y - pair.1.y) } }
        return travel >= 0.05
    }
    var payload: [String: Any] { ["version": version, "aspect_ratio": aspect_ratio, "strokes": strokes.map { $0.map { ["x": $0.x, "y": $0.y] } }] }
}
@MainActor final class SupervisorModel: ObservableObject {
    @Published var shifts: [Row] = []
    @Published var selected = 0
    @Published var detail = Row()
    @Published var busy = false
    @Published var error: String?
    @Published var notice: String?
    @Published var clock = Date()
    @Published var signature = InkSignature()
    @Published var attested = false
    @Published var entryDraft: [String: Any]?
    @Published var finishDraft: [String: Any]?
    private var timer: AnyCancellable?
    var shift: Row { detail.object("shift") }
    var report: Row { detail.object("report") }
    var signed: Bool { report.text("status") == "signed" }
    var entries: [Row] { detail.rows("entries").sorted { $0.text("entry_time") < $1.text("entry_time") } }
    var records: [Row] { detail.rows("records") }
    var allocated: [Row] { detail.rows("allocated") }
    var live: Bool {
        guard let (start, end) = UKTime.interval(shift) else { return false }
        return clock >= start && clock < end && shift.text("status") != "cancelled" && !signed && finishDraft == nil
    }
    var eventWindow: Bool {
        guard let (start, end) = UKTime.interval(shift) else { return false }
        return clock >= start && UKTime.day(clock) <= UKTime.day(end) && shift.text("status") != "cancelled"
    }
    var canFinish: Bool { !signed && eventWindow && !entries.isEmpty && entryDraft == nil }
    var canScan: Bool { eventWindow && selected > 0 }
    var path: String { "/api/supervisor/shifts/\(selected)" }
    init() {
        timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { @MainActor in self?.clock = API.shared.now }
        }
    }
    func refresh() async {
        guard !busy else { return }; busy = true; defer { busy = false }; error = nil
        do {
            shifts = try await API.shared.call("/api/supervisor/shifts").rows("shifts")
            if !shifts.contains(where: { $0.id == selected }) {
                selected = shifts.first(where: { $0.flag("report_available") || $0.flag("scan_available") })?.id ?? shifts.first?.id ?? 0
            }
            if selected > 0 { try await loadDetail() } else { detail = Row() }
            clock = API.shared.now
        } catch { self.error = error.localizedDescription }
    }
    func select(_ id: Int) async {
        guard !busy && entryDraft == nil && finishDraft == nil else { return }
        selected = id; signature = InkSignature(); attested = false; detail = Row(); error = nil
        busy = true; defer { busy = false }
        do { try await loadDetail() } catch { self.error = error.localizedDescription }
    }
    private func loadDetail() async {
        detail = try await API.shared.call(path); clock = API.shared.now
        if signed { finishDraft = nil; entryDraft = nil; signature = InkSignature(); attested = false }
    }
    func appendEntry(_ payload: [String: Any]) async -> Bool {
        guard !busy && finishDraft == nil else { return false }
        if entryDraft == nil {
            guard live else { error = "Report entries are available during your shift only."; return false }
            entryDraft = payload
        }
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await API.shared.call(path + "/entries", method: "POST", body: entryDraft)
            entryDraft = nil; try await loadDetail(); notice = "Report entry saved."; return true
        } catch {
            if let failure = error as? ServerError, !failure.uncertain { entryDraft = nil }
            self.error = error.localizedDescription
            if entryDraft != nil { self.error = "Delivery is uncertain. Retry the same entry to avoid duplicates.\n" + error.localizedDescription }
            return false
        }
    }
    func finish() async -> Bool {
        guard !busy else { return false }
        if finishDraft == nil {
            guard canFinish && signature.valid && attested else { error = "Draw your signature and confirm the report is complete."; return false }
            finishDraft = ["signature": signature.payload]
        }
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await API.shared.call(path + "/finish", method: "POST", body: finishDraft)
            finishDraft = nil; try await loadDetail(); notice = "Report signed and submitted to Admin."; return true
        } catch {
            if let failure = error as? ServerError, !failure.uncertain { finishDraft = nil }
            self.error = error.localizedDescription
            if finishDraft != nil { self.error = "Submission is uncertain. Retry using the same signature.\n" + error.localizedDescription }
            return false
        }
    }
}

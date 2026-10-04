import XCTest
@testable import SISSSupervisor

final class ContractTests: XCTestCase {
    private let token = "eyJzaWQiOjF9." + String(repeating: "A", count: 43)
    func testCurrentAndLegacyShiftQR() {
        XCTAssertEqual(QRToken.extract(token), token)
        for host in ["yourallsiss.co.uk", "www.yourallsiss.co.uk", "siss.duckdns.org", "allsiss.co.uk", "www.allsiss.co.uk"] {
            XCTAssertEqual(QRToken.extract("https://\(host)/scan?token=\(token)"), token)
        }
    }
    func testMalformedOrForeignQRRejected() {
        for input in ["https://example.com/scan?token=\(token)", "https://yourallsiss.co.uk.evil.com/scan?token=\(token)", "https://evil@yourallsiss.co.uk/scan?token=\(token)", "https://yourallsiss.co.uk/login?token=\(token)", "https://yourallsiss.co.uk/scan?token=\(token)&token=\(token)", "unsigned", token + "!"] {
            XCTAssertNil(QRToken.extract(input), input)
        }
    }
    func testNullableAndDecimalWireFields() {
        let row = Row(["id": 42, "name": NSNull(), "first_name": "Sam", "last_name": "Smith", "pay_rate": "12.50", "sia_expiry": NSNull(), "allocated_to_me": true])
        XCTAssertEqual(row.id, 42); XCTAssertEqual(row.name, "Sam Smith")
        XCTAssertEqual(row.text("pay_rate"), "12.50"); XCTAssertEqual(row.text("sia_expiry"), "")
        XCTAssertTrue(row.flag("allocated_to_me"))
    }
    func testOvernightShiftUsesUKCalendarDay() throws {
        let row = Row(["shift_date": "2026-10-24", "end_date": "2026-10-24", "start_time": "22:00:00", "end_time": "03:00:00"])
        let (start, end) = try XCTUnwrap(UKTime.interval(row))
        XCTAssertEqual(UKTime.day(start), "2026-10-24")
        XCTAssertEqual(UKTime.day(end), "2026-10-25")
        XCTAssertEqual(end.timeIntervalSince(start), 6 * 3600)
    }
    func testSignatureMustContainActualFingerMovement() {
        XCTAssertFalse(InkSignature().valid)
        XCTAssertFalse(InkSignature(strokes: [Array(repeating: InkPoint(x: 0.5, y: 0.5), count: 20)]).valid)
        let points = (0..<30).map { InkPoint(x: Double($0) / 40, y: 0.4 + sin(Double($0)) / 10) }
        XCTAssertTrue(InkSignature(strokes: [points]).valid)
        XCTAssertFalse(InkSignature(strokes: [Array(repeating: points, count: 201).flatMap { $0 }]).valid)
    }
    func testSignatureRoundTripPreservesCanvasRatio() throws {
        let signature = InkSignature(strokes: [[InkPoint(x: 0.1, y: 0.2), InkPoint(x: 0.7, y: 0.8)]])
        let decoded = try JSONDecoder().decode(InkSignature.self, from: JSONSerialization.data(withJSONObject: signature.payload))
        XCTAssertEqual(decoded, signature); XCTAssertEqual(decoded.aspect_ratio, 1.6)
    }
}

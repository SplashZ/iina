import XCTest
@testable import IINA

final class LocalMediaHTTPServerTests: XCTestCase {
  var server: LocalMediaHTTPServer!
  var tempFileURL: URL!

  override func setUp() async throws {
    try await super.setUp()
    server = LocalMediaHTTPServer(port: 0)
    try server.start()
    tempFileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("test_\(UUID().uuidString).bin")
    try Data(repeating: 0xAB, count: 100).write(to: tempFileURL)
  }

  override func tearDown() async throws {
    server.stop()
    try? FileManager.default.removeItem(at: tempFileURL)
    try await super.tearDown()
  }

  func testServesFile200() async throws {
    let path = server.register(fileURL: tempFileURL)
    let url = URL(string: "http://127.0.0.1:\(server.port)\(path)")!
    let (data, response) = try await URLSession.shared.data(from: url)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    XCTAssertEqual(data.count, 100)
  }

  func testReturns404ForUnknownPath() async throws {
    let url = URL(string: "http://127.0.0.1:\(server.port)/media/not-registered")!
    let (_, response) = try await URLSession.shared.data(from: url)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
  }

  func testSupportsRangeRequests() async throws {
    let path = server.register(fileURL: tempFileURL)
    let url = URL(string: "http://127.0.0.1:\(server.port)\(path)")!
    var request = URLRequest(url: url)
    request.setValue("bytes=0-9", forHTTPHeaderField: "Range")
    let (data, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 206)
    XCTAssertEqual(data.count, 10)
  }

  func testUnregisterReturns404() async throws {
    let path = server.register(fileURL: tempFileURL)
    server.unregister(path: path)
    let url = URL(string: "http://127.0.0.1:\(server.port)\(path)")!
    let (_, response) = try await URLSession.shared.data(from: url)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
  }
}

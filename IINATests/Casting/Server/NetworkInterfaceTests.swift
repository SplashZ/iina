import XCTest
@testable import IINA

final class NetworkInterfaceTests: XCTestCase {
  func testReturnValidIPOnConnectedMachine() throws {
    let ip = try NetworkInterface.lanIPAddress()
    let parts = ip.split(separator: ".")
    XCTAssertEqual(parts.count, 4, "应为 IPv4 格式")
    XCTAssertFalse(ip.hasPrefix("127."), "不应是回环地址")
    XCTAssertFalse(ip.hasPrefix("169.254."), "不应是 APIPA 地址")
  }
}

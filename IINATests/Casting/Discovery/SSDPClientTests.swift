import XCTest
@testable import IINA

final class SSDPClientTests: XCTestCase {

  func testMSearchMessageFormat() {
    let msg = SSDPClient.buildMSearchMessage(maxWait: 3)
    XCTAssertTrue(msg.hasPrefix("M-SEARCH * HTTP/1.1\r\n"))
    XCTAssertTrue(msg.contains("HOST: 239.255.255.250:1900\r\n"))
    XCTAssertTrue(msg.contains("MAN: \"ssdp:discover\"\r\n"))
    XCTAssertTrue(msg.contains("ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n"))
    XCTAssertTrue(msg.contains("MX: 3\r\n"))
  }

  func testParsesLocationHeader() {
    let response = "HTTP/1.1 200 OK\r\nLOCATION: http://192.168.1.100:1234/desc.xml\r\n\r\n"
    let url = SSDPClient.parseLocation(from: response)
    XCTAssertEqual(url?.absoluteString, "http://192.168.1.100:1234/desc.xml")
  }

  func testReturnsNilForMissingLocation() {
    let response = "HTTP/1.1 200 OK\r\nST: urn:something\r\n\r\n"
    XCTAssertNil(SSDPClient.parseLocation(from: response))
  }
}

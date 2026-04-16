import XCTest
@testable import IINA

final class DLNADeviceParserTests: XCTestCase {

  let validXML = """
  <?xml version="1.0"?>
  <root xmlns="urn:schemas-upnp-org:device-1-0">
    <device>
      <friendlyName>Samsung TV</friendlyName>
      <UDN>uuid:samsung-tv-001</UDN>
      <serviceList>
        <service>
          <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
          <controlURL>/upnp/control/AVTransport1</controlURL>
        </service>
        <service>
          <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
          <controlURL>/upnp/control/RenderingControl1</controlURL>
        </service>
      </serviceList>
    </device>
  </root>
  """

  func testParsesValidDevice() throws {
    let baseURL = URL(string: "http://192.168.1.100:1234")!
    let device = try XCTUnwrap(DLNADeviceParser.parse(xml: validXML, baseURL: baseURL))
    XCTAssertEqual(device.name, "Samsung TV")
    XCTAssertEqual(device.id, "uuid:samsung-tv-001")
    XCTAssertEqual(device.avTransportControlURL?.absoluteString,
                   "http://192.168.1.100:1234/upnp/control/AVTransport1")
  }

  func testReturnsNilWhenAVTransportMissing() {
    let xml = """
    <?xml version="1.0"?>
    <root xmlns="urn:schemas-upnp-org:device-1-0">
      <device><UDN>uuid:1</UDN>
        <serviceList><service>
          <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
          <controlURL>/rc</controlURL>
        </service></serviceList>
      </device>
    </root>
    """
    let device = DLNADeviceParser.parse(xml: xml, baseURL: URL(string: "http://192.168.1.1")!)
    XCTAssertNil(device, "没有 AVTransport 的设备应被过滤")
  }

  func testReturnsNilOnInvalidXML() {
    let device = DLNADeviceParser.parse(xml: "not xml <<>>",
                                        baseURL: URL(string: "http://192.168.1.1")!)
    XCTAssertNil(device)
  }

  func testFallbackNameForMissingFriendlyName() {
    let xml = """
    <?xml version="1.0"?>
    <root xmlns="urn:schemas-upnp-org:device-1-0">
      <device><UDN>uuid:no-name</UDN>
        <serviceList><service>
          <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
          <controlURL>/av</controlURL>
        </service></serviceList>
      </device>
    </root>
    """
    let device = DLNADeviceParser.parse(xml: xml, baseURL: URL(string: "http://192.168.1.1")!)
    XCTAssertEqual(device?.name, "Unknown Device")
  }
}

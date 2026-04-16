import Foundation
@testable import IINA

final class MockURLSession: URLSessionProtocol {
  var nextData: Data?
  var nextResponse: HTTPURLResponse?
  var nextError: Error?
  var lastRequest: URLRequest?

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    lastRequest = request
    if let e = nextError { throw e }
    let resp = nextResponse ?? HTTPURLResponse(url: request.url!, statusCode: 200,
                                               httpVersion: nil, headerFields: nil)!
    return (nextData ?? Data(), resp)
  }
}

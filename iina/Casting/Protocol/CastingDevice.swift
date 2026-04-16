import Foundation

protocol CastingDevice: AnyObject {
  var id: String { get }
  var name: String { get }
  var type: String { get }
}

import Foundation
import SwiftData

@Model
final class MacroStep: Codable {
  enum StepType: String, Codable {
    case key      // combined key+modifiers
    case mouse    // single button click
    case text     // literal typing
    case delay    // pause
  }

  @Attribute var id: UUID = UUID()
  var type: StepType
  var keyCode: Int?         // for .key or .mouse
  var modifiers: Int        // raw modifier mask
  var text: String?         // for .text
  var delay: TimeInterval?  // for .delay

  init(type: StepType,
       keyCode: Int? = nil,
       modifiers: Int = 0,
       text: String? = nil,
       delay: TimeInterval? = nil)
  {
    self.id = UUID()
    self.type = type
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.text = text
    self.delay = delay
  }
  
  // Codable conformance
  enum CodingKeys: String, CodingKey {
    case id, type, keyCode, modifiers, text, delay
  }
  
  required init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    type = try container.decode(StepType.self, forKey: .type)
    keyCode = try container.decodeIfPresent(Int.self, forKey: .keyCode)
    modifiers = try container.decode(Int.self, forKey: .modifiers)
    text = try container.decodeIfPresent(String.self, forKey: .text)
    delay = try container.decodeIfPresent(TimeInterval.self, forKey: .delay)
  }
  
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(type, forKey: .type)
    try container.encodeIfPresent(keyCode, forKey: .keyCode)
    try container.encode(modifiers, forKey: .modifiers)
    try container.encodeIfPresent(text, forKey: .text)
    try container.encodeIfPresent(delay, forKey: .delay)
  }
} 
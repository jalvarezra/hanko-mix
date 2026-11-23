import Foundation
import Testing
@testable import PAVCore

@Test func parameterSlotDeliversLatestValue() {
    let slot = ParameterSlot(0)
    slot.publish(1)
    slot.publish(2)
    #expect(slot.consumeLatest() == 2)
    #expect(slot.consumeLatest() == 2)
    slot.publish(3)
    #expect(slot.consumeLatest() == 3)
}

@Test func deviceSettingsTruncatesBandsOverTen() throws {
    let bands = (0..<12).map { _ in #"{"type":"peaking","frequency":1000,"gainDB":1,"q":1,"enabled":true}"# }
    let json = #"{"eqEnabled":true,"preampDB":0,"bands":["# + bands.joined(separator: ",") + "]}"
    let decoded = try JSONDecoder().decode(DeviceSettings.self, from: Data(json.utf8))
    #expect(decoded.bands.count == 10)
}

import Testing
import PAVCore
@testable import PAVAudio

private func device(_ uid: String, _ transport: TransportKind) -> OutputDevice {
    OutputDevice(uid: uid, name: uid, transport: transport, sampleRate: 48_000, channels: 2)
}

@Test func airPlayIsNotSelectable() {
    #expect(!DeviceFilter.isSelectableAsAppOutput(device("tv", .airPlay)))
}

@Test func aggregateIsNotSelectable() {
    #expect(!DeviceFilter.isSelectableAsAppOutput(device("multi", .aggregate)))
}

@Test func ownAggregateIsNotSelectable() {
    #expect(!DeviceFilter.isSelectableAsAppOutput(device(Identifiers.aggregateUIDPrefix + "x", .virtual)))
}

@Test func usbAndBluetoothAndBuiltInAreSelectable() {
    for t in [TransportKind.usb, .bluetooth, .builtIn] {
        #expect(DeviceFilter.isSelectableAsAppOutput(device("d", t)))
    }
}

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

@Test func airPlayIsSelectableAsSystemOutput() {
    #expect(DeviceFilter.isSelectableAsSystemOutput(device("tv", .airPlay)))
}

@Test func ownAggregateIsNotSelectableAsSystemOutput() {
    #expect(!DeviceFilter.isSelectableAsSystemOutput(device(Identifiers.aggregateUIDPrefix + "x", .aggregate)))
}

@Test func outputThatCannotBeDefaultIsNotSelectableAsSystemOutput() {
    var d = device("zoom-virtual", .virtual)
    d.canBeDefault = false
    #expect(!DeviceFilter.isSelectableAsSystemOutput(d))
}

@Test func inputThatCannotBeDefaultIsNotSelectableAsSystemInput() {
    let ok = InputDevice(uid: "mic", name: "Mic", transport: .builtIn, volume: 1, volumeSettable: true, muted: false, muteSettable: true)
    var hidden = ok
    hidden.uid = "zoom-mic"
    hidden.canBeDefault = false
    #expect(DeviceFilter.isSelectableAsSystemInput(ok))
    #expect(!DeviceFilter.isSelectableAsSystemInput(hidden))
}

@Test func leftoverAggregatesFromThePreviousNameAreNeverSelectable() {
    let leftover = device("io.github.perappvolume.agg.123", .virtual)
    #expect(!DeviceFilter.isSelectableAsAppOutput(leftover))
    #expect(!DeviceFilter.isSelectableAsSystemOutput(leftover))
    #expect(Identifiers.uidPrefix == "io.github.jalvarezra.hankomix.")
}

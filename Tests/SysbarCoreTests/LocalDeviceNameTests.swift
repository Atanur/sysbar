import Testing
@testable import SysbarCore

@Suite struct LocalDeviceNameTests {
    @Test func aNameIsTrimmedAndKeptShort() {
        #expect(LocalDeviceName.normalized("  Studio  ") == "Studio")
        #expect(LocalDeviceName.normalized(String(repeating: "a", count: 50)).count == LocalDeviceName.maxLength)
        #expect(LocalDeviceName.normalized(" \n ") == "")
    }

    @Test func anEmptyOrMissingNameFallsBackToThisMac() {
        #expect(LocalDeviceName.display("Studio", fallback: "This Mac") == "Studio")
        #expect(LocalDeviceName.display("   ", fallback: "This Mac") == "This Mac")
        #expect(LocalDeviceName.display(nil, fallback: "This Mac") == "This Mac")
    }
}

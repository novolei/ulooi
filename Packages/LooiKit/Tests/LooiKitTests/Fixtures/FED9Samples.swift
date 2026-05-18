import Foundation

enum FED9Samples {
    static let bootComplete = Data([0x11, 0x01, 0x00])

    // M0.5: type 0x01 is 5 bytes: 0x01 followed by four binary contact states.
    // Observed grounded-like state.
    static let binarySensorsGrounded = Data([0x01, 0x01, 0x01, 0x01, 0x01])

    // M0.5: lifting Looi's front toggled byte 1 from 0x01 to 0x00.
    static let binarySensorsFrontLifted = Data([0x01, 0x00, 0x01, 0x01, 0x01])

    // M0.5: type 0x02 samples were observed as 3 bytes.
    static let imuLikeSample = Data([0x02, 0xFF, 0xF8])

    static let touchDown = Data([0x09, 0x01])
    static let touchUp = Data([0x09, 0x00])

    // Existing M1 decoder shape: type 0x01 as bitfield and type 0x02 as 3-axis LE.
    static let legacyBitfieldAllSuspended = Data([0x01, 0x0F])
    static let legacyIMU3Axis = Data([0x02, 0x01, 0x00, 0xFF, 0xFF, 0x00, 0x01])
}

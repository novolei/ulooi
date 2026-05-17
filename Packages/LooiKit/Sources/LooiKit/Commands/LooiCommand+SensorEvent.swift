import Foundation

extension LooiCommand {
    /// FED5 (touch / sensors) + FED9 (cliff / TOF / battery stream) decoded events.
    /// ❓ Wire format incomplete. The M0.5 SenseView records raw bytes;
    /// once the layout is known, fill in typed Touch / Motion / Battery cases
    /// and a `decode(_:)` here.
    enum SensorEvent {
        // Placeholder. Example fillout once probed:
        //
        // struct Touch {
        //     let zone: Zone     // head / chin / back / ...
        //     let intensity: UInt8
        // }
        //
        // static func decode(_ data: Data) -> SensorEvent? { ... }
    }
}

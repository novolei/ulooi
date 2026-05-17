import Foundation
@_exported import LooiKit

/// LooiKitTesting — re-exports `LooiKit` and provides test doubles such as
/// `MockBLETransport`. Tests import `LooiKitTesting` instead of `LooiKit`
/// directly to get both the production API and the mocks in one statement.
public enum LooiKitTesting {
    public nonisolated(unsafe) static let version = LooiKit.version
}

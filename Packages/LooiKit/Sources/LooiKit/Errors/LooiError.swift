import Foundation

/// All errors thrown across LooiKit's public surface.
///
/// Swift 6 Sendability notes:
/// - `connectionFailed` stores the underlying error as a `String`
///   (`error.localizedDescription` captured at the throw site) — `any Error`
///   is not `Sendable`.
/// - `characteristicMissing` and `writeFailed` store the UUID as a `String`
///   (`cbuuid.uuidString`) — `CBUUID` is not `Sendable` in Swift 6 strict mode.
///   Callers capture the string before throwing:
///   `throw .characteristicMissing(char.uuid.uuidString)`
public enum LooiError: Error, LocalizedError, Sendable {
    case bluetoothUnauthorized
    case bluetoothPoweredOff
    case peripheralNotFound(timeout: Duration)
    case connectionFailed(underlyingDescription: String)
    case handshakeFailed(step: HandshakeStep)
    case characteristicMissing(String)          // CBUUID.uuidString
    case writeFailed(String, underlyingDescription: String) // CBUUID.uuidString
    case cliffLocked(directions: CliffState)
    case sessionNotReady(state: SessionState)
    case gestureCancelled

    public var errorDescription: String? {
        switch self {
        case .bluetoothUnauthorized:
            return "蓝牙未授权 — 请到「设置 → 隐私 → 蓝牙」打开 ulooi 的权限。"
        case .bluetoothPoweredOff:
            return "蓝牙已关闭 — 请打开蓝牙。"
        case .peripheralNotFound(let timeout):
            let s = Int(timeout.components.seconds)
            return "在 \(s) 秒内没有找到 Looi — 请确认机器已开机并在身边。"
        case .connectionFailed:
            return "连接 Looi 失败 — 请稍候重试。"
        case .handshakeFailed(let step):
            return "握手中断（\(step)）— Looi 可能掉线了，请重新尝试。"
        case .characteristicMissing(let uuidString):
            return "缺少特征 \(uuidString) — 服务发现可能未完成。"
        case .writeFailed(let uuidString, _):
            return "向 \(uuidString) 写入失败 — 连接可能掉了。"
        case .cliffLocked:
            return "Looi 悬空了 — 放回地面再驱动。"
        case .sessionNotReady(let state):
            return "Looi 未就绪（当前状态：\(state)）"
        case .gestureCancelled:
            return "动作被中止。"
        }
    }
}

extension LooiError {
    /// English fallback strings — useful for log messages and accessibility.
    public nonisolated var englishDescription: String {
        switch self {
        case .bluetoothUnauthorized:
            return "Bluetooth permission not granted."
        case .bluetoothPoweredOff:
            return "Bluetooth is off."
        case .peripheralNotFound(let t):
            return "No Looi found within \(Int(t.components.seconds))s."
        case .connectionFailed:
            return "Failed to connect to Looi."
        case .handshakeFailed(let s):
            return "Handshake interrupted at \(s)."
        case .characteristicMissing(let u):
            return "Missing characteristic \(u)."
        case .writeFailed(let u, _):
            return "Write to \(u) failed."
        case .cliffLocked:
            return "Looi is suspended — put me down to drive."
        case .sessionNotReady(let s):
            return "Session not ready (state: \(s))."
        case .gestureCancelled:
            return "Gesture cancelled."
        }
    }
}

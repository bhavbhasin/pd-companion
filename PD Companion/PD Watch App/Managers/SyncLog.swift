import Foundation

/// `[sync]` diagnostic logging — DEBUG builds only, never ships. `@autoclosure` so the
/// message isn't even evaluated in Release. Watch-target copy of the phone's SyncLog (the
/// two targets are separate modules). Replaces raw `print("[sync] …")` in production.
func syncLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

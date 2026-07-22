import Foundation

/// `[sync]` diagnostic logging — DEBUG builds only, never ships. `@autoclosure` so the
/// message (and its string interpolation) isn't even evaluated in Release. Replaces the raw
/// `print("[sync] …")` calls that were running in production and flooding the console.
func syncLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

import Foundation

#if DEBUG
enum DebugRecordSeed {
    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0026-4000-a000-%012x", n))!
    }
}
#endif

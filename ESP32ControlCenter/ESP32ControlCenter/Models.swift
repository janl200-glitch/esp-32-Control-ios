import Foundation

struct ESPStats: Codable {
    let ip: String
    let ramFree: UInt64
    let fsTotal: UInt64
    let fsUsed: UInt64
    let fsFree: UInt64
    let flash: UInt64
    let sketch: UInt64
    let freeSketch: UInt64
    let cpu: Int
    let rssi: Int
    let uptime: String
}

struct Analytics: Codable {
    let current: Int
    let peak: Int
    let h1: Int
    let h24: Int
    let d30: Int
    let hours: [HourPoint]
}

struct HourPoint: Codable {
    let c: Int
}

struct ESPFile: Codable, Identifiable {
    var id: String { name }
    let name: String
    let size: UInt64
}

struct ESPConfig: Codable {
    let name: String
    let lang: String
    let theme: String
}

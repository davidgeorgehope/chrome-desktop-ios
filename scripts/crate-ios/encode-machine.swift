import Foundation
struct Machine: Codable {
    var id: UUID
    var distributionID: String
    var version: String
    var codename: String?
    var cpuCount: Int
    var memoryGB: Int
    var diskGB: Int
    var diskUsedGB: Double
    var desktop: String
    var display: String
    var architecture: String = "arm64"
    var screenshot: String?
    var lastStarted: Date?
    var imageID: String?
    var cmdline: String?
    var fullWidthInLandscape: Bool?
    var previewDate: Date?
}
let uuid = UUID(uuidString: CommandLine.arguments[1])!
let m = Machine(
    id: uuid,
    distributionID: "debian",
    version: "13",
    codename: nil,
    cpuCount: 4,
    memoryGB: 4,
    diskGB: 32,
    diskUsedGB: 3.489660928,
    desktop: "Xfce",
    display: "1280 × 800",
    screenshot: nil,
    lastStarted: nil,
    imageID: "debian-xfce",
    cmdline: "console=ttyAMA0 root=/dev/vda rw",
    fullWidthInLandscape: true,
    previewDate: nil
)
let data = try JSONEncoder().encode([m])
let out = URL(fileURLWithPath: CommandLine.arguments[2])
try data.write(to: out)
print("wrote \(data.count) bytes")

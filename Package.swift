// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Daylight", platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)], products: [.executable(name: "Daylight", targets: ["Planner"])], targets: [.executableTarget(name: "Planner"), .testTarget(name: "PlannerTests", dependencies: ["Planner"])], swiftLanguageModes: [.v5])

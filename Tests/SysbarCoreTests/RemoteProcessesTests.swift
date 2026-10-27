import Foundation
import Testing
@testable import SysbarCore

@Suite struct RemoteProcessesTests {
    /// The script sends the busiest apps by CPU and then by memory; both lists must survive parsing.
    @Test func keepsTheBusiestAppsByCPUAndByMemory() throws {
        let lines = (1...20).map { "proc=\(Double(21 - $0)) \($0 * 1_000) App \($0)" }
        let raw = try #require(RemoteMetricsParser.parse((["os=Darwin"] + lines).joined(separator: "\n")))

        #expect(raw.processes.count == 16)
        #expect(raw.processes.first?.name == "App 1")
    }

    /// Runs the real script on this Mac: helpers fold into their app, as in Activity Monitor, so
    /// each app appears once, and CPU and memory still come through.
    @Test func onAMacEachAppIsReportedOnceWithItsHelpers() throws {
        let raw = try #require(RemoteMetricsParser.parse(try Self.runScriptLocally()))
        let names = raw.processes.map(\.name)

        #expect(raw.directCPUUsage != nil)
        #expect(!names.isEmpty && names.count <= 16)
        #expect(Set(names).count == names.count)
        #expect(raw.processes.contains { $0.memoryBytes > 0 })
        #expect(!names.contains { $0.hasSuffix(".app") || $0.contains("/") })
    }

    private static func runScriptLocally() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-s"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data(RemoteScript.source.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

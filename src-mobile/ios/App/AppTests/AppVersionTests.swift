import Foundation
import Testing
@testable import App

struct AppVersionTests {
    @Test func includesTheProvidedBuild() {
        #expect(AppVersion.display(version: "3.2.5", build: "286") == "3.2.5 (286)")
        #expect(AppVersion.display(version: "4.0", build: "901.2") == "4.0 (901.2)")
        #expect(AppVersion.display(version: "4.0", build: " 901\n") == "4.0 (901)")
    }

    @Test func missingOrEmptyBuildOmitsParentheses() {
        let builds: [String?] = [nil, "", " \n\t"]
        for build in builds {
            #expect(AppVersion.display(version: "3.2.5", build: build) == "3.2.5")
        }
        #expect(AppVersion.display(version: nil, build: nil) == "1.0")
    }

    @Test func readsTheSuppliedBundleMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let metadata = ["CFBundleShortVersionString": "7.8.9", "CFBundleVersion": "1234"]
        let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        try data.write(to: directory.appendingPathComponent("Info.plist"))
        let bundle = try #require(Bundle(url: directory))
        #expect(AppVersion.display(in: bundle) == "7.8.9 (1234)")
    }
}

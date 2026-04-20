import Foundation
import XCTest

final class InstallScriptTests: XCTestCase {
    func testInstallScriptReplacesInstalledAppAndRelaunches() throws {
        let environment = try makeScriptEnvironment(
            sourceVersion: "1.2.3",
            sourceBundleVersion: "123",
            installedVersion: "0.9.0",
            installedBundleVersion: "9"
        )

        let result = try runInstallScript(environment)

        XCTAssertEqual(result.exitStatus, 0, result.stderr)
        XCTAssertEqual(try plistValue(at: environment.targetAppInfoPlist, key: "CFBundleShortVersionString"), "1.2.3")
        XCTAssertEqual(try plistValue(at: environment.targetAppInfoPlist, key: "CFBundleVersion"), "123")
        XCTAssertEqual(
            try String(contentsOf: environment.openLog, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
            environment.targetApp.path
        )
        let defaultsLog = try String(contentsOf: environment.defaultsLog, encoding: .utf8)
        XCTAssertTrue(defaultsLog.contains("write com.mikelong.codextoolbar gitUpdate.repositoryRoot -string \(environment.repoRoot.path)"))
        XCTAssertTrue(defaultsLog.contains("write com.mikelong.codextoolbar gitUpdate.remoteName -string origin"))
        XCTAssertTrue(defaultsLog.contains("write com.mikelong.codextoolbar gitUpdate.branchName -string main"))
        XCTAssertEqual(hiddenAppArtifactPaths(in: environment.targetDir, prefix: ".CodexToolbar.stage.").count, 0)
        XCTAssertEqual(hiddenAppArtifactPaths(in: environment.targetDir, prefix: ".CodexToolbar.backup.").count, 0)
    }

    func testInstallScriptRestoresPreviousBundleWhenReplacementFails() throws {
        let environment = try makeScriptEnvironment(
            sourceVersion: "1.2.3",
            sourceBundleVersion: "123",
            installedVersion: "0.9.0",
            installedBundleVersion: "9"
        )
        try installFailingMoveShim(into: environment.fakeBinDir, targetAppPath: environment.targetApp.path)

        let result = try runInstallScript(environment)

        XCTAssertNotEqual(result.exitStatus, 0)
        XCTAssertEqual(try plistValue(at: environment.targetAppInfoPlist, key: "CFBundleShortVersionString"), "0.9.0")
        XCTAssertEqual(try plistValue(at: environment.targetAppInfoPlist, key: "CFBundleVersion"), "9")
        XCTAssertFalse(FileManager.default.fileExists(atPath: environment.openLog.path))
        XCTAssertEqual(hiddenAppArtifactPaths(in: environment.targetDir, prefix: ".CodexToolbar.stage.").count, 0)
        XCTAssertEqual(hiddenAppArtifactPaths(in: environment.targetDir, prefix: ".CodexToolbar.backup.").count, 0)
    }

    private func makeScriptEnvironment(
        sourceVersion: String,
        sourceBundleVersion: String,
        installedVersion: String,
        installedBundleVersion: String
    ) throws -> ScriptEnvironment {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexToolbarInstallScriptTests-\(UUID().uuidString)", isDirectory: true)
        let repoRoot = root.appendingPathComponent("repo", isDirectory: true)
        let scriptsDir = repoRoot.appendingPathComponent("scripts", isDirectory: true)
        let resourcesDir = repoRoot.appendingPathComponent("Resources", isDirectory: true)
        let fakeBinDir = root.appendingPathComponent("bin", isDirectory: true)
        let homeDir = root.appendingPathComponent("home", isDirectory: true)
        let targetDir = homeDir.appendingPathComponent("Applications", isDirectory: true)
        let targetApp = targetDir.appendingPathComponent("CodexToolbar.app", isDirectory: true)
        let openLog = root.appendingPathComponent("open.log")
        let defaultsLog = root.appendingPathComponent("defaults.log")

        try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fakeBinDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeDir.appendingPathComponent("Library/Preferences", isDirectory: true), withIntermediateDirectories: true)

        let sourceInstallScript = try String(
            contentsOf: repositoryRoot().appendingPathComponent("scripts/install_app.sh"),
            encoding: .utf8
        )
        try writeExecutable(sourceInstallScript, to: scriptsDir.appendingPathComponent("install_app.sh"))
        try writeExecutable(fakeBuildScript(), to: scriptsDir.appendingPathComponent("build_app.sh"))
        try writeExecutable(fakeOpenScript(), to: fakeBinDir.appendingPathComponent("open"))
        try writeExecutable(fakeDefaultsScript(), to: fakeBinDir.appendingPathComponent("defaults"))
        try writeExecutable("#!/bin/zsh\nexit 1\n", to: fakeBinDir.appendingPathComponent("pgrep"))
        try writeExecutable("#!/bin/zsh\nexit 0\n", to: fakeBinDir.appendingPathComponent("pkill"))

        try makeAppBundle(
            at: targetApp,
            version: installedVersion,
            bundleVersion: installedBundleVersion
        )
        try makeInfoPlist(
            at: resourcesDir.appendingPathComponent("Info.plist"),
            version: sourceVersion,
            bundleVersion: sourceBundleVersion
        )

        return ScriptEnvironment(
            repoRoot: repoRoot,
            fakeBinDir: fakeBinDir,
            homeDir: homeDir,
            targetDir: targetDir,
            targetApp: targetApp,
            targetAppInfoPlist: targetApp.appendingPathComponent("Contents/Info.plist"),
            openLog: openLog,
            defaultsLog: defaultsLog
        )
    }

    private func runInstallScript(_ environment: ScriptEnvironment) throws -> ScriptRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [environment.repoRoot.appendingPathComponent("scripts/install_app.sh").path]
        process.currentDirectoryURL = environment.repoRoot

        var shellEnvironment = ProcessInfo.processInfo.environment
        shellEnvironment["HOME"] = environment.homeDir.path
        shellEnvironment["OPEN_LOG"] = environment.openLog.path
        shellEnvironment["DEFAULTS_LOG"] = environment.defaultsLog.path
        shellEnvironment["PATH"] = "\(environment.fakeBinDir.path):\(shellEnvironment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")"
        process.environment = shellEnvironment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        return ScriptRunResult(
            exitStatus: process.terminationStatus,
            stdout: String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private func installFailingMoveShim(into fakeBinDir: URL, targetAppPath: String) throws {
        let script = """
        #!/bin/zsh
        set -euo pipefail
        if [[ "$#" -ge 2 && "$1" == *".CodexToolbar.stage."* && "$2" == \(shellQuoted(targetAppPath)) ]]; then
          echo "simulated replacement failure" >&2
          exit 1
        fi
        exec /bin/mv "$@"
        """
        try writeExecutable(script, to: fakeBinDir.appendingPathComponent("mv"))
    }

    private func fakeBuildScript() -> String {
        """
        #!/bin/zsh
        set -euo pipefail
        ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
        APP_NAME="CodexToolbar"
        SOURCE_APP="$ROOT_DIR/dist/$APP_NAME.app"
        rm -rf "$SOURCE_APP"
        mkdir -p "$SOURCE_APP/Contents/MacOS"
        cp "$ROOT_DIR/Resources/Info.plist" "$SOURCE_APP/Contents/Info.plist"
        cat >"$SOURCE_APP/Contents/MacOS/$APP_NAME" <<'APP'
        #!/bin/zsh
        exit 0
        APP
        chmod +x "$SOURCE_APP/Contents/MacOS/$APP_NAME"
        echo "Built app bundle:"
        echo "$SOURCE_APP"
        """
    }

    private func fakeOpenScript() -> String {
        """
        #!/bin/zsh
        set -euo pipefail
        echo "$1" >"$OPEN_LOG"
        """
    }

    private func fakeDefaultsScript() -> String {
        """
        #!/bin/zsh
        set -euo pipefail
        printf '%s\\n' "$*" >>"$DEFAULTS_LOG"
        """
    }

    private func makeAppBundle(at appURL: URL, version: String, bundleVersion: String) throws {
        try FileManager.default.createDirectory(
            at: appURL.appendingPathComponent("Contents/MacOS", isDirectory: true),
            withIntermediateDirectories: true
        )
        try makeInfoPlist(
            at: appURL.appendingPathComponent("Contents/Info.plist"),
            version: version,
            bundleVersion: bundleVersion
        )
        try writeExecutable(
            "#!/bin/zsh\nexit 0\n",
            to: appURL.appendingPathComponent("Contents/MacOS/CodexToolbar")
        )
    }

    private func makeInfoPlist(at plistURL: URL, version: String, bundleVersion: String) throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.mikelong.codextoolbar</string>
            <key>CFBundleShortVersionString</key>
            <string>\(version)</string>
            <key>CFBundleVersion</key>
            <string>\(bundleVersion)</string>
        </dict>
        </plist>
        """
        try plist.write(to: plistURL, atomically: true, encoding: .utf8)
    }

    private func writeExecutable(_ contents: String, to fileURL: URL) throws {
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
    }

    private func plistValue(at plistURL: URL, key: String) throws -> String {
        guard
            let dictionary = NSDictionary(contentsOf: plistURL) as? [String: Any],
            let value = dictionary[key] as? String
        else {
            throw NSError(domain: "InstallScriptTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing \(key) in \(plistURL.path)"])
        }

        return value
    }

    private func hiddenAppArtifactPaths(in directory: URL, prefix: String) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }

        return contents.filter { $0.hasPrefix(prefix) }
    }

    private func repositoryRoot() -> URL {
        let fileURL = URL(fileURLWithPath: #filePath)
        return fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private struct ScriptEnvironment {
    let repoRoot: URL
    let fakeBinDir: URL
    let homeDir: URL
    let targetDir: URL
    let targetApp: URL
    let targetAppInfoPlist: URL
    let openLog: URL
    let defaultsLog: URL
}

private struct ScriptRunResult {
    let exitStatus: Int32
    let stdout: String
    let stderr: String
}

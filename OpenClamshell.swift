import AppKit
import CoreGraphics
import Darwin

class OpenClamshell {
  private static let fallbackBrightness: Float = 0.8
  private var savedBrightness: Float = OpenClamshell.fallbackBrightness
  private var isDimmed = false

  private struct DisplayInfo {
    let builtin: CGDirectDisplayID?
    let external: CGDirectDisplayID?
  }

  init() {
    let displayInfo = getDisplayInfo()
    if let builtinID = displayInfo.builtin,
      displayInfo.external != nil,
      getBrightness(for: builtinID) == 0
    {
      isDimmed = true
    }

    handleDisplays()
    NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.handleDisplays()
    }
  }

  private func handleDisplays() {
    let displayInfo = getDisplayInfo()
    guard let builtinID = displayInfo.builtin else { return }
    let hasExternal = displayInfo.external != nil

    if hasExternal, !isDimmed {
      savedBrightness = getBrightness(for: builtinID) ?? Self.fallbackBrightness
      setBrightness(for: builtinID, value: 0)
      configureMirroring(using: displayInfo)
      isDimmed = true
    } else if !hasExternal, isDimmed {
      setBrightness(for: builtinID, value: savedBrightness)
      isDimmed = false
    }
  }

  private func getDisplayInfo() -> DisplayInfo {
    var displayCount: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success else {
      return DisplayInfo(builtin: nil, external: nil)
    }

    var displayIDs = Array(repeating: kCGNullDirectDisplay, count: Int(displayCount))
    guard CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount) == .success else {
      return DisplayInfo(builtin: nil, external: nil)
    }

    let builtin = displayIDs.first { CGDisplayIsBuiltin($0) != 0 }
    let external = displayIDs.first { CGDisplayIsBuiltin($0) == 0 }

    return DisplayInfo(builtin: builtin, external: external)
  }

  private func configureMirroring(using displayInfo: DisplayInfo) {
    guard let builtinID = displayInfo.builtin, let externalID = displayInfo.external else { return }

    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success else { return }

    CGConfigureDisplayOrigin(config, externalID, 0, 0)
    CGConfigureDisplayMirrorOfDisplay(config, builtinID, externalID)

    if CGCompleteDisplayConfiguration(config, .permanently) != .success {
      CGCancelDisplayConfiguration(config)
    }
  }

  private typealias DSSetBrightness = @convention(c) (UInt32, Float) -> Int32
  private typealias DSGetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32

  private struct DisplayServices {
    static var handle: UnsafeMutableRawPointer?
    static var setBrightness: DSSetBrightness?
    static var getBrightness: DSGetBrightness?

    static func load() -> Bool {
      if handle != nil { return true }
      guard
        let h = dlopen(
          "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY
        ),
        let setFunc = dlsym(h, "DisplayServicesSetBrightness"),
        let getFunc = dlsym(h, "DisplayServicesGetBrightness")
      else {
        return false
      }
      handle = h
      setBrightness = unsafeBitCast(setFunc, to: DSSetBrightness.self)
      getBrightness = unsafeBitCast(getFunc, to: DSGetBrightness.self)
      return true
    }
  }

  private func setBrightness(for displayID: CGDirectDisplayID, value: Float) {
    guard DisplayServices.load(), let setFunc = DisplayServices.setBrightness else { return }
    _ = setFunc(displayID, max(0, min(value, 1)))
  }

  private func getBrightness(for displayID: CGDirectDisplayID) -> Float? {
    guard DisplayServices.load(), let getFunc = DisplayServices.getBrightness else { return nil }
    var brightness: Float = 0
    return getFunc(displayID, &brightness) == 0 ? brightness : nil
  }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  private var openClamshell: OpenClamshell?

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    openClamshell = OpenClamshell()
  }
}

struct CLI {
  private static let serviceName = "com.user.openclamshell"
  private static let installPath = "/usr/local/bin/OpenClamshell"
  private static var plistPath: URL? {
    FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
      .appendingPathComponent("LaunchAgents")
      .appendingPathComponent("\(serviceName).plist")
  }

  static func handleArguments() {
    let arguments = CommandLine.arguments
    if arguments.count > 1 {
      switch arguments[1] {
      case "--install":
        install()
      case "--uninstall":
        uninstall()
      default:
        print("Unknown command: \(arguments[1])")
        print("Available commands: --install, --uninstall")
      }
    } else {
      let delegate = AppDelegate()
      NSApplication.shared.delegate = delegate
      NSApplication.shared.run()
    }
  }

  private static func isServiceLoaded() -> Bool {
    let command = "launchctl list | grep -q \(serviceName)"
    return runShellCommand(command) == 0
  }

  private static func install() {
    if isServiceLoaded() {
      print("✓ OpenClamshell service is already installed and loaded.")
      return
    }

    guard let executablePath = Bundle.main.executablePath else {
      print("Error: Could not determine executable path.")
      return
    }

    do {
      let installURL = URL(fileURLWithPath: installPath)
      if FileManager.default.fileExists(atPath: installURL.path) {
        try FileManager.default.removeItem(at: installURL)
      }
      try FileManager.default.copyItem(at: URL(fileURLWithPath: executablePath), to: installURL)
      print("✓ Installed OpenClamshell to \(installPath)")
    } catch {
      print("✗ Error installing executable: \(error.localizedDescription)")
      print("› Please try running the command again with sudo.")
      return
    }

    guard let plistPath = plistPath else {
      print("Error: Could not determine plist path.")
      return
    }

    let plistContent = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>\(serviceName)</string>
        <key>ProgramArguments</key>
        <array>
            <string>\(installPath)</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
    </dict>
    </plist>
    """

    do {
      try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)
      print("✓ Created launchd service file at \(plistPath.path)")
      let status = runShellCommand("launchctl load \(plistPath.path)")
      if status == 0 {
        print("✓ Successfully loaded and started OpenClamshell service.")
        print("✓ Installation complete.")
      } else {
        print("! Warning: Could not load launchd service. It may already be loaded.")
      }
    } catch {
      print("✗ Error writing plist file: \(error.localizedDescription)")
    }
  }

  private static func uninstall() {
    guard let plistPath = plistPath else {
      print("Error: Could not determine plist path.")
      return
    }

    let serviceLoaded = isServiceLoaded()
    let plistExists = FileManager.default.fileExists(atPath: plistPath.path)

    if !serviceLoaded, !plistExists {
      print("✓ OpenClamshell service is not installed.")
      return
    }

    if serviceLoaded {
      print("› Stopping OpenClamshell service...")
      _ = runShellCommand("launchctl unload \(plistPath.path)")
    }

    if plistExists {
      do {
        try FileManager.default.removeItem(at: plistPath)
        print("✓ Removed launchd service file.")
      } catch {
        print("✗ Error removing plist file: \(error.localizedDescription)")
      }
    }

    do {
      try FileManager.default.removeItem(atPath: installPath)
      print("✓ Removed OpenClamshell from \(installPath)")
    } catch {
      print("✗ Error removing executable: \(error.localizedDescription)")
    }

    print("✓ Uninstallation complete.")
  }

  @discardableResult
  private static func runShellCommand(_ command: String) -> Int32 {
    let process = Process()
    process.launchPath = "/bin/zsh"
    process.arguments = ["-c", command]
    process.launch()
    process.waitUntilExit()
    return process.terminationStatus
  }
}

CLI.handleArguments()

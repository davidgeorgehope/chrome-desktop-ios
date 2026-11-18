// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Foundation
#if canImport(StikJIT)
import StikJIT
#endif

// A separate process that attaches StikJIT to the Chrome app. The app cannot
// attach to itself: the attach stops every thread of the target, including
// the one talking to the debugger.
//
// Hosted as a com.apple.ar.viewer extension with a FALSEPREDICATE activation
// rule so only the host app starts it (via NSExtension). Input/output is the
// extension item's userInfo:
//   in:  "pid" (Int) and "pairing" (Data, the pairing file bytes)
//   out: "ok", "summary", "log"
//
// StikJIT.enableJIT is invoked with script .universal and is left running
// until the script detaches, so later TXM prepare-region breakpoints can be
// serviced for the life of the Chrome process.

@objc(DeskBrowserJITHelper)
final class DeskBrowserJITHelper: NSObject, NSExtensionRequestHandling {
  private static let queue = DispatchQueue(
    label: "com.davidhope.deskbrowser.blink.jithelper")

  func beginRequest(with context: NSExtensionContext) {
    let request = (context.inputItems.first as? NSExtensionItem)?.userInfo ?? [:]
    Self.queue.async {
      var lines: [String] = []
      var reply: [String: Any] = [:]
      do {
        let log: (String) -> Void = { lines.append($0) }
        reply["summary"] = try Self.enable(request, log: log)
        reply["ok"] = true
      } catch {
        reply["ok"] = false
        reply["summary"] = (error as? LocalizedError)?.errorDescription ?? "\(error)"
      }
      reply["log"] = lines
      let item = NSExtensionItem()
      item.userInfo = reply
      context.completeRequest(returningItems: [item], completionHandler: nil)
    }
  }

  private static func enable(
    _ request: [AnyHashable: Any], log: @escaping (String) -> Void
  ) throws -> String {
    guard let pid = request["pid"] as? Int, pid > 0 else {
      throw HelperError("no pid to attach to")
    }
    #if canImport(StikJIT)
    return try withPairingFile(request) { pairingURL in
      let started = Date()
      log("attaching to \(pid) with universal.js")
      let library = FileManager.default.urls(
        for: .libraryDirectory, in: .userDomainMask)[0]
      let ddiPaths = DDIPaths.default(
        in: library.appendingPathComponent("StikJIT"))
      try StikJIT.enableJIT(
        targetPID: Int32(pid),
        pairingFile: pairingURL,
        ddiPaths: ddiPaths,
        script: .universal,
        preparationProgress: { stage in
          log("prepare: \(stage)")
          NSLog("deskbrowser-jit: helper prepare: \(stage)")
        },
        progress: { line in
          log(line)
          NSLog("deskbrowser-jit: helper: \(line)")
        })
      return String(
        format: "enableJIT returned after %.1f s",
        Date().timeIntervalSince(started))
    }
    #else
    throw HelperError("this helper was built without StikJIT")
    #endif
  }

  // StikJIT reads the pairing file from a path belonging to this process.
  // The file is deleted as soon as enableJIT returns. Never logged.
  private static func withPairingFile<T>(
    _ request: [AnyHashable: Any], _ body: (URL) throws -> T
  ) throws -> T {
    guard let pairing = request["pairing"] as? Data, !pairing.isEmpty else {
      throw HelperError("no pairing file")
    }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".plist")
    try pairing.write(to: url, options: [.atomic, .completeFileProtection])
    defer { try? FileManager.default.removeItem(at: url) }
    return try body(url)
  }
}

struct HelperError: LocalizedError {
  let errorDescription: String?
  init(_ message: String) { errorDescription = message }
}

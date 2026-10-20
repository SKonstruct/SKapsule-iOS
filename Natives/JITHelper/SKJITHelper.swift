// App extension that enables JIT for SKapsule with StikJIT, so StikDebug is not needed.
//
// A process cannot debug itself (it deadlocks), so SKBuiltinJIT.m starts this extension and
// it attaches to the app's pid over the device's own debug tunnel (LocalDevVPN). An enable
// request only completes once the JIT script has detached, so this process lives exactly as
// long as the debugger does.
import Foundation
import StikJIT

@objc(SKJITHelperHandler)
final class SKJITHelperHandler: NSObject, NSExtensionRequestHandling {
    // StikJIT's calls are synchronous and blocking, and must run in order.
    private static let queue = DispatchQueue(label: "com.skonstruct.skapsule.jithelper")

    func beginRequest(with context: NSExtensionContext) {
        let request = (context.inputItems.first as? NSExtensionItem)?.userInfo?["request"] as? [String: Any] ?? [:]
        Self.queue.async {
            let item = NSExtensionItem()
            item.userInfo = ["reply": Self.handle(request)]
            context.completeRequest(returningItems: [item], completionHandler: nil)
        }
    }

    private static func handle(_ request: [String: Any]) -> [String: Any] {
        func reply(_ ok: Bool, _ message: String) -> [String: Any] {
            var out: [String: Any] = ["ok": ok, "message": message]
            if let txm = StikJIT.isTXMPresent { out["txm"] = txm }
            return out
        }

        let fm = FileManager.default
        // The Developer Disk Image cache lives here, in the extension's own container.
        let root = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("StikJIT", isDirectory: true)
        let paths = DDIPaths.default(in: root)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let op = request["op"] as? String ?? ""
            if op == "reset" {
                try StikJIT.resetCachedDDI(at: paths)
                return reply(true, "The Developer Disk Image cache was cleared.")
            }

            guard let pairing = request["pairing"] as? Data, !pairing.isEmpty else {
                return reply(false, "No pairing file was provided.")
            }
            // The pairing file is a credential for this device: on disk only for this call,
            // and never logged.
            let pairingURL = root.appendingPathComponent("pairing-\(UUID().uuidString).plist")
            try pairing.write(to: pairingURL, options: .atomic)
            defer { try? fm.removeItem(at: pairingURL) }

            switch op {
            case "prepare":
                switch StikJIT.prepareDevice(pairingFile: pairingURL, paths: paths) {
                case .ready:
                    return reply(true, "LocalDevVPN is reachable and the Developer Disk Image is mounted.")
                case .unreachable(let reason):
                    return reply(false, "Couldn't reach the device's debug service: \(reason)")
                case .preparationFailed(let reason):
                    return reply(false, reason)
                @unknown default:
                    return reply(false, "StikJIT returned an unrecognised readiness state.")
                }
            case "enable":
                guard let pid = (request["pid"] as? NSNumber)?.int32Value, let script = request["script"] as? String else {
                    return reply(false, "The JIT request was incomplete.")
                }
                // forceScript stays off: on a device without TXM, StikJIT attaches without the
                // script, which is all JIT needs there.
                try StikJIT.enableJIT(targetPID: pid,
                                      pairingFile: pairingURL,
                                      ddiPaths: paths,
                                      script: .customBase64(script),
                                      progress: { NSLog("[SKJITHelper] %@", $0) })
                return reply(true, "JIT enabled.")
            default:
                return reply(false, "Unknown JIT request '\(op)'.")
            }
        } catch {
            return reply(false, error.localizedDescription)
        }
    }
}

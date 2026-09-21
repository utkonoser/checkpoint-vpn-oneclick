import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum CheckpointAX {
    static let bundleID = "com.checkpoint.eps_vpn.ui"
    static let appPath = "/Applications/Endpoint Security VPN.app"

    private static let connectTitles: Set<String> = [
        "connect", "подключиться", "соединить", "ok", "okay", "continue", "submit",
        "далее", "ок",
    ]

    enum Error: Swift.Error, LocalizedError {
        case notTrusted
        case appNotRunning
        case timeout(String)

        var errorDescription: String? {
            switch self {
            case .notTrusted:
                return "Accessibility permission is required to fill Check Point login fields."
            case .appNotRunning:
                return "Endpoint Security VPN is not running."
            case .timeout(let step):
                return "Timed out waiting for Check Point UI (\(step))."
            }
        }
    }

    static func isTrusted(prompt: Bool) -> Bool {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt,
        ]
        if AXIsProcessTrustedWithOptions(options) { return true }
        return AXIsProcessTrusted()
    }

    /// Ensure the Check Point process is up. Do not wait for a window — `connectGUI` opens the login UI.
    @discardableResult
    static func ensureGUIRunning() async throws -> NSRunningApplication {
        guard FileManager.default.fileExists(atPath: appPath) else { throw Error.appNotRunning }
        if let running = runningApp() {
            running.unhide()
            running.activate()
            return running
        }
        let url = URL(fileURLWithPath: appPath)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            try Task.checkCancellation()
            if let running = runningApp() {
                running.unhide()
                running.activate()
                return running
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return app
    }

    static func fillLogin(username: String, password: String, timeout: TimeInterval = 12) async throws {
        guard isTrusted(prompt: true) else { throw Error.notTrusted }
        let deadline = Date().addingTimeInterval(timeout)
        var lastDump = ""
        var submits = 0

        while Date() < deadline, submits < 4 {
            try Task.checkCancellation()
            activate()
            guard let app = applicationElement() else {
                try await Task.sleep(nanoseconds: 150_000_000)
                continue
            }
            let snapshot = capture(app)
            lastDump = dump(app, indent: 0)

            // Already past login (OTP / connecting UI).
            if !snapshot.isLoginScreen,
               snapshot.passwordField == nil || snapshot.looksLikeChallenge || snapshot.responseField != nil {
                if snapshot.looksLikeChallenge || snapshot.responseField != nil || snapshot.secureFields.count == 1 {
                    return
                }
            }

            guard snapshot.passwordField != nil || !snapshot.secureFields.isEmpty else {
                try await Task.sleep(nanoseconds: 150_000_000)
                continue
            }

            if let userField = snapshot.usernameField {
                let current = attr(userField, kAXValueAttribute as String)
                if current != username {
                    typeInto(userField, username)
                    usleep(80_000)
                }
            }

            let clicked = loginViaSystemEvents(username: username, password: password)
                || submitLoginViaAX(snapshot: snapshot, username: username, password: password)
            guard clicked else {
                try await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            submits += 1

            let watchUntil = Date().addingTimeInterval(3.0)
            while Date() < watchUntil {
                try Task.checkCancellation()
                if let trac = try? TracClient.info(),
                   trac.overall == .connecting || trac.overall == .connected {
                    return
                }
                try await Task.sleep(nanoseconds: 200_000_000)
                guard let app = applicationElement() else { continue }
                let after = capture(app)
                if after.hasAccessDenied {
                    dismissAccessDenied(after)
                    break
                }
                if after.looksLikeChallenge || after.responseField != nil {
                    return
                }
                // Still the login form with an empty password → click did not stick; retry.
                if after.isLoginScreen {
                    let passEmpty = after.secureFields.first.map { attr($0.element, kAXValueAttribute as String).isEmpty } ?? true
                    if passEmpty { break }
                }
                if !after.isLoginScreen { return }
            }
        }
        NSLog("CheckpointAX timeout at login:\n\(lastDump)")
        throw Error.timeout("login")
    }

    private static func submitLoginViaAX(snapshot: Snapshot, username: String, password: String) -> Bool {
        if let userField = snapshot.usernameField {
            typeInto(userField, username)
        }
        guard let passwordField = snapshot.passwordField ?? snapshot.secureFields.first?.element else {
            return false
        }
        typeInto(passwordField, password)
        usleep(200_000)
        if let button = snapshot.connectButton, isEnabled(button) {
            press(button)
            return true
        }
        // Localized / laggy enable: try Return.
        tap(key: 36, flags: [])
        return true
    }

    static func fillChallenge(
        expectedDigits: Int = 6,
        maxAttempts: Int = 3,
        timeout: TimeInterval = 20,
        codeProvider: () -> String
    ) async throws {
        guard isTrusted(prompt: true) else { throw Error.notTrusted }
        let deadline = Date().addingTimeInterval(timeout)
        var lastDump = ""
        var attempts = 0

        while Date() < deadline, attempts < maxAttempts {
            try Task.checkCancellation()
            activate()
            guard let app = applicationElement() else {
                try await Task.sleep(nanoseconds: 150_000_000)
                continue
            }
            var snapshot = capture(app)
            lastDump = dump(app, indent: 0)

            if snapshot.hasAccessDenied {
                dismissAccessDenied(snapshot)
                try await Task.sleep(nanoseconds: 350_000_000)
                continue
            }
            if snapshot.isLoginScreen {
                // Bounced back to login after OTP → auth failed; retry with a fresh code only if we already submitted.
                if attempts > 0 {
                    // Need a full re-login; signal caller by throwing a distinct path — ConnectEngine will re-enter login.
                    throw Error.timeout("challenge-back-to-login")
                }
                try await Task.sleep(nanoseconds: 150_000_000)
                continue
            }
            guard snapshot.looksLikeChallenge || snapshot.responseField != nil || snapshot.textFields.count == 1 else {
                try await Task.sleep(nanoseconds: 150_000_000)
                continue
            }

            let code = codeProvider().trimmingCharacters(in: .whitespacesAndNewlines)
            guard code.count == expectedDigits else {
                try await Task.sleep(nanoseconds: 200_000_000)
                continue
            }

            let submitted = submitChallenge(
                snapshot: snapshot,
                code: code,
                expectedDigits: expectedDigits
            )
            guard submitted else {
                try await Task.sleep(nanoseconds: 250_000_000)
                continue
            }
            attempts += 1

            // One successful click is enough unless Access Denied shows up.
            let watchUntil = Date().addingTimeInterval(2.5)
            while Date() < watchUntil {
                try Task.checkCancellation()
                if let trac = try? TracClient.info(),
                   trac.overall == .connecting || trac.overall == .connected {
                    return
                }
                try await Task.sleep(nanoseconds: 200_000_000)
                guard let app = applicationElement() else { continue }
                snapshot = capture(app)
                if snapshot.hasAccessDenied {
                    dismissAccessDenied(snapshot)
                    // Fresh OTP on next outer-loop attempt.
                    break
                }
                // OTP rejected → back on username/password. Don't treat as success.
                if snapshot.isLoginScreen {
                    throw Error.timeout("challenge-back-to-login")
                }
                if !(snapshot.looksLikeChallenge || snapshot.responseField != nil || snapshot.textFields.count == 1) {
                    return
                }
            }
            if snapshot.hasAccessDenied { continue }
            // Challenge window often stays open while trac connects — stop typing and let ConnectEngine poll.
            return
        }
        NSLog("CheckpointAX timeout at challenge:\n\(lastDump)")
        throw Error.timeout("challenge")
    }

    /// Type OTP once and press Connect. Secure fields hide their value — never treat that as a short code.
    private static func submitChallenge(snapshot: Snapshot, code: String, expectedDigits: Int) -> Bool {
        if challengeViaSystemEvents(code: code) {
            return true
        }
        guard let field = snapshot.responseField
            ?? snapshot.secureFields.last?.element
            ?? snapshot.textFields.last?.element else {
            return false
        }
        typeInto(field, code)
        usleep(150_000)
        // Readable fields only: if we can see a partial value, retype once.
        let visible = attr(field, kAXValueAttribute as String).filter(\.isNumber)
        if !visible.isEmpty, visible.count != expectedDigits {
            typeInto(field, code)
            usleep(150_000)
        }
        if let button = snapshot.connectButton ?? snapshot.okButton, isEnabled(button) {
            press(button)
            return true
        }
        tap(key: 36, flags: []) // Return
        return true
    }

    static func dumpTree() -> String {
        guard let app = applicationElement() else { return "(no Check Point process)" }
        return dump(app, indent: 0)
    }

    private struct Node {
        var element: AXUIElement
        var role: String
        var title: String
        var value: String
        var description: String
        var placeholder: String
    }

    private struct Snapshot {
        var textFields: [Node] = []
        var secureFields: [Node] = []
        var buttons: [Node] = []
        var usernameField: AXUIElement?
        var passwordField: AXUIElement?
        var responseField: AXUIElement?
        var connectButton: AXUIElement?
        var okButton: AXUIElement?
        var looksLikeChallenge = false
        var hasAccessDenied = false
        var labels: [String] = []
        var isLoginScreen: Bool {
            usernameField != nil && passwordField != nil && !looksLikeChallenge
        }
    }

    private static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&error)
        if error != nil { return nil }
        return result?.stringValue
    }

    private static func appleQuote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Check Point enables Connect only after a real keystroke into the password field.
    /// Password is a secure text field; labels may be RU while the button stays "Connect".
    private static func loginViaSystemEvents(username: String, password: String) -> Bool {
        let user = appleQuote(username)
        let pass = appleQuote(password)
        let source = """
        tell application "System Events"
          tell process "Endpoint_Security_VPN"
            set frontmost to true
            if not (exists window 1) then return "no-window"
            tell window 1
              -- Username: named field or first plain text field.
              try
                set value of text field "username field" to \(user)
              on error
                try
                  set value of text field 1 to \(user)
                end try
              end try
              -- Password: secure text field (preferred) or named text field.
              set passFocused to false
              try
                set focused of secure text field 1 to true
                set passFocused to true
              end try
              if passFocused is false then
                try
                  set focused of text field "password field" to true
                  set passFocused to true
                end try
              end if
              if passFocused is false then return "no-password"
            end tell
            delay 0.1
            keystroke "a" using command down
            delay 0.05
            keystroke \(pass)
            delay 0.35
            tell window 1
              set btn to missing value
              try
                if enabled of button "Connect" then set btn to button "Connect"
              end try
              try
                if btn is missing value and enabled of button "Подключиться" then set btn to button "Подключиться"
              end try
              if btn is missing value then return "disabled"
              click btn
              return "clicked"
            end tell
          end tell
        end tell
        """
        return runAppleScript(source) == "clicked"
    }

    private static func challengeViaSystemEvents(code: String) -> Bool {
        let otp = appleQuote(code)
        let source = """
        tell application "System Events"
          tell process "Endpoint_Security_VPN"
            set frontmost to true
            if not (exists window 1) then return "no-window"
            tell window 1
              set n to count of text fields
              if n is 0 then return "no-field"
              set fld to text field n
              set focused of fld to true
            end tell
            delay 0.08
            keystroke "a" using command down
            delay 0.05
            keystroke \(otp)
            delay 0.25
            tell window 1
              if enabled of button "Connect" then
                click button "Connect"
                return "clicked"
              end if
            end tell
            return "disabled"
          end tell
        end tell
        """
        return runAppleScript(source) == "clicked"
    }

    private static func dismissAccessDenied(_ snapshot: Snapshot) {
        if let ok = snapshot.okButton {
            press(ok)
            return
        }
        tap(key: 53, flags: []) // Escape
    }

    private static func runningApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            ?? NSWorkspace.shared.runningApplications.first {
                $0.localizedName == "Endpoint Security VPN"
                    || $0.localizedName == "EndpointConnect"
                    || $0.executableURL?.lastPathComponent == "Endpoint_Security_VPN"
            }
    }

    private static func applicationElement() -> AXUIElement? {
        guard let app = runningApp() else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    private static func hasWindow() -> Bool {
        var names: Set<String> = [
            "Endpoint Security VPN",
            "EndpointConnect",
            "Check Point Endpoint Security VPN",
        ]
        if let localized = runningApp()?.localizedName, !localized.isEmpty {
            names.insert(localized)
        }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return info.contains { window in
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            return layer == 0 && names.contains(owner)
        }
    }

    private static func activate() {
        runningApp()?.activate()
    }

    private static func capture(_ root: AXUIElement) -> Snapshot {
        var snapshot = Snapshot()
        walk(root, parentLabels: [], into: &snapshot)
        if snapshot.labels.contains(where: looksLikeOTP) {
            snapshot.looksLikeChallenge = true
            if snapshot.responseField == nil {
                snapshot.responseField = snapshot.textFields.last?.element ?? snapshot.secureFields.last?.element
            }
        }
        if snapshot.labels.contains(where: looksLikeAccessDenied) {
            snapshot.hasAccessDenied = true
        }
        if snapshot.connectButton == nil {
            snapshot.connectButton = snapshot.buttons.first(where: { isConnectTitle($0.title) })?.element
        }
        if snapshot.okButton == nil {
            snapshot.okButton = snapshot.buttons.first(where: {
                ["ok", "okay", "ок"].contains($0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            })?.element
        }
        return snapshot
    }

    private static func walk(_ element: AXUIElement, parentLabels: [String], into snapshot: inout Snapshot) {
        let role = attr(element, kAXRoleAttribute as String)
        let title = attr(element, kAXTitleAttribute as String)
        let value = attr(element, kAXValueAttribute as String)
        let description = attr(element, kAXDescriptionAttribute as String)
        let placeholder = attr(element, kAXPlaceholderValueAttribute as String)
        let node = Node(element: element, role: role, title: title, value: value, description: description, placeholder: placeholder)
        let labels = parentLabels + [title, description, placeholder, value].filter { !$0.isEmpty }

        if role == kAXStaticTextRole as String || role == "AXStaticText" {
            snapshot.labels.append(value.isEmpty ? title : value)
            if looksLikeResponse(value) || looksLikeResponse(title) || looksLikeOTP(value) || looksLikeOTP(title) {
                snapshot.looksLikeChallenge = true
            }
        }
        if role == kAXTextFieldRole as String {
            snapshot.textFields.append(node)
            let named = title + " " + description + " " + placeholder
            if looksLikeOTP(named) || labels.contains(where: looksLikeOTP) || looksLikeResponse(named) || labels.contains(where: looksLikeResponse) {
                snapshot.responseField = element
                snapshot.looksLikeChallenge = true
            } else if looksLikePassword(named) || labels.contains(where: looksLikePassword) {
                snapshot.passwordField = element
            } else if looksLikeUsername(named) || labels.contains(where: looksLikeUsername) {
                snapshot.usernameField = element
            }
        }
        if role == "AXSecureTextField" {
            snapshot.secureFields.append(node)
            if looksLikeResponse(title) || looksLikeResponse(description) || labels.contains(where: looksLikeResponse) {
                snapshot.responseField = element
                snapshot.looksLikeChallenge = true
            } else if snapshot.passwordField == nil {
                snapshot.passwordField = element
            }
        }
        if role == kAXButtonRole as String {
            snapshot.buttons.append(node)
            if isConnectTitle(title) { snapshot.connectButton = element }
            if ["ok", "okay", "ок"].contains(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                snapshot.okButton = element
            }
        }

        var nextLabels = parentLabels
        if !title.isEmpty { nextLabels.append(title) }
        if role == kAXStaticTextRole as String, !value.isEmpty { nextLabels.append(value) }
        for child in children(element) {
            walk(child, parentLabels: nextLabels, into: &snapshot)
        }
    }

    private static func looksLikeUsername(_ text: String) -> Bool {
        let t = text.lowercased()
        if looksLikePassword(t) || looksLikeOTP(t) { return false }
        return t.contains("username") || t.contains("user name") || t.contains("логин") || t.contains("имя пользователя")
    }

    private static func looksLikePassword(_ text: String) -> Bool {
        let t = text.lowercased()
        if looksLikeOTP(t) { return false }
        return t.contains("password") || t.contains("пароль")
    }

    private static func looksLikeOTP(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("one time") || t.contains("one-time") || t.contains("onetime")
            || t.contains("totp") || t.contains(" otp") || t.hasPrefix("otp")
            || t.contains("однораз")
    }

    private static func looksLikeResponse(_ text: String) -> Bool {
        let t = text.lowercased()
        return looksLikeOTP(t) || t.contains("response") || t.contains("challenge") || t.contains("ответ") || t.contains("token")
    }

    static func looksLikeAccessDenied(_ text: String) -> Bool {
        let t = text.lowercased()
        if t.contains("access denied") || t.contains("authentication failed") || t.contains("auth failed") {
            return true
        }
        if t.contains("denied") && (t.contains("access") || t.contains("login") || t.contains("connection")) {
            return true
        }
        if t.contains("отказ") || t.contains("запрещ") { return true }
        if t.contains("неверн") && (t.contains("парол") || t.contains("код") || t.contains("ответ") || t.contains("данн")) {
            return true
        }
        if t.contains("invalid") && (t.contains("credential") || t.contains("password") || t.contains("response") || t.contains("code")) {
            return true
        }
        return false
    }

    private static func isEnabled(_ element: AXUIElement) -> Bool {
        var value: AnyObject?
        let status = AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value)
        guard status == .success else { return false }
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return false
    }

    private static func isConnectTitle(_ text: String) -> Bool {
        connectTitles.contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func setValue(_ element: AXUIElement, _ string: String) {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, string as CFTypeRef)
    }

    private static func typeInto(_ element: AXUIElement, _ string: String) {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        usleep(50_000)
        setValue(element, string)
        selectAll()
        typeUnicode(string)
    }

    private static func selectAll() {
        tap(key: 0, flags: .maskCommand) // ⌘A
    }

    private static func tap(key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }

    private static func typeUnicode(_ string: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for ch in string.utf16 {
            var char = ch
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
                up.post(tap: .cghidEventTap)
            }
            // Small gap so Check Point does not drop digits under load.
            usleep(12_000)
        }
    }

    private static func press(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        let status = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard status == .success, let list = value as? [AXUIElement] else { return [] }
        return list
    }

    private static func attr(_ element: AXUIElement, _ name: String) -> String {
        var value: AnyObject?
        let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard status == .success else { return "" }
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return ""
    }

    private static func dump(_ element: AXUIElement, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        let role = attr(element, kAXRoleAttribute as String)
        let title = attr(element, kAXTitleAttribute as String)
        let value = attr(element, kAXValueAttribute as String)
        var line = "\(pad)\(role) title=\(title) value=\(value.prefix(40))\n"
        if indent > 12 { return line }
        for child in children(element) {
            line += dump(child, indent: indent + 1)
        }
        return line
    }
}

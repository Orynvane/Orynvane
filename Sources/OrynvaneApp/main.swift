import AppKit
import OrynvaneCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var browserWindow: BrowserWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenus()

        let controller = BrowserWindowController()
        browserWindow = controller
        controller.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let initialAddress = ProcessInfo.processInfo.arguments.dropFirst().first(where: {
            !$0.hasPrefix("-")
        }), let url = URLResolver.address(initialAddress) {
            controller.load(url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func installMenus() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Orynvane", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApplication.shared.mainMenu = mainMenu
    }
}

let application = NSApplication.shared
let applicationDelegate = AppDelegate()
application.setActivationPolicy(.regular)
application.delegate = applicationDelegate
application.run()

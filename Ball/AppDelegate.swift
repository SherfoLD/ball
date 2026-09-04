//
//  AppDelegate.swift
//  Ball
//
//  Created by nate parrott on 1/22/23.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let appController = AppController()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }

        let putAllBallsBackItem = NSMenuItem(
            title: "Put All Balls Back",
            action: #selector(putAllBallsBack(_:)),
            keyEquivalent: ""
        )
        putAllBallsBackItem.target = self
        appMenu.insertItem(putAllBallsBackItem, at: 2)
        appMenu.insertItem(.separator(), at: 3)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // When dock icon is pressed, animate ball from dock pos
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appController.dockIconClicked()
        return false
    }

    @IBAction private func putAllBallsBack(_ sender: Any?) {
        appController.putAllBallsBack()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(putAllBallsBack(_:)) {
            return appController.canPutAllBallsBack
        }
        return true
    }
}

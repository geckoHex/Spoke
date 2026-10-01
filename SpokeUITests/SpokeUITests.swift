//
//  SpokeUITests.swift
//  SpokeUITests
//
//  Created by Beck Orion on 8/27/26.
//

import XCTest

final class SpokeUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testSolidNavigationAndControls() throws {
        let app = XCUIApplication()
        app.launch()

        for title in ["Home", "Ride", "History", "Settings"] {
            let tab = app.buttons[title]
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            tab.tap()
            XCTAssertTrue(tab.isSelected)
        }

        do {
            let developerToggle = app.switches["Enable Developer Mode"]
            XCTAssertTrue(developerToggle.waitForExistence(timeout: 5))
            let originalValue = developerToggle.value as? String
            defer {
                if developerToggle.value as? String != originalValue {
                    developerToggle.tap()
                }
            }
            developerToggle.tap()
            XCTAssertNotEqual(developerToggle.value as? String, originalValue)
            developerToggle.tap()
            XCTAssertEqual(developerToggle.value as? String, originalValue)
        }

        let settingsScreenshot = XCTAttachment(screenshot: app.screenshot())
        settingsScreenshot.name = "Solid Settings"
        settingsScreenshot.lifetime = .keepAlways
        add(settingsScreenshot)

        XCTAssertTrue(app.textFields["Name"].exists)

        app.buttons["Home"].tap()
        let startRide = app.buttons["Start Ride"]
        if startRide.exists {
            XCTAssertLessThanOrEqual(startRide.frame.maxY, app.buttons["Home"].frame.minY)
        }
        let homeScreenshot = XCTAttachment(screenshot: app.screenshot())
        homeScreenshot.name = "Solid Home"
        homeScreenshot.lifetime = .keepAlways
        add(homeScreenshot)

        app.buttons["History"].tap()
        let ride = app.scrollViews.buttons.firstMatch
        guard ride.waitForExistence(timeout: 3) else { return }
        ride.tap()

        let actions = app.buttons["Ride actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.tap()
        app.buttons["Rename Ride"].tap()
        let nameField = app.textFields["Ride name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        app.buttons["Clear ride name"].tap()
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        nameField.typeText("UI check")
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Close"].tap()

        actions.tap()
        app.buttons["Delete Ride"].tap()
        XCTAssertTrue(app.staticTexts["Delete Ride?"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()

        let detailScreenshot = XCTAttachment(screenshot: app.screenshot())
        detailScreenshot.name = "Solid Ride Detail"
        detailScreenshot.lifetime = .keepAlways
        add(detailScreenshot)

        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let destination = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        edge.press(forDuration: 0.1, thenDragTo: destination)
        XCTAssertTrue(ride.waitForExistence(timeout: 5))
        XCTAssertFalse(actions.exists)
    }

    @MainActor
    func testRefinedRideAndSheets() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        func capture(_ name: String) {
            // Let sheet and toolbar transitions finish before capturing their appearance.
            Thread.sleep(forTimeInterval: 1)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let start = app.buttons["Start Ride"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(start.frame.height, 60)
        capture("Refined Home")
        start.tap()

        let pause = app.buttons["Pause Ride"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(pause.frame.height, 60)
        XCTAssertTrue(app.staticTexts["Riding"].waitForExistence(timeout: 10))
        capture("Refined Ride")
        pause.tap()
        let resume = app.buttons["Resume Ride"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Paused"].exists)
        resume.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 5))

        let end = app.buttons["End Ride"]
        end.press(forDuration: 0.2)
        XCTAssertTrue(pause.exists, "A short press must not end the ride")
        end.press(forDuration: 1.3)
        XCTAssertTrue(app.staticTexts["Ride Complete"].waitForExistence(timeout: 5))
        capture("Refined Ride Complete")
        app.buttons["Discard Ride"].tap()
        XCTAssertTrue(app.navigationBars["Discard Ride?"].waitForExistence(timeout: 5))
        capture("Refined Discard Confirmation")
        app.buttons["Cancel"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["History"].isSelected)
        XCTAssertTrue(app.staticTexts["historyTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["historyTitle"].isHittable)
        capture("Refined History")

        app.scrollViews.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["Ride actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Ride actions"].isHittable)
        let banner = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .descendants(matching: .any)["NotificationShortLookView"]
        XCTAssertTrue(banner.waitForNonExistence(timeout: 10))
        capture("Refined Ride Detail")

        let actions = app.buttons["Ride actions"]
        actions.tap()
        XCTAssertTrue(app.navigationBars["Ride Actions"].waitForExistence(timeout: 5))
        capture("Refined Ride Actions")
        app.buttons["Rename Ride"].tap()
        let name = app.textFields["Ride name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        capture("Refined Rename")
        name.tap()
        app.buttons["Clear ride name"].tap()
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        name.typeText("Morning Ride")
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        XCTAssertTrue(app.keyboards.buttons["Done"].waitForExistence(timeout: 5))
        app.keyboards.buttons["Done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Morning Ride"].waitForExistence(timeout: 5))

        actions.tap()
        app.buttons["Add Note"].tap()
        XCTAssertTrue(app.navigationBars["Ride Notes"].waitForExistence(timeout: 5))
        let note = app.textViews["Note"]
        note.tap()
        note.typeText("A quiet morning ride.")
        XCTAssertTrue(app.keyboards.buttons["Done"].waitForExistence(timeout: 5))
        app.keyboards.buttons["Done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        capture("Refined Ride Notes")
        app.buttons["Close"].tap()
        actions.tap()
        app.buttons["Add Note"].tap()
        XCTAssertEqual(app.textViews["Note"].value as? String, "A quiet morning ride.")
        app.buttons["Close"].tap()

        app.buttons["Ride soundtrack"].tap()
        XCTAssertTrue(app.navigationBars["Ride Soundtrack"].waitForExistence(timeout: 5))
        capture("Refined Soundtrack")
        app.buttons["Close"].tap()

        if app.buttons["Replay"].exists {
            app.buttons["Replay"].tap()
            XCTAssertTrue(app.navigationBars["Replay"].waitForExistence(timeout: 5))
            capture("Refined Replay")
            app.buttons["Close"].tap()
        }

        actions.tap()
        app.buttons["Delete Ride"].tap()
        XCTAssertTrue(app.navigationBars["Delete Ride?"].waitForExistence(timeout: 5))
        capture("Refined Delete Confirmation")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Morning Ride"].exists)
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["historyTitle"].waitForExistence(timeout: 5))

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["settingsTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["settingsTitle"].isHittable)
        capture("Refined Settings")
    }
}

//
//  SpokeUITests.swift
//  SpokeUITests
//
//  Created by Beck Orion on 8/27/26.
//

import CoreLocation
import XCTest

final class SpokeUITests: XCTestCase {

    @MainActor
    func testStatsTabShowsMonthlyChartsAndMetrics() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--weather-fixture", "--stats-fixture"]
        app.launch()
        defer { app.terminate() }
        let stats = app.buttons["Stats"]
        XCTAssertTrue(stats.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.buttons["History"].frame.midX, stats.frame.midX)
        XCTAssertLessThan(stats.frame.midX, app.buttons["Settings"].frame.midX)
        stats.tap()
        XCTAssertTrue(app.staticTexts["statsTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Last 30 days"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["statsSpeedChart"].exists)
        let charts = XCTAttachment(screenshot: app.screenshot())
        charts.name = "Stats monthly charts"
        charts.lifetime = .keepAlways
        add(charts)
        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["statsDistanceChart"].exists)
        XCTAssertTrue(app.staticTexts["Your riding"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Peak performance"].exists)
        for label in ["Top speed", "Fastest ride average", "Longest distance", "Longest riding time"] {
            let metric = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
            if !metric.isHittable { app.swipeUp() }
            XCTAssertTrue(metric.isHittable)
            XCTAssertFalse(metric.label.contains("—"))
        }
        let summary = XCTAttachment(screenshot: app.screenshot())
        summary.name = "Stats peak performance"
        summary.lifetime = .keepAlways
        add(summary)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["settingsTitle"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStatsEmptyState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--weather-fixture"]
        app.launch()
        defer { app.terminate() }
        app.buttons["Stats"].tap()
        XCTAssertTrue(app.staticTexts["No rides in the last 30 days"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["statsSpeedChart"].exists)
        XCTAssertFalse(app.staticTexts["Peak performance"].exists)
        app.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["No Rides Yet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSoundEffectsToggleAndMutedRide() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--weather-fixture"]
        app.launch()
        defer { app.terminate() }
        app.buttons["Settings"].tap()

        let sounds = app.switches["Sound effects"]
        XCTAssertTrue(sounds.waitForExistence(timeout: 5))
        XCTAssertEqual(sounds.value as? String, "1")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Sound effects settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // A Form switch's accessibility frame includes its label; tap the trailing control.
        sounds.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(sounds.value as? String, "0")

        app.buttons["Home"].tap()
        app.buttons["Start Ride"].tap()
        let pause = app.buttons["Pause Ride"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        XCTAssertTrue(pause.wait(for: \.isHittable, toEqual: true, timeout: 5))
        app.buttons["End Ride"].press(forDuration: 1.2)
        XCTAssertTrue(app.staticTexts["Ride Complete"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["Settings"].tap()
        XCTAssertEqual(sounds.value as? String, "0")
        sounds.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(sounds.value as? String, "1")
    }

    @MainActor
    func testRideStartTransitionFromBothScreens() throws {
        for tab in ["Home", "Ride"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--weather-fixture"]
            app.launch()
            app.buttons[tab].tap()
            app.buttons["Start Ride"].tap()

            let transition = XCTAttachment(screenshot: app.screenshot())
            transition.name = "Ride start from \(tab)"
            transition.lifetime = .keepAlways
            add(transition)

            let pause = app.buttons["Pause Ride"]
            XCTAssertTrue(pause.waitForExistence(timeout: 10))
            XCTAssertTrue(pause.wait(for: \.isHittable, toEqual: true, timeout: 5))
            XCTAssertTrue(app.buttons["Ride"].isSelected)
            XCTAssertFalse(app.buttons["Start Ride"].exists)
            let destination = XCTAttachment(screenshot: app.screenshot())
            destination.name = "Ride start destination from \(tab)"
            destination.lifetime = .keepAlways
            add(destination)
            pause.tap()
            XCTAssertTrue(app.buttons["Resume Ride"].waitForExistence(timeout: 5))
            let end = app.buttons["End Ride"]
            end.press(forDuration: 0.2)
            XCTAssertTrue(app.buttons["Resume Ride"].exists, "A short hold must not end the ride")
            end.press(forDuration: 1.2)
            XCTAssertTrue(app.staticTexts["Ride Complete"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testRideStartTransitionWithReducedMotion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--weather-fixture", "--reduce-motion"]
        app.launch()
        defer { app.terminate() }
        app.buttons["Start Ride"].tap()
        let pause = app.buttons["Pause Ride"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        XCTAssertTrue(pause.wait(for: \.isHittable, toEqual: true, timeout: 5))
        pause.tap()
        XCTAssertTrue(app.buttons["Resume Ride"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRideRecordsAnOutAndBackRouteWhileMapsIsOpen() throws {
        let device = XCUIDevice.shared
        let previousLocation = device.location
        defer { device.location = previousLocation }
        func setLocation(_ offset: Double) {
            device.location = XCUILocation(location: CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37 + offset, longitude: -122),
                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                timestamp: .now
            ))
        }

        setLocation(0)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--weather-fixture"]
        app.launch()
        defer { app.terminate() }
        app.buttons["Start Ride"].tap()
        XCTAssertTrue(app.staticTexts["Recording"].waitForExistence(timeout: 15))

        let maps = XCUIApplication(bundleIdentifier: "com.apple.Maps")
        maps.activate()
        XCTAssertTrue(maps.wait(for: .runningForeground, timeout: 10))
        for offset in [0.00075, 0.0015, 0.00225, 0.003, 0.00225, 0.0015, 0.00075, 0] {
            setLocation(offset)
            Thread.sleep(forTimeInterval: 7)
            XCTAssertEqual(maps.state, .runningForeground)
        }

        app.activate()
        XCTAssertTrue(app.buttons["Pause Ride"].waitForExistence(timeout: 10))
        // Finishing at the start means a foreground-only recorder would still show zero.
        let distance = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "Distance", "0.4 mi"
        )).firstMatch
        XCTAssertTrue(distance.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Pause Ride"].tap()
        XCTAssertTrue(app.buttons["Resume Ride"].waitForExistence(timeout: 5))
        app.buttons["End Ride"].press(forDuration: 1.2)
        XCTAssertTrue(app.staticTexts["Ride Complete"].waitForExistence(timeout: 5))
    }

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
    func testSpotifyUsesNativeSignIn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["Settings"].tap()

        let signIn = app.buttons["spotifySignIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        XCTAssertTrue(signIn.isHittable)
        XCTAssertFalse(app.textFields["Spotify client ID"].exists)
        XCTAssertFalse(app.secureTextFields["Spotify client secret"].exists)
        XCTAssertFalse(app.secureTextFields["Spotify refresh token"].exists)
        let settings = XCTAttachment(screenshot: app.screenshot())
        settings.name = "Spotify Sign In Settings"
        settings.lifetime = .keepAlways
        add(settings)

        signIn.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let continueButton = springboard.alerts.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        let authentication = XCTAttachment(screenshot: app.screenshot())
        authentication.name = "Native Spotify Authentication"
        authentication.lifetime = .keepAlways
        add(authentication)
        springboard.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        XCTAssertTrue(signIn.isEnabled)
    }

    @MainActor
    func testTabNavigationAndControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ride-fixture", "--weather-fixture"]
        app.launch()
        defer { app.terminate() }

        let tabBar = app.otherElements["spokeTabBar"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertEqual(tabBar.buttons.count, 5)

        for title in ["Home", "Ride", "History", "Stats", "Settings"] {
            let tab = tabBar.buttons[title]
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(tab.frame.width, 44)
            XCTAssertGreaterThanOrEqual(tab.frame.height, 44)
            tab.tap()
            XCTAssertTrue(tab.isSelected)
        }

        do {
            let developerToggle = app.switches["Enable Developer Mode"]
            XCTAssertTrue(developerToggle.waitForExistence(timeout: 5))
            let originalValue = developerToggle.value as? String
            let toggleControl = developerToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
            defer {
                if developerToggle.value as? String != originalValue {
                    toggleControl.tap()
                }
            }
            toggleControl.tap()
            XCTAssertNotEqual(developerToggle.value as? String, originalValue)
            toggleControl.tap()
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
        let historyScreenshot = XCTAttachment(screenshot: app.screenshot())
        historyScreenshot.name = "Ride history rows"
        historyScreenshot.lifetime = .keepAlways
        add(historyScreenshot)
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
    func testTouchTargetsWeatherRecoveryAndSimulatedSpeed() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--weather-fixture"]
        app.launch()
        let attribution = app.links["Apple Weather attribution"]
        XCTAssertTrue(attribution.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(attribution.frame.height, 44)
        let retry = app.buttons["Retry weather"]
        XCTAssertTrue(retry.isHittable)
        retry.tap()
        XCTAssertTrue(app.staticTexts["Weather may be out of date"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["72°F"].exists)
        let weather = XCTAttachment(screenshot: app.screenshot())
        weather.name = "Stale weather and retry"
        weather.lifetime = .keepAlways
        add(weather)

        app.buttons["Settings"].tap()
        let name = app.textFields["Name"]
        name.tap()
        let clear = app.buttons["Clear name"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(clear.frame.width, 44)
        XCTAssertGreaterThanOrEqual(clear.frame.height, 44)
        clear.tap()
        name.typeText("Rider")
        app.keyboards.buttons["Done"].tap()
        XCTAssertFalse(clear.exists)
        let developerMode = app.switches["Enable Developer Mode"]
        developerMode.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(developerMode.value as? String, "1")
        app.buttons["Ride"].tap()
        app.buttons["Start Ride"].tap()
        XCTAssertTrue(app.otherElements["Simulated speed"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testLastRideOpensDetailsAndExplainsTheRoute() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ride-fixture"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Last 7 Days"].waitForExistence(timeout: 5))
        let lastRide = app.buttons["lastRide"]
        XCTAssertTrue(lastRide.waitForExistence(timeout: 5))
        if !lastRide.isHittable { app.scrollViews.firstMatch.swipeUp() }
        lastRide.tap()
        XCTAssertTrue(app.buttons["Ride actions"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(app.buttons["Ride actions"].exists, "Home clock updates must not pop the detail screen")
        XCTAssertTrue(app.staticTexts["Morning Loop"].exists)
        for title in ["Usual / faster", "Slower", "Stopped"] {
            XCTAssertTrue(app.staticTexts[title].exists, "Route must explain \(title)")
        }
        let map = app.descendants(matching: .any)["rideRouteMap"].firstMatch
        for title in ["Start", "Finish"] {
            let marker = app.descendants(matching: .any)["routeEndpoint\(title)"].firstMatch
            XCTAssertTrue(marker.waitForExistence(timeout: 5))
            XCTAssertTrue(map.frame.contains(marker.frame), "\(title) must fit inside the map")
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Route legend and endpoints"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Back"].tap()
        XCTAssertTrue(lastRide.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Home"].isSelected)
    }

    @MainActor
    func testReplayRespectsReducedMotion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ride-fixture", "--reduce-motion"]
        app.launch()
        app.buttons["History"].tap()
        app.scrollViews.buttons.firstMatch.tap()
        app.buttons["Replay"].tap()
        XCTAssertTrue(app.staticTexts["Route overview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["replayPlayback"].exists)
        XCTAssertTrue(app.buttons["Close"].isHittable)
    }

    @MainActor
    func testReplayCanPauseResumeAndStayOpen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ride-fixture"]
        app.launch()
        app.buttons["History"].tap()
        app.scrollViews.buttons.firstMatch.tap()
        app.buttons["Replay"].tap()
        let playback = app.buttons["replayPlayback"]
        XCTAssertTrue(playback.waitForExistence(timeout: 5))
        XCTAssertEqual(playback.label, "Pause")
        playback.tap()
        XCTAssertEqual(playback.label, "Resume")
        let progress = app.progressIndicators["Replay progress"]
        let pausedValue = progress.value as? String
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(progress.value as? String, pausedValue)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Paused route replay"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        playback.tap()
        let finished = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == 'Replay'"), object: playback
        )
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 15), .completed)
        XCTAssertTrue(app.navigationBars["Replay"].exists)
        playback.tap()
        XCTAssertEqual(playback.label, "Pause")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Ride actions"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRideDetailsAtAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ride-fixture", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        for title in ["Home", "Ride", "History", "Stats", "Settings"] {
            XCTAssertLessThanOrEqual(app.buttons[title].frame.height, 80, "Navigation must leave room for content")
        }
        app.buttons["History"].tap()
        app.scrollViews.buttons.firstMatch.tap()
        let content = app.scrollViews["rideDetailContent"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        for title in ["Duration", "Miles", "Time Moving", "Moving Avg."] {
            let label = content.staticTexts[title]
            for _ in 0..<5 where !label.isHittable { content.swipeUp() }
            XCTAssertTrue(label.isHittable, "\(title) must be reachable at the largest text size")
        }
        let soundtrack = app.buttons["Ride soundtrack"]
        for _ in 0..<5 where !content.frame.contains(soundtrack.frame) { content.swipeUp() }
        XCTAssertTrue(soundtrack.isHittable)
        XCTAssertTrue(content.frame.contains(soundtrack.frame))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Accessible ride details"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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

        func assertCompactSheet(endingWith element: XCUIElement, bottomPadding: CGFloat = 12) {
            let content = app.scrollViews["sheetContent"]
            XCTAssertTrue(content.exists)
            XCTAssertTrue(element.isHittable)
            let bottomSpace = content.frame.maxY - element.frame.maxY
            XCTAssertGreaterThanOrEqual(bottomSpace, 0, "Sheet content must not be clipped")
            // The scroll view's accessibility frame includes native bottom safe-area clearance.
            XCTAssertLessThanOrEqual(bottomSpace, 36 + bottomPadding, "Sheet must fit its content without dead space")
        }

        let start = app.buttons["Start Ride"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(start.frame.height, 60)
        capture("Refined Home")
        start.tap()

        let pause = app.buttons["Pause Ride"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(pause.frame.height, 60)
        XCTAssertLessThanOrEqual(pause.frame.maxY, app.otherElements["spokeTabBar"].frame.minY)
        XCTAssertTrue(app.otherElements["rideRecordingStatus"].waitForExistence(timeout: 10))
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
        assertCompactSheet(endingWith: app.buttons["Discard Ride"])
        app.buttons["Discard Ride"].tap()
        XCTAssertTrue(app.navigationBars["Discard Ride?"].waitForExistence(timeout: 5))
        capture("Refined Discard Confirmation")
        assertCompactSheet(endingWith: app.buttons["Cancel"])
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
        assertCompactSheet(endingWith: app.buttons["Delete Ride"])
        app.buttons["Rename Ride"].tap()
        let name = app.textFields["Ride name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        capture("Refined Rename")
        assertCompactSheet(endingWith: app.buttons["Save"])
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
        XCTAssertLessThanOrEqual(note.frame.height, 80, "A short note must not leave a tall empty editor")
        assertCompactSheet(endingWith: note, bottomPadding: 20)
        app.buttons["Close"].tap()
        actions.tap()
        app.buttons["Edit Note"].tap()
        XCTAssertEqual(app.textViews["Note"].value as? String, "A quiet morning ride.")
        app.buttons["Close"].tap()
        let notePreview = app.buttons["rideNotePreview"]
        if !notePreview.isHittable { app.scrollViews["rideDetailContent"].swipeUp() }
        XCTAssertTrue(notePreview.isHittable)
        notePreview.tap()
        XCTAssertTrue(app.textViews["Note"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()

        app.buttons["Ride soundtrack"].tap()
        XCTAssertTrue(app.navigationBars["Ride Soundtrack"].waitForExistence(timeout: 5))
        capture("Refined Soundtrack")
        assertCompactSheet(endingWith: app.staticTexts["No songs were recorded during this ride."])
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
        assertCompactSheet(endingWith: app.buttons["Cancel"])
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

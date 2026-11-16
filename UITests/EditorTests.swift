import XCTest

final class EditorTests: XCTestCase {
    @MainActor
    func testSaveLocationAppliesOnlyToCurrentProject() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-mandala.language", "en"]
        app.launch()
        app.buttons["new-project"].tap()
        let location = app.buttons["project-save-location"]
        XCTAssertTrue(location.waitForExistence(timeout: 10))
        let title = app.textFields["project-title"]
        title.tap()
        title.typeText("Local location " + UUID().uuidString.prefix(8))
        let create = app.buttons["create-project"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: create)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        let defaultLabel = location.label
        XCTAssertTrue(defaultLabel.contains("iCloud Drive") || defaultLabel.contains("On This Device"))

        location.tap()
        app.buttons["save-to-device"].tap()
        XCTAssertTrue(location.label.contains("On This Device"))
        create.tap()
        let close = app.buttons["close-project"]
        XCTAssertTrue(close.waitForExistence(timeout: 15), app.debugDescription)
        close.tap()

        app.buttons["new-project"].tap()
        XCTAssertTrue(location.waitForExistence(timeout: 10))
        XCTAssertEqual(location.label, defaultLabel)
    }

    @MainActor
    func testICloudDocumentRoundTripWithMac() throws {
        let name = ProcessInfo.processInfo.environment["MANDALA_TEST_ICLOUD_PROJECT"] ?? ""
        try XCTSkipUnless(!name.isEmpty, "Set MANDALA_TEST_ICLOUD_PROJECT and edit the test package on Mac.")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-mandala.language", "en"]
        app.launch()
        app.buttons["new-project"].tap()
        let title = app.textFields["project-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText(name)
        let center = app.textFields["project-center"]
        center.tap()
        center.typeText("Written on iPhone")
        let create = app.buttons["create-project"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: create)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
        XCTAssertTrue(app.buttons["project-save-location"].label.contains("iCloud Drive"))
        create.tap()

        let close = app.buttons["close-project"]
        XCTAssertTrue(close.waitForExistence(timeout: 30))
        close.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "project-row", name))
            .firstMatch
        let root = app.buttons.matching(NSPredicate(format: "identifier IN %@",
                                                    ["slot-center", "expanded-4-4"])).firstMatch
        let end = Date().addingTimeInterval(120)
        repeat {
            XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
            row.tap()
            if !root.waitForExistence(timeout: 6) {
                XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
                continue
            }
            if root.label.contains("Written on Mac") { return }
            close.tap()
        } while Date() < end
        XCTFail("The Mac edit did not arrive in the same iCloud project. \(app.debugDescription)")
    }

    @MainActor
    func testEmptyPositionAndAutosaveAcrossLevels() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-mandala.language", "en"]
        app.launch()
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }

        let name = "Editor check " + UUID().uuidString.prefix(8)
        app.buttons["new-project"].tap()
        let title = app.textFields["project-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText(name)
        app.buttons["create-project"].tap()

        let position = app.buttons["slot-top_left"]
        XCTAssertTrue(position.waitForExistence(timeout: 15))
        let emptyLabel = position.label
        XCTAssertTrue(emptyLabel.contains("Top Left"))
        XCTAssertFalse(app.staticTexts["Top Left"].exists)
        position.tap()
        let cellBody = app.textViews["cell-body"]
        XCTAssertTrue(cellBody.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["media-library"].isHittable)
        XCTAssertTrue(app.buttons["media-camera"].isHittable)
        XCTAssertTrue(app.buttons["media-file"].isHittable)
        let back = app.buttons["finish-editing"]
        let compact = back.exists
        if compact { back.tap() }
        else { app.buttons["finish-sidebar-editing"].tap() }
        XCTAssertEqual(position.label, emptyLabel)
        XCTAssertFalse(app.buttons["expand-top_left"].exists)

        position.tap()
        XCTAssertTrue(cellBody.waitForExistence(timeout: 10))
        cellBody.tap()
        XCTAssertFalse(app.textViews["cell-title"].exists)
        cellBody.typeText("\nField notes\nSecond line")
        if compact { back.tap() }
        let expand = app.buttons["expand-top_left"]
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(expand.frame.midX, position.frame.midX)
        XCTAssertLessThan(expand.frame.midY, position.frame.midY)
        expand.tap()
        let up = app.buttons["level-up"]
        XCTAssertTrue(up.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["slot-center"].label.contains("Field notes"))
        up.tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 10))

        app.terminate()
        app.launch()
        let saved = app.buttons.containing(.staticText, identifier: name).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        saved.tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        XCTAssertTrue(position.label.contains("Field notes"))
        XCTAssertFalse(position.label.contains("Second line"))
        XCTAssertFalse(app.staticTexts["Top Left"].exists)
        position.tap()
        let detail = app.staticTexts["cell-detail-body"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        XCTAssertEqual(detail.label, "\nField notes\nSecond line")
    }

    @MainActor
    func testActionOnlyCellShowsInBodyAndPreview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-mandala.language", "en"]
        app.launch()
        let name = "Action check " + UUID().uuidString.prefix(8)
        app.buttons["new-project"].tap()
        let title = app.textFields["project-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText(name)
        app.buttons["create-project"].tap()

        let position = app.buttons["slot-top_left"]
        XCTAssertTrue(position.waitForExistence(timeout: 15))
        position.tap()
        let add = app.buttons["add-action"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let action = app.textFields["action-name"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        action.tap()
        action.typeText("Call the library")
        app.buttons["confirm-action"].tap()
        let back = app.buttons["finish-editing"]
        if back.exists { back.tap() }
        else { app.buttons["finish-sidebar-editing"].tap() }

        XCTAssertTrue(app.buttons["expand-top_left"].waitForExistence(timeout: 10))
        XCTAssertTrue(position.label.contains("Call the library"))
        position.tap()
        let detail = app.staticTexts["cell-detail-action"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        XCTAssertEqual(detail.label, "Call the library")
        XCTAssertFalse(app.staticTexts["cell-detail-body"].exists)
        XCTAssertTrue(app.buttons["Add to Reminders…"].exists)
    }

    @MainActor
    func testImportsPhotoFromSystemPicker() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MANDALA_TEST_PHOTO_FIXTURE"] == "1",
                          "Add a test photo to the test simulator's photo library before running.")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-mandala.language", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let name = "Media check " + UUID().uuidString.prefix(8)
        app.buttons["new-project"].tap()
        let title = app.textFields["project-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText(name)
        app.buttons["create-project"].tap()

        let position = app.buttons["slot-top_left"]
        XCTAssertTrue(position.waitForExistence(timeout: 15))
        position.tap()
        let library = app.buttons["media-library"]
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        library.tap()
        let photo = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH[c] 'Photo,'")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 12), app.debugDescription)
        photo.tap()
        let resource = app.descendants(matching: .any)["editor-resource"].firstMatch
        XCTAssertTrue(resource.waitForExistence(timeout: 20), app.debugDescription)
        if app.buttons["finish-editing"].exists { app.buttons["finish-editing"].tap() }
        else { app.buttons["finish-sidebar-editing"].tap() }
        let expand = app.buttons["expand-top_left"]
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        XCTAssertTrue(position.label.contains("Image"), position.label)
        XCTAssertTrue(position.frame.contains(expand.frame))
        XCTAssertLessThanOrEqual(abs(expand.frame.maxX - position.frame.maxX), 1)
        XCTAssertLessThanOrEqual(abs(expand.frame.minY - position.frame.minY), 1)
        expand.tap()
        let up = app.buttons["level-up"]
        XCTAssertTrue(up.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Image"].exists)
        up.tap()
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        position.tap()
        XCTAssertTrue(app.buttons["cell-detail-inline-image"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["cell-detail-body"].exists)
    }

    @MainActor
    func testLegacyImportAndNavigation() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MANDALA_TEST_LEGACY_FIXTURE"] == "1",
                          "Place sample.mandala in the simulator app's Documents folder before running.")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-mandala.language", "en", "-mandala.fixture", "sample.mandala"]
        app.launch()

        let accept = app.buttons["accept-import"]
        XCTAssertTrue(accept.waitForExistence(timeout: 15), app.debugDescription)
        accept.tap()
        let chapter = app.buttons["slot-top"]
        XCTAssertTrue(chapter.waitForExistence(timeout: 15))
        XCTAssertTrue(chapter.label.contains("Sample topic"), chapter.label)
        app.buttons["expand-top"].tap()
        let section = app.buttons["slot-right"]
        XCTAssertTrue(app.buttons["level-up"].waitForExistence(timeout: 10))
        XCTAssertTrue(section.label.contains("下一层"), section.label)
        app.buttons["expand-right"].tap()
        let center = app.buttons["slot-center"]
        XCTAssertTrue(center.waitForExistence(timeout: 10))
        XCTAssertTrue(center.label.contains("下一层"), center.label)
    }

    @MainActor
    func testLegacyImportUsingSystemFilePicker() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MANDALA_TEST_LEGACY_FIXTURE"] == "1",
                          "Place sample.mandala in the app Documents folder before running.")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-mandala.language", "en", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["open-project"].tap()

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20), app.debugDescription)
        if app.buttons["Recents"].isSelected {
            app.buttons["Browse"].tap()
        }
        let localStorage = app.cells.containing(.staticText, identifier: "On My iPhone").firstMatch
        if localStorage.isHittable {
            localStorage.tap()
        }
        let appFolder = app.cells.containing(.staticText, identifier: "MandalaThink").firstMatch
        if appFolder.isHittable {
            appFolder.tap()
        }
        let result = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH[c] 'sample'")).firstMatch
        if !result.isHittable {
            search.tap()
            search.typeText("sample")
        }
        XCTAssertTrue(result.waitForExistence(timeout: 12), app.debugDescription)
        result.tap()
        let open = app.buttons["DOCPicker.actionButton"]
        if open.exists && open.isEnabled { open.tap() }
        let importButton = app.buttons["accept-import"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 15), app.debugDescription)
        importButton.tap()
        let chapter = app.buttons["slot-top"]
        XCTAssertTrue(chapter.waitForExistence(timeout: 15))
        XCTAssertTrue(chapter.label.contains("Sample topic"), chapter.label)
    }

    @MainActor
    func testReminderLinkOpensSavedActionDirectly() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MANDALA_TEST_REMINDER_FIXTURE"] == "1",
                          "Install the saved reminder-link project fixture in the test library.")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-mandala.language", "en"]
        app.launch()
        XCTAssertTrue(app.buttons["open-project"].waitForExistence(timeout: 10))
        app.terminate()
        let link = try XCTUnwrap(URL(string: "mandala-think://project/project123456/cell/childcell0001/actionid00001"))
        app.open(link)
        let action = app.staticTexts.containing(NSPredicate(format: "label == %@", "Linked action from Reminders")).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(action.isHittable, app.debugDescription)
    }

    @MainActor
    func testHomeListsRecentProjectsAndSupportsSwipeDeletion() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-mandala.language", "en"]
        app.launch()
        XCTAssertTrue(app.navigationBars["MandalaThink"].exists)
        let tag = UUID().uuidString.prefix(8)
        let older = "A Delete check " + tag
        let newer = "Z Recent check " + tag

        for name in [older, newer] {
            app.buttons["new-project"].tap()
            let title = app.textFields["project-title"]
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            title.tap()
            title.typeText(name)
            app.buttons["create-project"].tap()
            let close = app.buttons["close-project"]
            XCTAssertTrue(close.waitForExistence(timeout: 10))
            close.tap()
        }

        let rows = app.buttons.matching(identifier: "project-row")
        let oldRow = rows.containing(.staticText, identifier: older).firstMatch
        XCTAssertTrue(oldRow.waitForExistence(timeout: 10))
        XCTAssertTrue(rows.firstMatch.label.contains(newer))
        oldRow.tap()
        let close = app.buttons["close-project"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        XCTAssertTrue(oldRow.waitForExistence(timeout: 10))
        XCTAssertTrue(rows.firstMatch.label.contains(older))

        app.terminate()
        app.launch()
        XCTAssertTrue(oldRow.waitForExistence(timeout: 10))
        XCTAssertTrue(rows.firstMatch.label.contains(older))
        let rowFrame = oldRow.frame
        oldRow.swipeLeft(velocity: .slow)
        let delete = app.buttons["delete-project"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertEqual(delete.frame.width, 72, accuracy: 2)
        XCTAssertEqual(delete.frame.maxX, rowFrame.maxX, accuracy: 2)
        XCTAssertEqual(delete.frame.midY, rowFrame.midY, accuracy: 1)
        XCTAssertEqual(delete.frame.height, rowFrame.height, accuracy: 2)
        XCTAssertEqual(delete.label, "Delete")
        XCTAssertFalse(delete.staticTexts["Delete"].exists)
        oldRow.swipeRight(velocity: .slow)
        XCTAssertTrue(delete.waitForNonExistence(timeout: 5))
        oldRow.swipeLeft(velocity: .slow)
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let removed = NSPredicate(format: "exists == false")
        expectation(for: removed, evaluatedWith: oldRow)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(rows.firstMatch.label.contains(newer))
    }

    @MainActor
    func testCreatedReminderOpensFromGridAndContainsSourceNotes() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MANDALA_TEST_SYSTEM_REMINDERS"] == "1",
                          "Run only with a disposable simulator Reminders library.")
        continueAfterFailure = false
        let app = XCUIApplication()
        let reminders = XCUIApplication(bundleIdentifier: "com.apple.reminders")
        reminders.launch()
        app.launchArguments = ["-mandala.language", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let name = "Reminder check " + UUID().uuidString.prefix(8)
        app.buttons["new-project"].tap()
        let title = app.textFields["project-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText(name)
        app.buttons["create-project"].tap()

        let tile = app.buttons["slot-top_left"]
        XCTAssertTrue(tile.waitForExistence(timeout: 45), app.debugDescription)
        tile.tap()
        app.buttons["add-action"].tap()
        let action = app.textFields["action-name"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        action.tap()
        action.typeText(name)
        let create = app.buttons["Create Reminder"]
        XCTAssertTrue(create.waitForExistence(timeout: 12), app.debugDescription)
        if !create.isHittable { app.swipeUp() }
        create.tap()
        let open = app.buttons["Open in Reminders"]
        XCTAssertTrue(open.waitForExistence(timeout: 12), app.debugDescription)
        app.buttons["confirm-action"].tap()
        app.buttons["finish-editing"].tap()
        XCTAssertTrue(app.buttons["expand-top_left"].waitForExistence(timeout: 10))
        tile.tap()
        XCTAssertTrue(reminders.wait(for: .runningForeground, timeout: 10))
        let reminder = reminders.cells.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        let source = reminder.links.matching(NSPredicate(format: "label BEGINSWITH %@", "mandala-think://")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 15), reminders.debugDescription)
        let sourceURL = try XCTUnwrap(URL(string: source.label))
        app.terminate()
        app.open(sourceURL)
        let returnedAction = app.staticTexts["cell-detail-action"]
        XCTAssertTrue(returnedAction.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(returnedAction.label, name)
    }

    @MainActor
    func testExpandedGridCanEditBranchAndSaveColor() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-mandala.language", "en"]
        app.launch()
        app.buttons["new-project"].tap()
        let title = app.textFields["project-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText("Nine check " + UUID().uuidString.prefix(8))
        app.buttons["create-project"].tap()
        let nine = app.buttons["board-size-nine"]
        XCTAssertTrue(nine.waitForExistence(timeout: 10))
        nine.tap()
        let centralChild = app.buttons["expanded-4-0"]
        XCTAssertTrue(centralChild.waitForExistence(timeout: 10))
        let canvas = app.scrollViews["expanded-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let topLeft = app.buttons["expanded-0-4"]
        let bottomRightBlock = app.buttons["expanded-8-4"]
        XCTAssertTrue(canvas.frame.contains(topLeft.frame))
        XCTAssertTrue(canvas.frame.contains(bottomRightBlock.frame))
        let fitWidth = centralChild.frame.width
        canvas.pinch(withScale: 2, velocity: 0.7)
        XCTAssertGreaterThan(centralChild.frame.width, fitWidth * 1.25, "Accessibility zoom: \(canvas.value ?? "nil")")
        XCTAssertFalse(app.buttons["edit-cell"].exists)
        let zoomedPosition = centralChild.frame.midX
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertLessThan(centralChild.frame.midX, zoomedPosition - 20)
        app.buttons["board-fit"].tap()
        XCTAssertEqual(centralChild.frame.width, fitWidth, accuracy: 1)
        centralChild.tap()
        let color = app.buttons["cell-color"]
        XCTAssertTrue(color.waitForExistence(timeout: 10))
        color.tap()
        app.buttons["Red"].tap()
        let back = app.buttons["finish-editing"]
        back.tap()

        XCTAssertTrue(app.buttons["expanded-0-4-expand"].waitForExistence(timeout: 10))
        let grandchild = app.buttons["expanded-0-8"]
        XCTAssertTrue(grandchild.isHittable)
        grandchild.tap()
        let body = app.textViews["cell-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 10))
        body.tap()
        body.typeText("Grandchild note")
        back.tap()

        app.buttons["board-size-three"].tap()
        let expand = app.buttons["expand-top_left"]
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        expand.tap()
        let bottomRight = app.buttons["slot-bottom_right"]
        XCTAssertTrue(bottomRight.waitForExistence(timeout: 10))
        XCTAssertTrue(bottomRight.label.contains("Grandchild note"))
        let topLeftSlot = app.buttons["slot-top_left"]
        let gridWidth = topLeftSlot.frame.width
        let list = app.buttons["board-size-list"]
        list.tap()
        XCTAssertGreaterThan(topLeftSlot.frame.width, gridWidth * 2)
        app.buttons["board-size-three"].tap()
        XCTAssertEqual(topLeftSlot.frame.width, gridWidth, accuracy: 1)
        XCTAssertTrue(bottomRight.label.contains("Grandchild note"))
        app.buttons["slot-center"].tap()
        app.buttons["edit-cell"].tap()
        XCTAssertTrue(color.waitForExistence(timeout: 10))
        XCTAssertEqual(color.value as? String, "Red")
    }

    @MainActor
    func testFourLanguageBundles() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for (language, newLabel, openLabel) in [("zh-Hans", "新建", "打开"), ("ja", "新規", "開く"),
                                                ("ko", "새로 만들기", "열기"), ("en", "New", "Open")] {
            app.launchArguments = ["-mandala.language", language]
            app.launch()
            let new = app.buttons["new-project"]
            XCTAssertTrue(new.waitForExistence(timeout: 10), language)
            XCTAssertEqual(new.label, newLabel)
            XCTAssertEqual(app.buttons["open-project"].label, openLabel)
            XCTAssertFalse(app.staticTexts["My Mandalas"].exists)
            XCTAssertFalse(app.buttons["Share Project"].exists)
            app.terminate()
        }
    }
}

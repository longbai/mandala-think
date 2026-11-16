import Foundation
import XCTest
import ZIPFoundation
@testable import MandalaCore

final class FormatTests: XCTestCase {
    func testPlainTextAndSharingRoundTrip() throws {
        let body = "  \"引号\"\r\n\\n\t```\n한\u{2028}e\u{301}\n\n"
        var project = try Project(title: "访谈", center: "訪問")
        let root = project.manifest.rootCellID
        let actionID = try ShortID.generate()
        var cell = Cell(body: body)
        cell.color = .purple
        cell.actions = [.init(id: actionID, title: "Call", notes: body,
                              due: .init(date: "2026-11-20", time: "16:30", timeZone: "Asia/Shanghai"))]
        let id = try project.createChild(in: root, at: .topRight, content: cell)
        try project.move(id, to: root, at: .bottomLeft)
        let restored = try ProjectPackage.readSharingData(ProjectPackage.sharingData(for: project))
        XCTAssertEqual(restored.cells[root]?.child(at: .bottomLeft), id)
        XCTAssertEqual(Array(try XCTUnwrap(restored.cells[id]?.body).utf8), Array(body.utf8))
        XCTAssertEqual(Array(try XCTUnwrap(restored.cells[id]?.actions?.first?.notes).utf8), Array(body.utf8))
        XCTAssertEqual(restored, project)
        XCTAssertEqual(restored.cells[id]?.color, .purple)
        XCTAssertTrue(LegacyMandala.notices(for: project, includeLinks: false).contains(.color(id)))
    }

    func testLegacyDocumentRoundTripByPosition() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "sample", withExtension: "mandala"))
        let project = try LegacyMandala.read(Data(contentsOf: fixture), filename: fixture.lastPathComponent).project
        let root = project.manifest.rootCellID
        let topic = try XCTUnwrap(project.cells[root]?.child(at: .top))
        let note = try XCTUnwrap(project.cells[topic]?.child(at: .right))
        XCTAssertEqual(project.manifest.legacyRootID, 9)
        XCTAssertEqual(project.cells.count, 3)
        XCTAssertEqual(project.cells[topic]?.body, "Sample topic")
        XCTAssertEqual(project.cells[note]?.body, "下一层\nメモ")
        XCTAssertEqual(project.cells[note]?.resources?.first?.kind, .image)
        XCTAssertEqual(project.assets.count, 1)

        let exported = try LegacyMandala.write(project, includeLinks: false)
        let roundTrip = try LegacyMandala.read(exported, filename: fixture.lastPathComponent).project
        XCTAssertEqual(tree(project, root), tree(roundTrip, roundTrip.manifest.rootCellID))
        let restored = try ProjectPackage.readSharingData(ProjectPackage.sharingData(for: project, backup: true))
        XCTAssertEqual(project, restored)
    }

    func testRejectsInvalidTreesAndUntrustedArchivePaths() throws {
        var project = try Project(title: "Test", center: "Center")
        let root = project.manifest.rootCellID
        project.cells[root]?.setChild(root, at: .topLeft)
        XCTAssertThrowsError(try ProjectPackage.makeWrapper(for: project))

        let archive = try Archive(accessMode: .create)
        try ProjectPackage.add("test.mprj/../project.yaml", data: Data("test".utf8), to: archive)
        XCTAssertThrowsError(try ProjectPackage.readSharingData(XCTUnwrap(archive.data)))
    }

    func testRejectsAmbiguousYAML() throws {
        for source in [
            "body: x\nbody: y",
            "body: &name x\nactions: *name",
            "body: !!str x",
            "body: ok\nextra: y",
            "body: ok\n---\nbody: ok",
            "body: ok\ntitle: x"
        ] {
            XCTAssertThrowsError(try YAMLDocument.decode(Cell.self, from: Data(source.utf8), filename: "cell"))
        }
    }

    func testMigratesEarlyBuildTextWithoutLosingEdits() throws {
        let project = try Project(title: "Test", center: "")
        let root = project.manifest.rootCellID
        let attachment = try ShortID.generate() + ".jpeg"
        let action = try ShortID.generate()
        let original = "\r\n   First line \r\n本文\r\n"
        let cases = [
            ("First line", original, original),
            ("Edited title", original, "Edited title\n\n" + original),
            ("Only a title", "", "Only a title"),
            ("", original, original),
            ("e\u{301}", "é\nbody", "e\u{301}\n\né\nbody")
        ]
        for (oldTitle, body, expected) in cases {
            var originalManifest = project.manifest
            originalManifest.schemaVersion = 1
            let cellJSON: [String: Any] = [
                "title": oldTitle, "body": body,
                "actions": [["id": action, "title": "Call"]],
                "resources": [["kind": "image", "path": "assets/" + attachment]]
            ]
            let wrapper = FileWrapper(directoryWithFileWrappers: [
                "project.yaml": FileWrapper(regularFileWithContents: try YAMLDocument.encode(originalManifest)),
                "cells": FileWrapper(directoryWithFileWrappers: [
                    root + ".yaml": FileWrapper(regularFileWithContents: try JSONSerialization.data(withJSONObject: cellJSON))
                ]),
                "assets": FileWrapper(directoryWithFileWrappers: [
                    attachment: FileWrapper(regularFileWithContents: Data([1, 2, 3]))
                ])
            ])
            let upgraded = try ProjectPackage.read(wrapper)
            XCTAssertEqual(upgraded.manifest.schemaVersion, 2)
            let cell = try XCTUnwrap(upgraded.cells[root])
            XCTAssertEqual(Data(cell.body.utf8), Data(expected.utf8))
            XCTAssertEqual(cell.actions?.first?.id, action)
            XCTAssertEqual(upgraded.assets[attachment], Data([1, 2, 3]))

            let encoded = String(decoding: try YAMLDocument.encode(cell), as: UTF8.self)
            XCTAssertFalse(encoded.contains("\n\"title\":"))
            XCTAssertEqual(try ProjectPackage.readSharingData(ProjectPackage.sharingData(for: upgraded)), upgraded)
        }
    }

    func testAtomicPackageOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Sample.mprj")
        var project = try Project(title: "Test", center: "Original")
        try ProjectPackage.makeWrapper(for: project).write(to: url, options: .atomic, originalContentsURL: nil)
        project.cells[project.manifest.rootCellID]?.body = "Updated"
        try ProjectPackage.makeWrapper(for: project).write(to: url, options: .atomic, originalContentsURL: url)
        XCTAssertEqual(try ProjectPackage.readDirectory(url), project)
    }

    private func tree(_ project: Project, _ id: String, _ path: String = "") -> [String: Data] {
        let cell = project.cells[id]!
        var output = [path: Data(cell.body.utf8)]
        for (slot, child) in cell.children ?? [:] { output.merge(tree(project, child, path + "/" + slot)) { _, new in new } }
        for (slot, child) in cell.legacyChildren ?? [:] { output.merge(tree(project, child, path + "/legacy" + slot)) { _, new in new } }
        return output
    }
}

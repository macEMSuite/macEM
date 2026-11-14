//
//  SEMSessionRecord.swift
//  Role: what the window's SEM session did that no room keeps (D-SEM-104): every file the Patterns, Indexing and Maps rooms wrote,
//        with its bytes when it is a picture, and each room's Output lines with the moment each was logged. The rooms keep only their
//        current state and the last export's bytes; the Results room's session rows and the session report read the rest here
//        (`SEMSessionLedger`). Window-wide and not saved, as the rooms' sessions are; composed by `AppState`, which tells it of every
//        export (the room states' `onWritten`) and every line (the sessions' `onEvent`).
//
//        Nothing is recomputed from it: a line is the room's own words, an export the bytes the room wrote.
//

import Foundation
import Observation
import TEMCore

@Observable
final class SEMSessionRecord {
    /// The rooms whose lines are kept.
    enum Room: String, CaseIterable {
        case patterns, indexing, maps
    }

    /// Every file a SEM room wrote this session, in the order written.
    private(set) var exports: [SEMExportedFile] = []
    /// Each room's Output lines, in the order logged.
    private(set) var lines: [Room: [SEMLogLine]] = [:]

    /// The longest side of a picture the record keeps: more than the report draws at a column's width (about 1950 px at 300 dpi for an A4
    /// column is printed sharp at 1600), and a 19433 × 19320 export kept at its own size would cost GBs for the session's life (#619).
    static let figureSide = 1600

    /// A room wrote a file. A picture is kept at most `figureSide` on its longest side, with its own size noted.
    func wrote(_ file: SEMExportedFile) {
        var kept = file
        if let png = file.png, let figure = SEMReportFigure(png: png, caption: "", file: nil),
           let smaller = MacTEMAgentDoor.smaller(png, side: Self.figureSide) {
            kept.png = smaller
            kept.pixelWidth = figure.pixelWidth
            kept.pixelHeight = figure.pixelHeight
        }
        exports.append(kept)
    }

    /// A room logged `text` (an empty line and the "…ing" lines of a run in flight are not kept: the line that ends the run says it).
    func note(_ text: String, in room: Room, at time: Date = Date()) {
        guard !text.isEmpty, !text.hasSuffix("\u{2026}") else { return }
        lines[room, default: []].append(SEMLogLine(time: time, text: text))
    }

    /// The room's lines, in order.
    func lines(of room: Room) -> [SEMLogLine] { lines[room] ?? [] }

    /// The room's lines since the last one that starts with `prefix` (that line included), or all of them when none does: the lines
    /// of the dataset open now, from its "Opened …" line.
    func lines(of room: Room, sinceLastStartingWith prefix: String) -> [SEMLogLine] {
        let all = lines(of: room)
        guard let start = all.lastIndex(where: { $0.text.hasPrefix(prefix) }) else { return all }
        return Array(all[start...])
    }

    /// The last line of the room that starts with `prefix`.
    func lastLine(of room: Room, startingWith prefix: String) -> SEMLogLine? {
        lines(of: room).last { $0.text.hasPrefix(prefix) }
    }
}

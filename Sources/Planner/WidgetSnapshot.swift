import Foundation
import WidgetKit

struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        let title: String
        let date: Date
    }

    let term: String
    let validUntil: Date
    let classes: [Item]
    let deadline: Item?

    static let kind = "StudyFlowNextUp"
    #if os(watchOS)
    static let group = "group.studio.daylight.planner.watch"
    #else
    static let group = "group.studio.daylight.planner"
    #endif

    private static var file: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("widget-snapshot.json")
    }

    static func load() -> Self? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    static func publish(_ snapshot: Self) {
        guard let file, load() != snapshot,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try data.write(to: file, options: .atomic)
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        } catch {
            // A widget remains unavailable until its app group is accessible.
        }
    }
}

#if !os(watchOS) && !WIDGET_EXTENSION
extension Database {
    func widgetSnapshot(term: String, today: Date = .now, calendar: Calendar = .current) -> WidgetSnapshot {
        let start = calendar.startOfDay(for: today)
        let days = (0...7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let items = days.flatMap { day in
            let weekday = (calendar.component(.weekday, from: day) + 5) % 7
            return classes.filter { $0.weekday == weekday && $0.end > $0.start }.compactMap { slot -> WidgetSnapshot.Item? in
                guard let subject = subject(slot.subjectID),
                      let time = calendar.date(byAdding: .minute, value: slot.start, to: day) else { return nil }
                return .init(title: String(subject.name.prefix(120)), date: time)
            }
        }.sorted { $0.date < $1.date }
        let task = tasks.filter { $0.status != .done }.min { $0.due < $1.due }
        return WidgetSnapshot(term: String(term.prefix(80)),
                              validUntil: calendar.date(byAdding: .day, value: 8, to: start) ?? start,
                              classes: items,
                              deadline: task.map { .init(title: String($0.title.prefix(120)), date: $0.due) })
    }
}
#endif

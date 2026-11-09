import SwiftUI
import WidgetKit

struct NextUpEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    var nextClass: WidgetSnapshot.Item? {
        snapshot?.classes.first { $0.date >= date }
    }
}

struct NextUpProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextUpEntry {
        let now = Date.now
        return NextUpEntry(date: now, snapshot: WidgetSnapshot(
            term: "StudyFlow Planner", validUntil: now.addingTimeInterval(86400),
            classes: [.init(title: "Data Analytics", date: now.addingTimeInterval(1800))],
            deadline: .init(title: "ส่งรายงาน", date: now.addingTimeInterval(7200))
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextUpEntry) -> Void) {
        let now = Date.now
        let snapshot = WidgetSnapshot.load().flatMap { $0.validUntil > now ? $0 : nil }
        completion(context.isPreview ? placeholder(in: context) : NextUpEntry(date: now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextUpEntry>) -> Void) {
        let now = Date.now
        guard let snapshot = WidgetSnapshot.load(), snapshot.validUntil > now else {
            completion(Timeline(entries: [NextUpEntry(date: now, snapshot: nil)], policy: .never))
            return
        }
        var entries = [NextUpEntry(date: now, snapshot: snapshot)]
        let horizon = min(snapshot.validUntil, now.addingTimeInterval(86400))
        let transitions = Set(snapshot.classes.map { $0.date.addingTimeInterval(1) })
            .filter { $0 > now && $0 < horizon }.sorted().prefix(32)
        entries += transitions.map { NextUpEntry(date: $0, snapshot: snapshot) }
        if snapshot.validUntil == horizon { entries.append(NextUpEntry(date: horizon, snapshot: nil)) }
        completion(Timeline(entries: entries, policy: .after(horizon)))
    }
}

struct NextUpView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextUpEntry

    var body: some View {
        Group {
            #if os(watchOS) || os(iOS)
            if family == .accessoryInline {
                Label(entry.nextClass?.title ?? entry.snapshot?.deadline?.title ?? "StudyFlow", systemImage: "calendar")
                    .privacySensitive()
            } else {
                content
            }
            #else
            content
            #endif
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(entry.snapshot?.term ?? "StudyFlow", systemImage: "graduationcap")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                .privacySensitive()
            if entry.snapshot != nil {
                row(entry.nextClass, empty: "ไม่มีคาบถัดไป", icon: "calendar")
                row(entry.snapshot?.deadline, empty: "ไม่มีงานค้าง", icon: "checkmark.square")
            } else {
                Text("เปิด StudyFlow เพื่ออัปเดต").font(.caption).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func row(_ item: WidgetSnapshot.Item?, empty: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).accessibilityHidden(true)
            Text(item?.title ?? empty).lineLimit(1)
            if let item {
                Spacer(minLength: 1)
                Text(item.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .font(.caption)
        .privacySensitive()
    }
}

@main
struct NextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.kind, provider: NextUpProvider()) { entry in
            NextUpView(entry: entry)
        }
        .configurationDisplayName("StudyFlow · คาบและงานถัดไป")
        .description("ดูคาบเรียนและงานค้างของเทอมที่เลือก")
        #if os(watchOS)
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
        #elseif os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
        #else
        .supportedFamilies([.systemSmall, .systemMedium])
        #endif
    }
}

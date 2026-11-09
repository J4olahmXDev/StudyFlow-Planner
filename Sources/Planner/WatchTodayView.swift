#if os(watchOS)
import SwiftUI

struct WatchTodayView: View {
    @EnvironmentObject private var watch: WatchSync

    var body: some View {
        NavigationStack {
            if let plan = watch.plan {
                TimelineView(.everyMinute) { context in
                    let today = plan.days.first { Calendar.current.isDate($0.date, inSameDayAs: context.date) }
                    List {
                        Section("Today's schedule") {
                            if let today {
                                if today.entries.isEmpty { Text("No plans today") }
                                ForEach(today.entries) { entry in
                                    entryRow(entry, format: .dateTime.hour().minute())
                                }
                            } else {
                                Text("Open StudyFlow on your iPhone to update the schedule.")
                            }
                        }
                        Section("Deadlines") {
                            if plan.deadlines.isEmpty { Text("No unfinished tasks") }
                            ForEach(plan.deadlines) { entry in
                                entryRow(entry, format: .dateTime.month(.abbreviated).day().hour().minute())
                            }
                        }
                    }
                }
                .navigationTitle("Today")
            } else {
                ScrollView {
                    ContentUnavailableView("Waiting for iPhone", systemImage: "iphone",
                                           description: Text("Open StudyFlow Planner on your paired iPhone."))
                }
                .navigationTitle("Today")
            }
        }
        .task { watch.start() }
    }

    private func entryRow(_ entry: WatchPlan.Entry, format: Date.FormatStyle) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title).font(.headline)
            Text(entry.start, format: format).font(.caption).foregroundStyle(.secondary)
            if !entry.location.isEmpty { Text(entry.location).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}
#endif

import SwiftUI

struct OverviewPage: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.plannerPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Binding var editor: EditorTarget?
    let openTimetable: () -> Void
    let openTasks: () -> Void
    @State private var selectedWeekday: Int?

    private let thai = Locale(identifier: "th_TH")
    private let weekdays = ["จ.", "อ.", "พ.", "พฤ.", "ศ.", "ส.", "อา."]
    private let calendar = Calendar.current

    private var accent: Color { palette.accent(scheme) }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let today = weekday(now)
            let monday = calendar.date(byAdding: .day, value: -today, to: calendar.startOfDay(for: now))!
            let week = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: monday)! }
            let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday)!
            let active = selectedWeekday ?? today
            let classes = store.termDatabase.classes.filter { (0..<7).contains($0.weekday) && $0.end > $0.start }
            let counts = (0..<7).map { day in classes.filter { $0.weekday == day }.count }
            let minutes = classes.reduce(0) { $0 + $1.end - $1.start }
            let progress = store.termDatabase.weeklyTaskProgress(from: monday, to: nextMonday)
            let pending = store.termDatabase.tasks.filter { $0.status != .done }.sorted { $0.due < $1.due }

            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    heading(now: now)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 24) {
                            dailyPage(week, counts: counts, active: active, today: today, now: now)
                                .frame(minWidth: 390)
                            weeklyMargin(classCount: classes.count, minutes: minutes, progress: progress, pending: pending, now: now)
                                .frame(width: 275)
                        }
                        VStack(alignment: .leading, spacing: 24) {
                            dailyPage(week, counts: counts, active: active, today: today, now: now)
                            weeklyMargin(classCount: classes.count, minutes: minutes, progress: progress, pending: pending, now: now)
                        }
                    }
                }
                .padding(.horizontal, 27)
                .padding(.top, 24)
                .padding(.bottom, 27)
            }
        }
    }

    private func heading(now: Date) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("สมุดแพลนเนอร์")
                    .font(.system(size: 12, weight: .semibold, design: palette.titleDesign))
                    .foregroundStyle(.secondary)
                Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(thai)))
                    .font(.system(size: 32, weight: .semibold, design: palette.titleDesign))
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 10)
            Menu("สร้าง", systemImage: "plus") {
                Button("เพิ่มคาบเรียน") {
                    if let subject = store.termDatabase.subjects.first {
                        editor = .slot(ClassSlot(subjectID: subject.id, weekday: selectedWeekday ?? weekday(now),
                                                start: 540, end: 600, room: ""))
                    } else {
                        editor = .subject(Subject(name: "", code: "", teacher: "", color: 0))
                    }
                }
                Button("เพิ่มงาน") {
                    let due = calendar.date(byAdding: .day, value: 1, to: now) ?? now
                    editor = .task(StudyTask(title: "", assigned: now, due: due))
                }
                Button("เพิ่มกิจกรรม") {
                    editor = .event(PlannerEvent(title: "", start: now, end: now.addingTimeInterval(3600)))
                }
                Button("จองช่วงโฟกัส") {
                    editor = .event(PlannerEvent(title: "ช่วงโฟกัส", start: now, end: now.addingTimeInterval(1500)))
                }
                Button("เพิ่มวิชา") { editor = .subject(Subject(name: "", code: "", teacher: "", color: 0)) }
            }
            .fixedSize()
        }
    }

    private func dailyPage(_ week: [Date], counts: [Int], active: Int, today: Int, now: Date) -> some View {
        let date = week[active]
        let items = store.termDatabase.agenda(on: date)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(shortDate(week[0])) – \(shortDate(week[6]))")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("เปิดตารางเรียน", systemImage: "arrow.up.right", action: openTimetable)
                    .font(.caption.weight(.medium)).buttonStyle(.plain).foregroundStyle(accent)
            }
            HStack(spacing: 5) {
                ForEach(week.indices, id: \.self) { index in
                    dayTab(week[index], index: index, count: counts[index], active: index == active, today: index == today)
                }
            }
            Divider()
            HStack {
                Text("กำหนดการ")
                    .font(.system(size: 20, weight: .semibold, design: palette.titleDesign))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(active == today ? "วันนี้" : shortDate(date)).font(.caption).foregroundStyle(.secondary)
            }
            if items.isEmpty {
                Text("วันนี้ยังไม่มีรายการ")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in agendaLine(item, showDate: false) }
                }
            }

            if active == today {
                let upcoming = nextItems(afterToday: now)
                if !upcoming.isEmpty {
                    Text("ถัดจากวันนี้").font(.subheadline.weight(.semibold)).padding(.top, 8)
                    VStack(spacing: 0) {
                        ForEach(upcoming) { item in agendaLine(item, showDate: true) }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.paper(scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.10)).allowsHitTesting(false) }
    }

    private func dayTab(_ date: Date, index: Int, count: Int, active: Bool, today: Bool) -> some View {
        Button { selectedWeekday = index } label: {
            VStack(spacing: 4) {
                Text(weekdays[index]).font(.caption.weight(.medium))
                Text(date.formatted(.dateTime.day().locale(thai)))
                    .font(.system(size: 18, weight: .semibold, design: palette.titleDesign).monospacedDigit())
                Circle().fill(count == 0 ? Color.clear : accent).frame(width: 4, height: 4)
            }
            .foregroundStyle(active ? accent : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(active ? accent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .topTrailing) {
                if today { Circle().fill(accent).frame(width: 4, height: 4).padding(6) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(thai))), \(count) คาบ\(today ? ", วันนี้" : "")")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func agendaLine(_ item: AgendaItem, showDate: Bool) -> some View {
        let isTask = item.taskID != nil && item.eventID == nil
        return VStack(spacing: 0) {
            Divider()
            Button {
                if let event = store.termDatabase.events.first(where: { $0.id == item.eventID }) { editor = .event(event) }
                else if let task = store.termDatabase.tasks.first(where: { $0.id == item.taskID }) { editor = .task(task) }
                else if let slot = store.termDatabase.classes.first(where: { $0.id.uuidString == item.id }) { editor = .slot(slot) }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(time(item.start)).font(.system(size: 14, weight: .semibold).monospacedDigit())
                        if showDate { Text(shortDate(item.start)).font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(width: 62, alignment: .leading)
                    Rectangle().fill(accent.opacity(0.36)).frame(width: 2, height: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(isTask ? "กำหนดส่ง" : [time(item.end), item.detail].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func weeklyMargin(classCount: Int, minutes: Int, progress: WeeklyTaskProgress,
                              pending: [StudyTask], now: Date) -> some View {
        let hours = (Double(minutes) / 60).formatted(.number.precision(.fractionLength(0...1)))
        return VStack(alignment: .leading, spacing: 13) {
            Text("สัปดาห์นี้").font(.system(size: 20, weight: .semibold, design: palette.titleDesign))
                .accessibilityAddTraits(.isHeader)
            Text("\(classCount) คาบ · \(hours) ชั่วโมง").font(.subheadline).foregroundStyle(.secondary)
            Divider()
            Text("งานครบกำหนดสัปดาห์นี้").font(.subheadline.weight(.medium))
            workRing(progress)
            Divider().padding(.vertical, 2)
            HStack {
                Text("งานที่ต้องติดตาม").font(.subheadline.weight(.semibold))
                Spacer()
                Button("ดูทั้งหมด", action: openTasks).font(.caption).buttonStyle(.plain).foregroundStyle(accent)
            }
            if pending.isEmpty {
                Text("ไม่มีงานค้าง").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(pending.prefix(4)) { task in
                HStack(spacing: 8) {
                    Button { store.toggle(task) } label: {
                        Image(systemName: "square").font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ทำงาน \(task.title) เสร็จแล้ว")
                    Button { editor = .task(task) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title).font(.caption.weight(.semibold)).lineLimit(1)
                            Text("\(shortDate(task.due)) · \(time(task.due))")
                                .font(.caption2).foregroundStyle(task.due < now ? .red : .secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 3)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workRing(_ progress: WeeklyTaskProgress) -> some View {
        let track = accent.opacity(0.16)
        return HStack(spacing: 16) {
            ZStack {
                Circle().strokeBorder(track, lineWidth: 10)
                if progress.done > 0 {
                    Circle().inset(by: 5).trim(from: 0, to: progress.fraction)
                        .stroke(accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 3) {
                    Text(progress.total == 0 ? "–" : progress.fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 23, weight: .semibold, design: palette.titleDesign).monospacedDigit())
                    if progress.total > 0 {
                        Text("เสร็จแล้ว").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 91, height: 91)
            .accessibilityHidden(true)

            if progress.total == 0 {
                Text("ไม่มีงานครบกำหนด")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ringLegend("เสร็จ", count: progress.done, color: accent)
                    ringLegend("เหลือ", count: progress.remaining, color: track)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.total == 0 ? "ไม่มีงานครบกำหนดสัปดาห์นี้" :
                            "เสร็จ \(progress.done) จาก \(progress.total) งาน เหลือ \(progress.remaining) งาน")
    }

    private func ringLegend(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
            Text("\(count) งาน").fontWeight(.semibold).monospacedDigit()
        }
        .font(.subheadline)
    }

    private func nextItems(afterToday now: Date) -> [AgendaItem] {
        let items = (1...7).compactMap { calendar.date(byAdding: .day, value: $0, to: now) }.flatMap { day in
            store.termDatabase.agenda(on: day).filter {
                ($0.eventID != nil || $0.taskID == nil) && calendar.isDate($0.start, inSameDayAs: day)
            }
        }
        return Array(items.prefix(2))
    }

    private func weekday(_ date: Date) -> Int { (calendar.component(.weekday, from: date) + 5) % 7 }
    private func shortDate(_ date: Date) -> String { date.formatted(.dateTime.day().month(.abbreviated).locale(thai)) }
    private func time(_ date: Date) -> String { date.formatted(.dateTime.hour().minute().locale(thai)) }
}

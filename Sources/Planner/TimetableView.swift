import SwiftUI

struct TimetableView: View {
    private enum Mode: String, CaseIterable {
        case week = "สัปดาห์", day = "วัน", month = "เดือน", list = "รายการ"
    }

    @EnvironmentObject var store: PlannerStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.plannerPalette) private var palette
    @Binding var editor: EditorTarget?
    let soft: Bool
    let term: String
    let showDemo: Bool
    let openTasks: () -> Void
    let openProfile: () -> Void
    let openShare: () -> Void
    let openTerms: () -> Void

    @AppStorage("planner.taskRail") private var showRail = true
    @State private var mode = Mode.week
    @State private var date = Date()
    @State private var choosingDate = false
    @State private var showingReminders = false
    @State private var searching = false
    @State private var search = ""

    private let calendar = Calendar.current
    private let thai = Locale(identifier: "th_TH")
    private let weekdays = ["จันทร์", "อังคาร", "พุธ", "พฤหัสบดี", "ศุกร์", "เสาร์", "อาทิตย์"]
    private let labelWidth: CGFloat = 96
    private let headerHeight: CGFloat = 54

    private var weekStart: Date { adding(.day, -weekday(date), to: calendar.startOfDay(for: date)) }
    private var weekEnd: Date { adding(.day, 7, to: weekStart) }
    private var weekDays: [Date] {
        (0..<7).map { adding(.day, $0, to: weekStart) }
    }
    private var firstHour: Int { min(8, max(0, (store.termDatabase.classes.map(\.start).min() ?? 480) / 60)) }
    private var lastHour: Int { max(18, min(24, ((store.termDatabase.classes.map(\.end).max() ?? 1080) + 59) / 60)) }
    private var gridBorder: Color { .primary.opacity(scheme == .dark ? 0.16 : 0.085) }
    private var surface: Color { palette.paper(scheme) }
    private var openAssignments: [StudyTask] {
        store.termDatabase.tasks.filter { $0.status != .done }.sorted { $0.due < $1.due }
    }

    var body: some View {
        GeometryReader { geometry in
            let railFits = geometry.size.width >= 925
            VStack(alignment: .leading, spacing: 14) {
                #if os(iOS)
                if geometry.size.width < 620 {
                    compactHeader
                } else {
                    header(wide: geometry.size.width >= 720)
                }
                #else
                header(wide: geometry.size.width >= 720)
                #endif
                controls(railFits: railFits, compact: geometry.size.width < 520)
                if searching {
                    TextField("ค้นหาชื่อหรือรหัสวิชา", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("ค้นหาวิชา")
                }
                HStack(alignment: .top, spacing: 13) {
                    Group {
                        switch mode {
                        case .week: timeline(days: weekDays)
                        case .day: timeline(days: [date])
                        case .month: month
                        case .list: agenda(days: weekDays)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if railFits && showRail {
                        ScrollView { taskRail }
                            .frame(width: soft ? 222 : 200)
                    }
                }
            }
            .padding(.horizontal, soft ? 17 : 13)
            .padding(.top, 19)
            .padding(.bottom, 23)
        }
    }

    #if os(iOS)
    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ตารางเรียน").font(.title2.bold())
                    HStack(spacing: 8) {
                        Button(action: openTerms) {
                            Label(term, systemImage: "chevron.up.chevron.down").lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("My Term: \(term)")
                        Text(periodDetail).lineLimit(1).fixedSize()
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                iconButton("magnifyingglass", label: "ค้นหาวิชา") {
                    searching.toggle()
                    if !searching { search = "" }
                }
                iconButton("gearshape", label: "ตั้งค่า", action: openProfile)
            }
            Picker("มุมมองตาราง", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { item in Text(item.rawValue).tag(item) }
            }
            .pickerStyle(.segmented)
        }
    }
    #endif

    private func header(wide: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ตารางเรียน").font(.system(size: 26, weight: .bold))
                if !term.isEmpty {
                    HStack(spacing: 8) {
                        Text(term).font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                        if showDemo {
                            Text("ตัวอย่าง").font(.caption.weight(.medium))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(.primary.opacity(0.06), in: Capsule())
                        }
                    }
                }
                TimelineView(.everyMinute) { context in
                    Text(todayLabel(context.date))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if wide { modePicker }
            iconButton("magnifyingglass", label: "ค้นหาวิชา") {
                searching.toggle()
                if !searching { search = "" }
            }
            if wide {
                iconButton("bell", label: "งานที่ต้องติดตาม") { showingReminders.toggle() }
                    .overlay(alignment: .topTrailing) {
                        if !openAssignments.isEmpty {
                            Circle().fill(.red).frame(width: 7, height: 7).offset(x: -3, y: 2)
                                .allowsHitTesting(false)
                        }
                    }
                    .popover(isPresented: $showingReminders) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("งานที่ต้องติดตาม").font(.headline)
                            if openAssignments.isEmpty {
                                Text("ไม่มีงานค้าง").foregroundStyle(.secondary)
                            }
                            ForEach(openAssignments.prefix(5)) { task in
                                Button {
                                    showingReminders = false
                                    editor = .task(task)
                                } label: {
                                    HStack {
                                        Text(task.title)
                                        Spacer()
                                        Text(shortDate(task.due)).foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            Button("ดูงานทั้งหมด") { showingReminders = false; openTasks() }
                        }
                        .padding(16)
                        .frame(width: 260)
                    }
                iconButton("person.crop.circle.fill", label: "โปรไฟล์ในเครื่อง", action: openProfile)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !wide { modePicker.padding(.trailing, 48) }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 9)
    }

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(Mode.allCases, id: \.self) { option in
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { mode = option } } label: {
                    Text(option.rawValue).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 15).frame(height: 34)
                        .foregroundStyle(mode == option ? palette.buttonText : .primary)
                        .background(mode == option ? palette.button : .clear, in: Capsule())
                }
                .buttonStyle(PlannerPressStyle())
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
        .padding(2)
        .background(.primary.opacity(0.055), in: Capsule())
    }

    private func controls(railFits: Bool, compact: Bool) -> some View {
        HStack(spacing: 8) {
            iconButton("chevron.left", label: "ช่วงก่อนหน้า") { shift(-1) }
            iconButton("chevron.right", label: "ช่วงถัดไป") { shift(1) }
            Button { choosingDate.toggle() } label: {
                HStack(spacing: 8) {
                    Text(periodTitle).font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 13)
                .frame(height: 36)
                .background(surface, in: Capsule())
                .overlay { Capsule().strokeBorder(gridBorder) }
            }
            .buttonStyle(PlannerPressStyle())
            .fixedSize()
            .popover(isPresented: $choosingDate, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    DatePicker("ไปที่วันที่", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical).labelsHidden().environment(\.locale, thai)
                    HStack {
                        Button("วันนี้") { date = .now; choosingDate = false }
                        Spacer()
                        Button("เสร็จสิ้น") { choosingDate = false }.keyboardShortcut(.defaultAction)
                    }
                }
                .padding(14)
                .frame(width: 290)
            }
            if !compact { Text(periodDetail).font(.system(size: 14, weight: .semibold)).lineLimit(1) }
            Spacer(minLength: 0)
            #if os(macOS) || os(iOS)
            iconButton("square.and.arrow.up", label: "แชร์ตารางหรืองาน", action: openShare)
            #endif
            Button {
                editor = .subject(Subject(name: "", code: "", teacher: "", color: 0))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    if !compact { Text("เพิ่มวิชา") }
                }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, compact ? 10 : 15).frame(height: 36)
                    .foregroundStyle(palette.buttonText).background(palette.button, in: Capsule())
            }
            .buttonStyle(PlannerPressStyle())
            .accessibilityLabel("เพิ่มวิชา")
            Menu {
                Button("เพิ่มคาบเรียน") {
                    guard let subject = store.termDatabase.subjects.first else { return }
                    editor = .slot(ClassSlot(subjectID: subject.id, weekday: weekday(date), start: 540, end: 600, room: ""))
                }
                .disabled(store.termDatabase.subjects.isEmpty)
                Button("เพิ่มงาน") {
                    editor = .task(StudyTask(title: "", assigned: .now, due: .now.addingTimeInterval(86400)))
                }
                if railFits { Toggle("แสดงแผงงาน", isOn: $showRail) }
                Button("ดูงานทั้งหมด", action: openTasks)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(surface, in: Circle())
                    .overlay { Circle().strokeBorder(gridBorder) }
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            #endif
            .fixedSize()
            .accessibilityLabel("ตัวเลือกตารางเรียน")
        }
        .padding(.horizontal, 8)
    }

    private func timeline(days: [Date]) -> some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, labelWidth + CGFloat(lastHour - firstHour) * 54 + 29)
            let unit = (width - labelWidth - 29) / CGFloat(lastHour - firstHour)
            let weekly = days.count > 1
            let fittedHeight = (geometry.size.height - headerHeight) / CGFloat(days.count)
            let rowHeight = weekly ? max(1, fittedHeight) : max(soft ? 82 : 70, fittedHeight)
            let scrollAxes: Axis.Set = weekly ? .horizontal : [.horizontal, .vertical]
            ScrollView(scrollAxes) {
                TimelineView(.everyMinute) { context in
                    VStack(spacing: 0) {
                        hourHeader(unit: unit)
                        ForEach(days, id: \.self) { day in
                            dayRow(day, isToday: calendar.isDate(day, inSameDayAs: context.date), unit: unit, height: rowHeight)
                        }
                    }
                    .frame(width: width)
                    .overlay(alignment: .topLeading) {
                        if let minute = liveMinute(context.date, in: days) {
                            timeMarker(minute, unit: unit)
                        }
                    }
                    .background(surface)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(gridBorder).allowsHitTesting(false) }
                }
            }
        }
    }

    private func hourHeader(unit: CGFloat) -> some View {
        Color.clear.frame(height: headerHeight)
            .overlay(alignment: .topLeading) {
                ForEach(firstHour...lastHour, id: \.self) { hour in
                    Text(clock(hour * 60)).font(.system(size: 12, weight: .medium).monospacedDigit())
                        .frame(width: 56)
                        .offset(x: labelWidth + CGFloat(hour - firstHour) * unit - 28, y: 19)
                }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(gridBorder).frame(height: 1) }
            .accessibilityHidden(true)
    }

    private func dayRow(_ day: Date, isToday: Bool, unit: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(weekdays[weekday(day)]).font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isToday ? palette.accent(scheme) : .primary)
                HStack(spacing: 4) {
                    Text(shortDate(day)).font(.system(size: 12)).foregroundStyle(.secondary)
                    if isToday && height < 58 { todayBadge }
                }
                if isToday && height >= 58 { todayBadge }
            }
            .padding(.leading, 10)
            .frame(width: labelWidth, height: height, alignment: .leading)
            .background(isToday ? palette.accent(scheme).opacity(0.06) : .clear)
            .accessibilityElement(children: .combine)

            let entries = classLanes(on: day)
            let laneCount = (entries.map(\.lane).max() ?? 0) + 1
            Color.clear.frame(maxWidth: .infinity).frame(height: height)
                .overlay(alignment: .topLeading) {
                    ForEach(firstHour...lastHour, id: \.self) { hour in
                        Rectangle().fill(gridBorder).frame(width: 1, height: height)
                            .offset(x: CGFloat(hour - firstHour) * unit)
                    }
                }
                .overlay(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        ForEach(entries, id: \.slot.id) { entry in
                            let slot = entry.slot
                            if let subject = store.termDatabase.subject(slot.subjectID), matches(subject) {
                                let laneHeight = (height - 12) / CGFloat(laneCount)
                                classCard(slot, subject: subject,
                                          width: max(1, CGFloat(slot.end - slot.start) / 60 * unit - 4),
                                          height: min(88, max(1, laneHeight - 4)))
                                .offset(x: CGFloat(slot.start - firstHour * 60) / 60 * unit + 2,
                                        y: 6 + CGFloat(entry.lane) * laneHeight + max(0, (laneHeight - 88) / 2))
                            }
                        }
                    }
                }
                .clipped()
        }
        .overlay(alignment: .bottom) { Rectangle().fill(gridBorder).frame(height: 1) }
    }

    private var todayBadge: some View {
        Text("วันนี้").font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(palette.accent(scheme).opacity(0.14), in: Capsule())
    }

    private func classCard(_ slot: ClassSlot, subject: Subject, width: CGFloat, height: CGFloat) -> some View {
        let color = Color.subject(subject.color)
        let time = "\(clock(slot.start)) – \(clock(slot.end))"
        let detail = [subject.code, subject.name, slot.kind?.rawValue ?? "", time, slot.location]
            .filter { !$0.isEmpty }.joined(separator: ", ")
        return Button { editor = .slot(slot) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    Text(subject.code.isEmpty ? subject.name : subject.code)
                        .font(.system(size: 12, weight: .bold)).lineLimit(1)
                    if let kind = slot.kind, width > 54 {
                        Spacer(minLength: 0)
                        Text(kind.rawValue).font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(color.opacity(0.19), in: Capsule())
                    }
                }
                if height >= 48 {
                    Text(subject.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
                if height >= 29 {
                    if slot.location.isEmpty {
                        Label(time, systemImage: "clock").font(.system(size: 10)).lineLimit(1)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) {
                                Label(time, systemImage: "clock")
                                Label(slot.location, systemImage: "mappin")
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            VStack(alignment: .leading, spacing: 2) {
                                Label(time, systemImage: "clock").lineLimit(1)
                                if height >= 59 {
                                    Label(slot.location, systemImage: "mappin").lineLimit(1)
                                }
                            }
                        }
                        .font(.system(size: 10))
                    }
                }
            }
            .padding(.leading, width > 28 ? 14 : 3)
            .padding(.trailing, 5)
            .frame(width: width, height: height, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(palette.paper(scheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(
                                colors: [color.opacity(scheme == .dark ? 0.22 : 0.14), color.opacity(palette == .retro ? 0.20 : 0.30)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                    }
            }
            .overlay(alignment: .leading) {
                Capsule().fill(color).frame(width: width > 28 ? 5 : 2)
                    .padding(.vertical, min(6, height / 4)).padding(.leading, width > 28 ? 5 : 0)
            }
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shadow(color: color.opacity(scheme == .dark ? 0 : 0.16), radius: 3, x: 0, y: 2)
        .accessibilityLabel(detail)
        .plannerHelp(detail)
    }

    private func classLanes(on day: Date) -> [(slot: ClassSlot, lane: Int)] {
        var ends: [Int] = []
        return store.termDatabase.classes.filter { $0.weekday == weekday(day) && $0.end > $0.start }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
            .map { slot in
                let lane = ends.firstIndex { $0 <= slot.start } ?? ends.count
                if lane == ends.count { ends.append(slot.end) } else { ends[lane] = slot.end }
                return (slot, lane)
            }
    }

    private func liveMinute(_ now: Date, in days: [Date]) -> Int? {
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        guard days.contains(where: { calendar.isDate($0, inSameDayAs: now) }),
              (firstHour * 60...lastHour * 60).contains(minute) else { return nil }
        return minute
    }

    private func timeMarker(_ minute: Int, unit: CGFloat) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Text(clock(minute)).font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .foregroundStyle(.white).background(.red, in: Capsule())
                Rectangle().fill(.red).frame(width: 1.5)
            }
            .frame(width: 55, height: max(0, geometry.size.height - headerHeight + 13))
            .offset(x: labelWidth + CGFloat(minute - firstHour * 60) / 60 * unit - 27.5, y: headerHeight - 13)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var month: some View {
        let start = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let days = calendar.range(of: .day, in: .month, for: date)?.count ?? 0
        return ScrollView {
            VStack(spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(weekdays, id: \.self) { day in
                        Text(day).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                    ForEach(0..<weekday(start), id: \.self) { _ in Color.clear.frame(height: 30) }
                    ForEach(0..<days, id: \.self) { offset in
                        let day = adding(.day, offset, to: start)
                        let count = store.termDatabase.classes.filter { slot in
                            slot.weekday == weekday(day) && store.termDatabase.subject(slot.subjectID).map(matches) == true
                        }.count
                        Button {
                            date = day
                            mode = .day
                        } label: {
                            VStack(spacing: 5) {
                                Text(day.formatted(.dateTime.day().locale(thai))).font(.headline)
                                Text("\(count) คาบ").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(surface, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(shortDate(day)), \(count) คาบ")
                    }
                }
            }
            .padding(14)
        }
        .background(surface, in: RoundedRectangle(cornerRadius: 13))
    }

    private func agenda(days: [Date]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(days, id: \.self) { day in
                    let entries = classLanes(on: day).map(\.slot)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(weekdays[weekday(day)]) \(shortDate(day))").font(.headline)
                        ForEach(entries) { slot in
                            if let subject = store.termDatabase.subject(slot.subjectID), matches(subject) {
                                Button { editor = .slot(slot) } label: {
                                    HStack(spacing: 12) {
                                        Circle().fill(Color.subject(subject.color)).frame(width: 8, height: 8)
                                        Text(subject.code).fontWeight(.semibold)
                                        Text(subject.name)
                                        Spacer()
                                        Text(slot.kind?.rawValue ?? "")
                                        Text("\(clock(slot.start)) – \(clock(slot.end))")
                                        Text(slot.location).foregroundStyle(.secondary)
                                    }
                                    .padding(8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if !entries.contains(where: { store.termDatabase.subject($0.subjectID).map(matches) == true }) {
                            Text("ไม่มีคาบเรียน").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .background(surface, in: RoundedRectangle(cornerRadius: 13))
    }

    private var taskRail: some View {
        let progress = store.termDatabase.weeklyTaskProgress(from: weekStart, to: weekEnd)
        let weekTasks = progress.tasks
        return VStack(spacing: 11) {
            railPanel {
                HStack {
                    Label("งานในสัปดาห์นี้", systemImage: "checkmark.square").font(.system(size: 13, weight: .bold))
                    Spacer(minLength: 3)
                    Button("ดูทั้งหมด →", action: openTasks)
                        .font(.caption).foregroundStyle(.secondary).buttonStyle(.plain)
                }
                if weekTasks.isEmpty {
                    Text("ไม่มีงานครบกำหนดในสัปดาห์นี้")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                }
                ForEach(weekTasks.sorted { ($0.status == .done ? 1 : 0, $0.due) < ($1.status == .done ? 1 : 0, $1.due) }.prefix(3)) { task in
                    taskRow(task)
                }
            }
            railPanel {
                Text("สรุปสัปดาห์").font(.system(size: 15, weight: .bold))
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "calendar").font(.system(size: 19)).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("งานเสร็จ").font(.caption.weight(.semibold))
                        HStack {
                            Text("\(progress.done) / \(progress.total)")
                            Spacer()
                            Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
                        }
                        .font(.system(size: 13))
                        ProgressView(value: progress.fraction).tint(Color(red: 0.19, green: 0.56, blue: 0.43))
                            .accessibilityLabel("งานเสร็จในสัปดาห์")
                    }
                }
                Divider()
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("คาบเรียน").font(.caption.weight(.semibold))
                        Text("\(store.termDatabase.classes.count) คาบ").font(.system(size: 13))
                    }
                } icon: { Image(systemName: "calendar").font(.system(size: 19)) }
            }
            TimelineView(.everyMinute) { context in
                railPanel {
                    let next = nextEvent(after: context.date)
                    Text("ช่วงเวลาถัดไป").font(.system(size: 14, weight: .bold))
                    if let next {
                        Button { open(next) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "calendar.badge.clock").font(.system(size: 18))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(next.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                                    Text(nextTime(next))
                                        .font(.caption).foregroundStyle(.secondary)
                                    if !next.detail.isEmpty {
                                        Text(next.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("ไม่มีคาบหรือกิจกรรมที่กำลังจะมาถึง").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(1)
    }

    private func taskRow(_ task: StudyTask) -> some View {
        let done = task.status == .done
        let priority = task.priority == .high ? "สูง" : task.priority == .medium ? "กลาง" : "ต่ำ"
        return HStack(alignment: .top, spacing: 9) {
            Button { store.toggle(task) } label: {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 19)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "เปิดงาน \(task.title) อีกครั้ง" : "ทำงาน \(task.title) เสร็จแล้ว")
            Button { editor = .task(task) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(.system(size: 12, weight: .medium)).lineLimit(2).strikethrough(done)
                    Text("ส่ง \(task.due.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(thai)))")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(priority).font(.system(size: 10, weight: .semibold))
                .padding(.vertical, 3).padding(.horizontal, 6)
                .background(task.displayColor.opacity(0.22), in: Capsule())
                .accessibilityLabel("ความสำคัญ \(priority)")
        }
        .padding(.vertical, 2)
    }

    private func railPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(gridBorder).allowsHitTesting(false) }
    }

    private func nextEvent(after now: Date) -> AgendaItem? {
        let today = calendar.startOfDay(for: now)
        guard today < weekEnd else { return nil }
        let first = max(today, weekStart)
        let last = today >= weekStart ? adding(.day, 8, to: today) : weekEnd
        let days = calendar.dateComponents([.day], from: first, to: last).day ?? 0
        for offset in 0..<days {
            if let next = store.termDatabase.agenda(on: adding(.day, offset, to: first))
                .first(where: { ($0.eventID != nil || $0.taskID == nil) && $0.start >= now && $0.start < last }) {
                return next
            }
        }
        return nil
    }

    private func nextTime(_ item: AgendaItem) -> String {
        let time = Date.FormatStyle.dateTime.hour().minute().locale(thai)
        return "\(shortDate(item.start)) · \(item.start.formatted(time)) – \(item.end.formatted(time))"
    }

    private func open(_ item: AgendaItem) {
        if let event = store.termDatabase.events.first(where: { $0.id == item.eventID }) { editor = .event(event) }
        else if let slot = store.termDatabase.classes.first(where: { $0.id.uuidString == item.id }) { editor = .slot(slot) }
    }

    private func iconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(surface, in: Circle())
                .overlay { Circle().strokeBorder(gridBorder) }
                .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.08), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .plannerHelp(label)
    }

    private var periodTitle: String {
        switch mode {
        case .week, .list:
            var mondayCalendar = calendar
            mondayCalendar.firstWeekday = 2
            return "สัปดาห์ที่ \(mondayCalendar.component(.weekOfYear, from: date))"
        case .day: return "เลือกวัน"
        case .month: return "เลือกเดือน"
        }
    }

    private var periodDetail: String {
        switch mode {
        case .week, .list:
            let last = adding(.day, -1, to: weekEnd)
            let first = calendar.isDate(weekStart, equalTo: last, toGranularity: .month)
                ? weekStart.formatted(.dateTime.day().locale(thai)) : shortDate(weekStart)
            return "\(first) – \(last.formatted(.dateTime.day().month(.abbreviated).year().locale(thai)))"
        case .day: return date.formatted(.dateTime.day().month(.abbreviated).year().locale(thai))
        case .month: return date.formatted(.dateTime.month(.wide).year().locale(thai))
        }
    }

    private func shift(_ direction: Int) {
        switch mode {
        case .week, .list: date = adding(.day, direction * 7, to: date)
        case .day: date = adding(.day, direction, to: date)
        case .month: date = adding(.month, direction, to: date)
        }
    }

    private func adding(_ component: Calendar.Component, _ value: Int, to date: Date) -> Date {
        calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    private func weekday(_ day: Date) -> Int { (calendar.component(.weekday, from: day) + 5) % 7 }
    private func todayLabel(_ day: Date) -> String {
        let date = day.formatted(.dateTime.day().month(.wide).year().locale(thai))
        return "วันนี้ วัน\(weekdays[weekday(day)])ที่ \(date)"
    }

    private func shortDate(_ day: Date) -> String { day.formatted(.dateTime.day().month(.abbreviated).locale(thai)) }
    private func matches(_ subject: Subject) -> Bool {
        search.isEmpty || subject.name.localizedCaseInsensitiveContains(search) || subject.code.localizedCaseInsensitiveContains(search)
    }
}

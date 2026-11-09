import SwiftUI
#if os(macOS)
import AppKit
#endif

enum Section: String, CaseIterable, Identifiable {
    case today = "Overview", timetable = "Timetable", calendar = "Calendar", tasks = "Tasks", subjects = "Subjects", notes = "Notes", analytics = "Analytics"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .today: return "house"
        case .timetable: return "calendar"
        case .calendar: return "calendar.badge.clock"
        case .tasks: return "checkmark.square"
        case .subjects: return "square.3.layers.3d"
        case .notes: return "note.text"
        case .analytics: return "chart.bar"
        }
    }
}

struct MainView: View {
    @EnvironmentObject var store: PlannerStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("planner.palette") private var palette = PlannerPalette.classic
    @AppStorage("planner.appearance") private var appearance = "Follow System"
    @AppStorage("planner.layout") private var layout = "Soft Minimal"
    @Binding var showDemo: Bool
    @State private var confirmClearDemo = false
    @State private var section: Section = .timetable
    @State private var search = ""
    @State private var editor: EditorTarget?
    @State private var settings = false
    @State private var shareSheet = false

    private var soft: Bool { layout == "Soft Minimal" }
    private var pending: Int { store.termDatabase.tasks.filter { $0.status != .done }.count }

    @State private var terms = false

    private var term: String {
        store.termOptions.first { $0.id == store.activeTermID }?.name ?? ""
    }

    var body: some View {
        GeometryReader { geometry in
            #if os(iOS)
            if sizeClass == .compact {
                page
                    .safeAreaInset(edge: .bottom, spacing: 0) { mobileNavigation }
            } else {
                desktopLayout(width: geometry.size.width)
            }
            #else
            desktopLayout(width: geometry.size.width)
            #endif
        }
        .environment(\.plannerPalette, palette)
        .tint(palette.accent(scheme))
        .preferredColorScheme(appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil)
        .sheet(item: $editor) { target in
            EditorSheet(target: target).environmentObject(store)
                .presentationBackground(palette.paper(scheme))
                #if os(iOS)
                .presentationDetents(target.needsFullHeight ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
        }
        #if os(macOS) || os(iOS)
        .sheet(isPresented: $shareSheet) {
            ShareSheet(showDemo: showDemo).environmentObject(store)
                .presentationBackground(palette.paper(scheme))
        }
        #endif
        .sheet(isPresented: $terms) {
            TermSheet(showDemo: showDemo)
                .environmentObject(store)
                .presentationBackground(palette.paper(scheme))
        }
        .sheet(isPresented: $settings) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("StudyFlow Planner").font(.title2.bold())
                    Label("โปรไฟล์ในเครื่อง", systemImage: "person.crop.circle")
                        .foregroundStyle(.secondary)
                    Toggle("ใช้ข้อมูลตัวอย่าง", isOn: $showDemo)
                    if showDemo {
                        Text("รายการที่เพิ่มหรือแก้ตรงนี้จะบันทึกแยกจากข้อมูลจริง")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("ล้างข้อมูลตัวอย่าง…", role: .destructive) { confirmClearDemo = true }
                            .disabled(store.db == Database())
                    }
                    Picker("Layout", selection: $layout) {
                        Text("B · Soft Minimal").tag("Soft Minimal")
                        Text("A · Modern Clean").tag("Modern Clean")
                    }
                    Picker("Theme", selection: $palette) {
                        Text("Classic · ขาวดำ").tag(PlannerPalette.classic)
                        Text("Retro · ครีมอุ่น").tag(PlannerPalette.retro)
                        Text("Soft Honey · เหลืองนุ่ม").tag(PlannerPalette.honey)
                        Text("White / Lilac · ขาวม่วง").tag(PlannerPalette.lilac)
                    }
                    Picker("Appearance", selection: $appearance) {
                        ForEach(["Light", "Dark", "Follow System"], id: \.self) { Text($0) }
                    }
                    #if os(macOS) || os(iOS)
                    Divider()
                    CloudSettings(showDemo: showDemo)
                    #endif
                    Button("เสร็จสิ้น") { settings = false }
                        .keyboardShortcut(.defaultAction)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(24)
            }
            #if os(macOS)
            .frame(width: 410, height: 620)
            #endif
            .presentationBackground(palette.paper(scheme))
            .confirmationDialog("ล้างข้อมูลตัวอย่างทั้งหมด?", isPresented: $confirmClearDemo, titleVisibility: .visible) {
                Button("ล้างข้อมูลตัวอย่าง", role: .destructive) {
                    if store.update({ $0 = Database() }) {
                        settings = false
                        showDemo = false
                    }
                }
            } message: {
                Text("ลบรายการในพื้นที่ตัวอย่างเท่านั้น")
            }
        }
        .alert("Storage needs attention", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .alert("Reminder", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("OK") { store.notice = nil }
        } message: { Text(store.notice ?? "") }
    }

    private func desktopLayout(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            sidebar(compact: width < 780)
            Rectangle().fill(.primary.opacity(0.09)).frame(width: 1)
            page
        }
    }

    private var page: some View {
        VStack(spacing: 0) {
            if section != .timetable && section != .today { pageHeader }
            Group {
                switch section {
                case .timetable:
                    TimetableView(editor: $editor, soft: soft, term: term, showDemo: showDemo,
                                  openTasks: { select(.tasks) }, openProfile: { settings = true },
                                  openShare: { shareSheet = true }, openTerms: { terms = true })
                case .calendar: CalendarPage(editor: $editor)
                case .tasks: TasksPage(search: search, editor: $editor)
                case .subjects: SubjectsPage(search: search, editor: $editor)
                case .today:
                    OverviewPage(editor: $editor, openTimetable: { select(.timetable) },
                                 openTasks: { select(.tasks) })
                case .notes: notesPage
                case .analytics: analyticsPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(palette.canvas(scheme))
    }

    #if os(iOS)
    private var mobileNavigation: some View {
        HStack(spacing: 0) {
            mobileTab(.timetable, label: "ตาราง")
            mobileTab(.today, label: "ภาพรวม")
            mobileTab(.tasks, label: "งาน")
            Menu {
                Button("My Term", systemImage: "graduationcap") { terms = true }
                Button("ปฏิทิน", systemImage: Section.calendar.icon) { select(.calendar) }
                Button("วิชา", systemImage: Section.subjects.icon) { select(.subjects) }
                Button("โน้ต", systemImage: Section.notes.icon) { select(.notes) }
                Button("สถิติ", systemImage: Section.analytics.icon) { select(.analytics) }
                Button("ตั้งค่า", systemImage: "gearshape") { settings = true }
            } label: {
                mobileTabLabel("เพิ่มเติม", icon: "ellipsis")
            }
        }
        .padding(.vertical, 6)
        .background(palette.sidebar(scheme))
    }

    private func mobileTab(_ item: Section, label: String) -> some View {
        Button { select(item) } label: { mobileTabLabel(label, icon: item.icon) }
            .buttonStyle(.plain)
            .foregroundStyle(section == item ? palette.accent(scheme) : Color.secondary)
            .accessibilityAddTraits(section == item ? .isSelected : [])
    }

    private func mobileTabLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 17))
            Text(title).font(.caption2)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }
    #endif

    @ViewBuilder private var brandIcon: some View {
        #if os(macOS)
        if let url = Bundle.main.url(forResource: "StudyFlowIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            Image(nsImage: icon).resizable().scaledToFit()
        } else {
            fallbackBrandIcon
        }
        #else
        fallbackBrandIcon
        #endif
    }

    private var fallbackBrandIcon: some View {
        Image(systemName: "calendar.badge.checkmark")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(palette.buttonText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.button, in: RoundedRectangle(cornerRadius: 9))
    }

    private func sidebar(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: soft ? 4 : 2) {
            HStack(spacing: 12) {
                brandIcon
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                if !compact { Text("StudyFlow").font(.system(size: 18, weight: .bold)).fixedSize() }
            }
            .padding(.horizontal, compact ? 0 : 10)
            .padding(.bottom, 22)

            ForEach(Section.allCases) { item in
                let selected = item == section
                Button { select(item) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: item.icon).font(.system(size: 20, weight: .medium)).frame(width: 24)
                        if !compact {
                            Text(item.rawValue).fontWeight(selected ? .semibold : .regular).lineLimit(1).fixedSize()
                            Spacer(minLength: 0)
                            if item == .tasks, pending > 0 {
                                Text("\(pending)").font(.caption2.bold()).padding(5)
                                    .foregroundStyle(.white).background(.gray, in: Circle())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: soft ? 40 : 34, alignment: compact ? .center : .leading)
                    .padding(.horizontal, compact ? 0 : 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? palette.accent(scheme) : Color.primary)
                .background(selected ? palette.selection(scheme) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .plannerHelp(item.rawValue)
            }

            Divider().padding(.vertical, compact ? 8 : 16)
            if !compact {
                Text("My Term").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
            }
            Button { terms = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "graduationcap")
                    if !compact {
                        Text(term).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                }
                .font(.system(size: compact ? 17 : 12, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 36, alignment: compact ? .center : .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, compact ? 0 : 12)
            .accessibilityLabel("My Term")
            .accessibilityValue(term)

            Spacer()
            Button { settings = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "gearshape").font(.system(size: 21)).frame(width: 24)
                    if !compact { Text("Settings") }
                }
                .frame(maxWidth: .infinity, minHeight: 42, alignment: compact ? .center : .leading)
                .padding(.horizontal, compact ? 0 : 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.top, 54)
        .padding(.bottom, 22)
        .frame(width: compact ? 58 : soft ? 197 : 179)
        .frame(maxHeight: .infinity)
        .background(palette.sidebar(scheme))
    }

    private var pageHeader: some View {
        HStack {
            Text(section.rawValue).font(.largeTitle.bold())
            Spacer()
            if section == .tasks || section == .subjects {
                TextField("Search \(section.rawValue.lowercased())", text: $search).frame(width: 180)
            }
            Menu("Create", systemImage: "plus") {
                Button("Class") {
                    if let subject = store.termDatabase.subjects.first {
                        editor = .slot(ClassSlot(subjectID: subject.id, weekday: 0, start: 540, end: 600, room: ""))
                    } else { newSubject() }
                }
                Button("Subject", action: newSubject)
                Button("Task") { editor = .task(StudyTask(title: "", assigned: .now, due: .now.addingTimeInterval(86400))) }
                Button("Event / work session") {
                    editor = .event(PlannerEvent(title: "", start: .now, end: .now.addingTimeInterval(3600)))
                }
            }
            .fixedSize()
        }
        .padding(24)
    }

    private var notesPage: some View {
        let notes = store.termDatabase.tasks.filter { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if notes.isEmpty {
                    EmptyState(title: "ยังไม่มีโน้ต", detail: "เพิ่มโน้ตได้ในหน้ารายละเอียดงาน")
                }
                ForEach(notes) { task in
                    Button { editor = .task(task) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(task.title).font(.headline)
                            Text(task.notes).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
    }

    private var analyticsPage: some View {
        let total = store.termDatabase.tasks.count
        let done = total - pending
        let hours = Double(store.termDatabase.classes.reduce(0) { $0 + max(0, $1.end - $1.start) }) / 60
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("สรุปการเรียนและงาน").font(.title2.bold())
                VStack(alignment: .leading, spacing: 12) {
                    Label("งานเสร็จ \(done) / \(total)", systemImage: "checkmark.square")
                    ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                    Label("\(store.termDatabase.classes.count) คาบเรียนต่อสัปดาห์", systemImage: "calendar")
                    Label("\(hours.formatted(.number.precision(.fractionLength(0...1)))) ชั่วโมงเรียนต่อสัปดาห์",
                          systemImage: "clock")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            .padding(24)
        }
    }

    private func select(_ item: Section) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { section = item }
        search = ""
    }

    private func newSubject() {
        editor = .subject(Subject(name: "", code: "", teacher: "", color: 0))
    }
}


private struct TermSheet: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    let showDemo: Bool
    @State private var name = ""
    @State private var editing: UUID?
    @State private var duplicate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("My Term").font(.title2.bold())
                Text(showDemo ? "กำลังจัดการเทอมในข้อมูลตัวอย่าง" : "เลือกเทอมเพื่อดูตารางเรียน วิชา และงานของเทอมนั้น")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(store.termOptions) { term in
                    HStack {
                        Button {
                            store.selectTerm(term.id)
                            dismiss()
                        } label: {
                            Label(term.name, systemImage: term.id == store.activeTermID ? "checkmark.circle.fill" : "graduationcap")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            editing = term.id
                            name = term.name
                            duplicate = false
                        } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("เปลี่ยนชื่อ \(term.name)")
                    }
                    .padding(.vertical, 5)
                }
                Divider()
                Text(editing == nil ? "เพิ่มเทอมใหม่" : "เปลี่ยนชื่อเทอม").font(.headline)
                TextField("เช่น เทอม 2 / 2569", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _, _ in duplicate = false }
                    .onSubmit(save)
                if duplicate {
                    Text("มีเทอมชื่อนี้แล้ว หรือบันทึกไม่ได้").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    if editing != nil {
                        Button("ยกเลิกการเปลี่ยนชื่อ") {
                            editing = nil
                            name = ""
                            duplicate = false
                        }
                    }
                    Spacer()
                    Button("ปิด") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(editing == nil ? "เพิ่มเทอม" : "บันทึกชื่อ", action: save)
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
        }
        #if os(macOS)
        .frame(width: 420, height: 410)
        #endif
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if store.saveTerm(name, editing: editing) { dismiss() }
        else { duplicate = true }
    }
}

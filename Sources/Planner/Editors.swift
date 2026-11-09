import SwiftUI

enum EditorTarget:Identifiable {
    case subject(Subject), slot(ClassSlot), task(StudyTask), event(PlannerEvent)
    var needsFullHeight: Bool { if case .task = self { return true }; return false }
    var id:String { switch self {case .subject(let s):return "s\(s.id)";case .slot(let s):return "c\(s.id)";case .task(let t):return "t\(t.id)";case .event(let e):return "e\(e.id)"} }
}
struct EditorSheet:View {
    var target:EditorTarget
    var body:some View { Group { switch target { case .subject(let s):SubjectEditor(value:s);case .slot(let s):ClassEditor(value:s);case .task(let t):TaskEditor(value:t);case .event(let e):EventEditor(value:e) } }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 530, minHeight: 470).padding(24)
        #else
        .padding(16)
        #endif
    }
}
struct EditorHeader: View {
    @Environment(\.plannerPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    var title: String
    var subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(PlannerPressStyle())
            .accessibilityLabel("ปิด")
        }
        .padding(14)
        .background(palette.popupTint(scheme), in: RoundedRectangle(cornerRadius: 13))
    }
}
struct EditorActions: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.plannerPalette) private var palette
    var valid: Bool
    var save: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button("ยกเลิก") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
            Button { save(); dismiss() } label: {
                Text("บันทึก").fontWeight(.semibold)
                    .padding(.horizontal, 19).padding(.vertical, 8)
                    .foregroundStyle(palette.buttonText)
                    .background(palette.button, in: RoundedRectangle(cornerRadius: 8))
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(PlannerPressStyle())
            .disabled(!valid)
            .opacity(valid ? 1 : 0.45)
        }
        .padding(.top, 10)
    }
}
struct SubjectPicker:View {
    @EnvironmentObject var store:PlannerStore
    @Binding var selection:UUID?
    var body:some View { Picker("วิชา",selection:$selection) { Text("None").tag(nil as UUID?); ForEach(store.termDatabase.subjects){Text($0.name).tag(Optional($0.id))} } }
}
struct SubjectEditor:View {
    @EnvironmentObject var store:PlannerStore
    @State var value:Subject
    var body:some View { VStack { EditorHeader(title:store.termDatabase.subjects.contains { $0.id == value.id } ? "แก้ไขวิชา" : "เพิ่มวิชา",subtitle:"จัดการชื่อ รหัสวิชา และสีบนตาราง"); Form { TextField("ชื่อวิชา",text:$value.name);TextField("รหัสวิชา",text:$value.code);TextField("ผู้สอน",text:$value.teacher);Picker("Color",selection:$value.color){ForEach(0..<Color.palette.count,id:\.self){i in Text(Color.paletteNames[i]).tag(i)}} }.formStyle(.grouped);EditorActions(valid:!value.name.trimmingCharacters(in:.whitespaces).isEmpty){store.save(value)} } }
}
struct ClassEditor:View {
    @EnvironmentObject var store:PlannerStore
    @Environment(\.dismiss) var dismiss
    @State var value:ClassSlot
    var start:Binding<Date>{Binding(get:{Calendar.current.startOfDay(for:Date()).addingTimeInterval(Double(value.start*60))},set:{value.start=Calendar.current.component(.hour,from:$0)*60+Calendar.current.component(.minute,from:$0)})}
    var end:Binding<Date>{Binding(get:{Calendar.current.startOfDay(for:Date()).addingTimeInterval(Double(value.end*60))},set:{value.end=Calendar.current.component(.hour,from:$0)*60+Calendar.current.component(.minute,from:$0)})}
    var overlaps:Bool { store.termDatabase.classes.contains { $0.id != value.id && $0.weekday == value.weekday && $0.start < value.end && $0.end > value.start } }
    var body:some View { VStack { EditorHeader(title:store.termDatabase.classes.contains { $0.id == value.id } ? "แก้ไขคาบเรียน" : "เพิ่มคาบเรียน",subtitle:"แสดงในตารางทุกสัปดาห์"); Form { Picker("วิชา",selection:$value.subjectID){ForEach(store.termDatabase.subjects){Text($0.name).tag($0.id)}};Picker("วัน",selection:$value.weekday){ForEach(0..<7,id:\.self){Text(dayNames[$0]).tag($0)}};DatePicker("เริ่ม",selection:start,displayedComponents:.hourAndMinute);DatePicker("จบ",selection:end,displayedComponents:.hourAndMinute);Picker("ประเภท", selection: $value.kind) {
        Text("Unspecified").tag(nil as ClassKind?)
        ForEach(ClassKind.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
    };TextField("อาคาร", text: Binding(get: { value.building ?? "" }, set: { value.building = $0.isEmpty ? nil : $0 }));TextField("ห้อง",text:$value.room);if let s=store.termDatabase.subject(value.subjectID){LabeledContent("Teacher",value:s.teacher)};if value.end <= value.start { Text("End time must be later than start time.").foregroundStyle(.red) };if overlaps { Label("This overlaps another class.",systemImage:"exclamationmark.triangle").foregroundStyle(.orange) } }.formStyle(.grouped); HStack { if store.termDatabase.classes.contains(where:{$0.id == value.id}) { Button("Delete class",role:.destructive){store.deleteClass(value.id);dismiss()} }; Spacer() };EditorActions(valid:value.end > value.start){store.save(value)} } }
}
struct TaskEditor:View {
    @EnvironmentObject var store:PlannerStore
    @Environment(\.dismiss) var dismiss
    @State var value:StudyTask
    @State var subtask=""
    @State var session:EditorTarget?
    var body:some View {
        VStack { EditorHeader(title:store.termDatabase.tasks.contains { $0.id == value.id } ? "แก้ไขงาน" : "เพิ่มงาน",subtitle:"รายละเอียดงานและกำหนดส่ง")
            Form {
                SwiftUI.Section { TextField("Title",text:$value.title);SubjectPicker(selection:$value.subjectID);DatePicker("Assigned",selection:$value.assigned,displayedComponents:.date);DatePicker("Due",selection:$value.due);Picker("Priority",selection:$value.priority){ForEach(Priority.allCases,id:\.self){Text($0.rawValue)}};Picker("Task color", selection: $value.color) {
                    Text("By priority").tag(nil as Int?)
                    ForEach(Color.paletteNames.indices, id: \.self) { Text(Color.paletteNames[$0]).tag(Optional($0)) }
                };Picker("Status",selection:$value.status){ForEach(WorkStatus.allCases,id:\.self){Text($0.rawValue)}};if value.assigned > value.due { Text("Due date must follow the assignment date.").foregroundStyle(.red) } }
                SwiftUI.Section("Subtasks · \(Int(value.progress*100))% complete") {
                    ForEach($value.subtasks) { $step in HStack { Toggle("Complete",isOn:$step.done).labelsHidden();TextField("Step",text:$step.title);Button { value.subtasks.removeAll{$0.id == step.id} } label:{Image(systemName:"minus.circle")}.buttonStyle(.plain).accessibilityLabel("Remove subtask") } }
                    HStack { TextField("Add a small step",text:$subtask).onSubmit{addStep()};Button("Add"){addStep()}.disabled(subtask.trimmingCharacters(in:.whitespaces).isEmpty) }
                }
                SwiftUI.Section("Reminder") {
                    Toggle("Remind me",isOn:Binding(get:{value.reminder != nil},set:{value.reminder = $0 ? value.due.addingTimeInterval(-3600) : nil}))
                    if value.reminder != nil { DatePicker("Remind at",selection:Binding(get:{value.reminder ?? Date()},set:{value.reminder=$0}));Text("Notifications require permission on this device. Reminder dates are always saved.").font(.caption).foregroundStyle(.secondary) }
                }
                SwiftUI.Section("Work sessions") {
                    ForEach(store.termDatabase.events.filter{$0.taskID == value.id}) { e in Button { session = .event(e) } label:{HStack{Text(e.title);Spacer();Text(e.start,format:.dateTime.month(.abbreviated).day().hour().minute()).font(.caption)}}.buttonStyle(.plain) }
                    Button("Schedule time for this task",systemImage:"calendar.badge.plus") { store.save(value); session = .event(PlannerEvent(title:value.title,subjectID:nil,taskID:value.id,start:Date().addingTimeInterval(3600),end:Date().addingTimeInterval(7200))) }.disabled(!valid)
                }
                SwiftUI.Section("Notes") { TextEditor(text:$value.notes).frame(minHeight:60) }
            }.formStyle(.grouped).frame(minHeight:400,maxHeight:580)
            HStack { if store.termDatabase.tasks.contains(where:{$0.id == value.id}) { Button("Delete assignment",role:.destructive){store.deleteTask(value.id);dismiss()} };Spacer() }
            EditorActions(valid:valid){store.save(value)}
        }.sheet(item:$session){EditorSheet(target:$0).environmentObject(store)}
    }
    var valid:Bool{!value.title.trimmingCharacters(in:.whitespaces).isEmpty && value.due >= value.assigned}
    func addStep(){let text=subtask.trimmingCharacters(in:.whitespaces);guard !text.isEmpty else{return};value.subtasks.append(Subtask(title:text));subtask=""}
}
struct EventEditor:View {
    @EnvironmentObject var store:PlannerStore
    @Environment(\.dismiss) var dismiss
    @State var value:PlannerEvent
    var body:some View { VStack { EditorHeader(title:value.taskID == nil ? "กิจกรรม" : "ช่วงทำงาน",subtitle:"กำหนดเวลาและสถานที่ในปฏิทิน");Form { TextField("Title",text:$value.title);Picker("Linked task",selection:$value.taskID){Text("None").tag(nil as UUID?);ForEach(store.termDatabase.tasks){Text($0.title).tag(Optional($0.id))}}.onChange(of:value.taskID){_,id in if id != nil {value.subjectID=nil} };if let task=store.termDatabase.tasks.first(where:{$0.id == value.taskID}) { LabeledContent("Subject",value:store.termDatabase.subject(task.subjectID)?.name ?? "None (from task)") } else { SubjectPicker(selection:$value.subjectID) };DatePicker("เริ่ม",selection:$value.start);DatePicker("จบ",selection:$value.end);TextField("Location",text:$value.location);if value.end <= value.start{Text("End must follow start.").foregroundStyle(.red)} }.formStyle(.grouped);HStack{if store.termDatabase.events.contains(where:{$0.id == value.id}){Button("Delete event",role:.destructive){store.deleteEvent(value.id);dismiss()}};Spacer()};EditorActions(valid:!value.title.trimmingCharacters(in:.whitespaces).isEmpty && value.end > value.start){store.save(value)} } }
}

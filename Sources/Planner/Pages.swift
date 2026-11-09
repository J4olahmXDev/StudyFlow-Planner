import SwiftUI
struct TasksPage:View {
    @EnvironmentObject var store:PlannerStore
    var search:String
    @Binding var editor:EditorTarget?
    @State var filter="All"
    var tasks:[StudyTask] { store.termDatabase.tasks.filter { (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) && (filter == "All" || (filter == "Completed" ? $0.status == .done : $0.status != .done)) }.sorted { $0.due < $1.due } }
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:20) {
            HStack { Text("Small steps. Real progress.").font(.title3.weight(.medium)); Spacer(); Picker("Show",selection:$filter) { ForEach(["All","Open","Completed"],id:\.self) { Text($0) } }.pickerStyle(.segmented).frame(width:240) }
            if tasks.isEmpty { EmptyState(title:"A clear list",detail:"Create a task or change your search.") }
            ForEach(tasks) { task in
                HStack(alignment:.top,spacing:14) {
                    Button { store.toggle(task) } label: { Image(systemName:task.status == .done ? "checkmark.circle.fill" : "circle").font(.system(size:22)).foregroundStyle(task.status == .done ? Color.daylight : .secondary) }.buttonStyle(.plain).accessibilityLabel(task.status == .done ? "Reopen \(task.title)" : "Complete \(task.title)")
                    Button { editor = .task(task) } label: {
                        VStack(alignment:.leading,spacing:10) { HStack { Text(task.title).font(.system(size:15,weight:.semibold)).strikethrough(task.status == .done); Spacer(); Text(task.priority.rawValue).font(.caption.weight(.medium)).padding(.horizontal,6).padding(.vertical,3).background(task.displayColor.opacity(0.22),in:Capsule()) }; HStack(spacing:12) { if let s=store.termDatabase.subject(task.subjectID) { Label(s.name,systemImage:"circle.fill").foregroundStyle(Color.subject(s.color)) }; Text(task.status.rawValue); Text("Assigned \(task.assigned.formatted(date:.abbreviated,time:.omitted))"); Spacer(); Text(task.due,format:.dateTime.month(.abbreviated).day().hour().minute()).foregroundStyle(task.due < Date() && task.status != .done ? .red : .secondary) }.font(.system(size:11)); if !task.subtasks.isEmpty { HStack { ProgressView(value:task.progress).tint(.daylight); Text("\(task.subtasks.filter(\.done).count)/\(task.subtasks.count)").font(.caption).foregroundStyle(.secondary) } }; if let reminder=task.reminder { Label(reminder.formatted(date:.abbreviated,time:.shortened),systemImage:"bell").font(.caption).foregroundStyle(.secondary) } }
                    }.buttonStyle(.plain)
                }.card()
            }
        }.padding(30) }
    }
}
struct SubjectsPage:View {
    @EnvironmentObject var store:PlannerStore
    var search:String
    @Binding var editor:EditorTarget?
    var body:some View { ScrollView { LazyVGrid(columns:[GridItem(.adaptive(minimum:230),spacing:18)],spacing:18) { ForEach(store.termDatabase.subjects.filter{search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)}) { s in Button { editor = .subject(s) } label: { VStack(alignment:.leading,spacing:16) { HStack { Image(systemName:"book.closed").font(.title2).foregroundStyle(Color.subject(s.color)); Spacer(); Text(s.code).font(.caption).foregroundStyle(.secondary) }; Text(s.name).font(.title3.weight(.semibold)); Label(s.teacher.isEmpty ? "No teacher added" : s.teacher,systemImage:"person").font(.caption).foregroundStyle(.secondary); Divider(); HStack { Text("\(store.termDatabase.classes.filter{$0.subjectID == s.id}.count) classes / week"); Spacer(); Text("\(store.termDatabase.tasks.filter{$0.subjectID == s.id && $0.status != .done}.count) open tasks") }.font(.system(size:10)).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading).card() }.buttonStyle(.plain) } }.padding(30) } }
}
struct AgendaRow:View {
    @EnvironmentObject var store:PlannerStore
    var item:AgendaItem
    @Binding var editor:EditorTarget?
    var body:some View { Button {
        if let id=item.eventID,let e=store.termDatabase.events.first(where:{$0.id == id}) { editor = .event(e) }
        else if let id=item.taskID,let t=store.termDatabase.tasks.first(where:{$0.id == id}) { editor = .task(t) }
        else if let s=store.termDatabase.classes.first(where:{$0.id.uuidString == item.id}) { editor = .slot(s) }
    } label: { HStack(spacing:16) { Text(item.start,format:.dateTime.hour().minute()).font(.system(size:13,weight:.medium,design:.monospaced)).frame(width:80,alignment:.leading); RoundedRectangle(cornerRadius:2).fill(Color.subject(store.termDatabase.subject(item.subjectID)?.color ?? 0)).frame(width:3,height:35); VStack(alignment:.leading,spacing:5) { Text(item.title).fontWeight(.medium); Text(item.detail).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName:"chevron.right").font(.caption).foregroundStyle(.tertiary) }.frame(maxWidth:.infinity).card() }.buttonStyle(.plain) }
}

enum CalendarMode:String, CaseIterable { case vertical="Week ↓", horizontal="Week →", day="Day", month="Month" }
struct CalendarPage:View {
    @Environment(\.plannerPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject var store:PlannerStore
    @Binding var editor:EditorTarget?
    @State var selected=Date()
    @State var mode:CalendarMode = .vertical
    var cal:Calendar { var c=Calendar.current;c.firstWeekday=2;return c }
    var week:[Date] { let start=cal.dateInterval(of:.weekOfYear,for:selected)!.start; return (0..<7).map{cal.date(byAdding:.day,value:$0,to:start)!} }
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack { Button { move(-1) } label:{Image(systemName:"chevron.left")}; Button("Today") { selected=Date() }; Button { move(1) } label:{Image(systemName:"chevron.right")}; Text(selected,format:.dateTime.month(.wide).year()).font(.title3.weight(.medium)); Spacer(); Picker("Calendar view",selection:$mode) { ForEach(CalendarMode.allCases,id:\.self){Text($0.rawValue)} }.pickerStyle(.segmented).frame(width:340) }
            switch mode {
            case .day: ScrollView { VStack(alignment:.leading,spacing:12) { DatePicker("Day",selection:$selected,displayedComponents:.date); if store.termDatabase.agenda(on:selected).isEmpty { EmptyState(title:"Nothing planned",detail:"Add an event using Create.") }; ForEach(store.termDatabase.agenda(on:selected)){AgendaRow(item:$0,editor:$editor)} } }
            case .month: monthGrid
            case .horizontal: horizontalWeek
            case .vertical: verticalWeek
            }
        }.padding(30)
    }
    func move(_ by:Int) { selected=cal.date(byAdding: mode == .month ? .month : mode == .day ? .day : .weekOfYear,value:by,to:selected)! }
    func dayHeader(_ d:Date) -> some View { VStack(spacing:6) { Text(d,format:.dateTime.weekday(.abbreviated)).font(.system(size:10,weight:.medium)).textCase(.uppercase).foregroundStyle(.secondary); Text(d,format:.dateTime.day()).font(.system(size:20,weight:.medium,design:.rounded)).foregroundStyle(cal.isDateInToday(d) ? Color.daylight : .primary) }.frame(maxWidth:.infinity).padding(.vertical,12) }
    var verticalWeek:some View {
        ScrollView([.horizontal,.vertical]) {
            HStack(alignment:.top,spacing:0) {
                VStack(spacing:0) { Color.clear.frame(height:66); ForEach(0..<24) { hour in Text(clock(hour*60)).font(.system(size:9,design:.monospaced)).foregroundStyle(.secondary).frame(width:45,height:56,alignment:.topLeading) } }
                ForEach(week,id:\.self) { day in
                    VStack(spacing:0) { dayHeader(day).frame(height:66); ZStack(alignment:.topLeading) {
                        VStack(spacing:0) { ForEach(0..<24) { _ in Rectangle().fill(.primary.opacity(0.06)).frame(height:1); Color.clear.frame(height:55) } }
                        ForEach(store.termDatabase.agenda(on:day)) { item in
                            let range = item.minuteRange(on:day,calendar:cal)
                            eventChip(item).frame(width:117,height:max(22,(range.upperBound-range.lowerBound)/60*56-3),alignment:.topLeading).offset(x:3,y:min(range.lowerBound/60*56,1322))
                        }
                    }.frame(width:123,height:1344).overlay(alignment:.leading){Rectangle().fill(.primary.opacity(0.05)).frame(width:1)} }
                }
            }.frame(minWidth:906)
        }.background(palette.paper(scheme),in:RoundedRectangle(cornerRadius:12))
    }
    var horizontalWeek:some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing:0) {
                HStack(spacing:0) {
                    Text("DAY / TIME").font(.caption2).frame(width:80)
                    ForEach(0..<24) { hour in
                        Text(clock(hour*60)).font(.system(size:10,design:.monospaced)).frame(width:90,alignment:.leading)
                    }
                }.frame(height:40)
                ForEach(week,id:\.self) { day in
                    let items = store.termDatabase.agenda(on:day)
                    HStack(spacing:0) {
                        dayHeader(day).frame(width:80)
                        ZStack(alignment:.topLeading) {
                            HStack(spacing:0) {
                                ForEach(0..<24) { _ in Rectangle().fill(.primary.opacity(0.06)).frame(width:1); Color.clear.frame(width:89) }
                            }
                            // Separate lanes preserve access to overlapping classes, sessions and deadlines.
                            ForEach(Array(items.enumerated()),id:\.element.id) { index,item in
                                let range = item.minuteRange(on:day,calendar:cal)
                                eventChip(item)
                                    .frame(width:max(58,(range.upperBound-range.lowerBound)*1.5-3),height:46)
                                    .offset(x:min(range.lowerBound*1.5,2102),y:CGFloat(index)*50+4)
                            }
                        }.frame(width:2160,height:CGFloat(max(1,items.count))*50+8)
                    }.overlay(alignment:.bottom) { Rectangle().fill(.primary.opacity(0.08)).frame(height:1) }
                }
            }
        }.background(palette.paper(scheme),in:RoundedRectangle(cornerRadius:12))
    }
    var monthGrid:some View {
        let start=cal.dateInterval(of:.month,for:selected)!.start
        let offset=(cal.component(.weekday,from:start)+5)%7
        let count=cal.range(of:.day,in:.month,for:selected)!.count
        return ScrollView { LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:1),count:7),spacing:1) {
            ForEach(dayNames,id:\.self){Text(String($0.prefix(3))).font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(8)}
            ForEach(0..<(Int(ceil(Double(count+offset)/7))*7),id:\.self) { i in
                let d=cal.date(byAdding:.day,value:i-offset,to:start)!
                VStack(alignment:.leading,spacing:7) { Button { selected=d;mode = .day } label:{Text(d,format:.dateTime.day()).font(.system(size:14,weight:.medium))}.buttonStyle(.plain); if i >= offset && i < count+offset { ForEach(store.termDatabase.agenda(on:d).prefix(3)) { item in eventChip(item).frame(height:28) }; if store.termDatabase.agenda(on:d).count > 3 { Text("+\(store.termDatabase.agenda(on:d).count-3) more").font(.system(size:9)).foregroundStyle(.secondary) } }; Spacer(minLength:0) }.padding(8).frame(maxWidth:.infinity,minHeight:142,alignment:.topLeading).background(palette.paper(scheme).opacity(i >= offset && i < count+offset ? 1 : 0.3))
            }
        } }
    }
    func eventChip(_ item:AgendaItem) -> some View {
        Button { if let id=item.eventID,let e=store.termDatabase.events.first(where:{$0.id == id}) { editor = .event(e) } else if let id=item.taskID,let t=store.termDatabase.tasks.first(where:{$0.id == id}) { editor = .task(t) } else if let s=store.termDatabase.classes.first(where:{$0.id.uuidString == item.id}) { editor = .slot(s) } } label: { VStack(alignment:.leading,spacing:3) { Text(item.title).font(.system(size:10,weight:.semibold)).lineLimit(2); Text(item.start,format:.dateTime.hour().minute()).font(.system(size:9)) }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).padding(5).foregroundStyle(Color.subject(store.termDatabase.subject(item.subjectID)?.color ?? 0)).background(Color.subject(store.termDatabase.subject(item.subjectID)?.color ?? 0).opacity(0.13),in:RoundedRectangle(cornerRadius:5)) }.buttonStyle(.plain)
    }
}

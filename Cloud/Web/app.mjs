import { days, icon, el, addDays, weekStart, weekLabel, periodLabel, renderSchedule, renderOverview, renderProgress, shortDate, fullDate, time, weekTasks, widgetRow, samplePlanner } from "./planner-ui.mjs";
import { devicePlanner, openOfflineStore, privatePlanner } from "./offline.mjs";
import { projectURL, publishableKey } from "./config.mjs";
import { cloudClient, legacyTermID, localDate, newTask, plannerTerm, recordsOf, saveRecord, saveTask, shareWorkspace, swiftDate, uuid, workspaceFor } from "./sync.mjs";

const byId = id => document.getElementById(id);
let statusTimer;
const status = message => {
  clearTimeout(statusTimer);
  byId("status").textContent = message;
  if (message === "บันทึกในเครื่องแล้ว") statusTimer = setTimeout(() => {
    byId("status").textContent = "";
  }, 2600);
  const popupStatus = document.querySelector(".editor-dialog[open] .popup-status");
  if (popupStatus) popupStatus.textContent = message;
};
const date = new Intl.DateTimeFormat("th-TH", { dateStyle: "medium", timeStyle: "short" });
const desktop = location.hostname === "studyflow-planner.example";
const windows = !desktop && navigator.userAgent.includes("Windows");
const workerReady = !desktop && "serviceWorker" in navigator
  ? navigator.serviceWorker.register("./widget-worker.js").then(() => navigator.serviceWorker.ready).catch(() => null)
  : Promise.resolve(null);
let currentWidgetData = null;
let workspace, cloud, localPlanner, device, storage, currentReplica, activeTermID = legacyTermID, busy = false, shared = false;
const connectionStatus = message => { byId("connection-status").textContent = message; };
const getStore = () => storage ??= openOfflineStore();
const isLocal = () => !workspace && !!device;
let editedClass;
const editorDialogs = document.querySelectorAll(".editor-dialog");

function showMode() {
  byId("show-connect").hidden = !!workspace;
  byId("refresh").hidden = !workspace;
  byId("disconnect").hidden = !workspace;
  byId("create-sync-actions").hidden = !isLocal();
  byId("planner").hidden = !workspace && !device;
}

const node = el;

function row(title, detail) {
  const item = node("div", "", "row");
  item.append(node("strong", title), node("span", detail, "muted"));
  return item;
}

function pushWidget(data) {
  if (!windows) return;
  void workerReady.then(worker => worker?.active?.postMessage({ type: "studyflow-widget", data }));
}

let displayed, selectedDate = new Date(), page = "timetable", mode = "week", demo = false, nextClass;
const pages = { overview: ["Overview","ภาพรวม"], timetable: ["Timetable","ตารางเรียน"],
  calendar: ["Calendar","ปฏิทิน"], tasks: ["Tasks","งาน"], subjects: ["Subjects","วิชา"],
  notes: ["Notes","โน้ต"], analytics: ["Analytics","สถิติ"], settings: ["Settings","การตั้งค่า"] };
const termName = () => demo ? "ภาคเรียนที่ 1 / 2569" : shared ? "ชุดแชร์" : byId("term-picker").selectedOptions[0]?.textContent || "My Term";
const readOnly = () => shared || demo;
let theme = "classic";
try {
  const stored = localStorage.getItem("studyflow-theme");
  if (["retro", "honey", "lilac"].includes(stored)) theme = stored;
} catch {}
byId("theme-picker").value = theme;
document.documentElement.dataset.theme = theme;
byId("theme-picker").addEventListener("change", event => {
  document.documentElement.dataset.theme = event.currentTarget.value;
  try { localStorage.setItem("studyflow-theme", event.currentTarget.value); } catch {}
});

for (const target of document.querySelectorAll("[data-icon]")) target.append(icon(target.dataset.icon));
for (const [key, [label]] of Object.entries(pages).filter(([key]) => key !== "settings")) {
  const button = node("button", "", "nav-button");
  button.type = "button";
  button.dataset.page = key;
  button.append(icon(key), node("span", label));
  if (key === "tasks") button.append(node("small", "", "task-badge"));
  byId("navigation").append(button);
}
function selectPage(next) {
  if (next !== page && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
    document.querySelector("main").animate?.([{ opacity: 0.78 }, { opacity: 1 }], { duration: 170 });
  }
  if (next === "calendar" && page !== "calendar") mode = "month";
  if (next === "timetable" && page !== "timetable") mode = "week";
  page = next;
  drawPage();
}
document.addEventListener("click", event => {
  const control = event.target.closest("[data-page]");
  if (control) selectPage(control.dataset.page);
  const view = event.target.closest("[data-mode]");
  if (view) { mode = view.dataset.mode; drawPage(); }
  const editor = event.target.closest("[data-editor]");
  if (editor) openEditor(editor.dataset.editor);
  const dismiss = event.target.closest("[data-close-editor]");
  if (dismiss) dismiss.closest("dialog").close();
});
function stepPeriod(amount) {
  if (mode === "month") selectedDate = new Date(selectedDate.getFullYear(), selectedDate.getMonth() + amount, 1);
  else selectedDate = addDays(selectedDate, mode === "day" ? amount : amount * 7);
  drawPage();
}
byId("previous-period").addEventListener("click", () => stepPeriod(-1));
byId("next-period").addEventListener("click", () => stepPeriod(1));
const controls = byId("control-dialog");
const compactLayout = matchMedia("(max-width: 760px)");
function showControls(title, items) {
  byId("control-title").textContent = title;
  byId("control-items").replaceChildren(...items);
  controls.showModal();
}
function menuItem(title, action, disabled = false) {
  const button = node("button", title, "quick-result");
  button.type = "button";
  button.disabled = disabled;
  button.addEventListener("click", () => { controls.close(); action(); });
  return button;
}
function pickTerm() {
  const picker = byId("term-picker");
  const items = Array.from(picker.options, option => menuItem(option.text, () => {
    picker.value = option.value;
    picker.dispatchEvent(new Event("change"));
  }));
  if (!shared && !demo) items.push(menuItem("จัดการเทอม", () => selectPage("settings")));
  showControls("My Term", items);
}
function setDemo(value) {
  demo = value;
  try { localStorage.setItem("studyflow-demo", value ? "on" : "off"); } catch {}
  if (currentReplica) renderReplica(currentReplica);
}
byId("compact-term").addEventListener("click", pickTerm);
byId("demo-toggle").addEventListener("change", event => setDemo(event.currentTarget.checked));
byId("mobile-more").addEventListener("click", () => showControls("เพิ่มเติม", [
  menuItem("My Term", pickTerm), menuItem("ปฏิทิน", () => selectPage("calendar")),
  menuItem("วิชา", () => selectPage("subjects"), displayed?.selection?.timetable === false),
  menuItem("โน้ต", () => selectPage("notes"), displayed?.selection?.tasks === false),
  menuItem("สถิติ", () => selectPage("analytics"), displayed?.selection?.tasks === false),
  menuItem("ตั้งค่า", () => selectPage("settings")),
  ...(compactLayout.matches && displayed ? [menuItem("คาบและงานถัดไป", () => {
    const widget = byId("widget-card").cloneNode(true);
    widget.removeAttribute("id");
    for (const child of widget.querySelectorAll("[id]")) child.removeAttribute("id");
    showControls("StudyFlow", [widget]);
  })] : [])
]));
byId("today-period").addEventListener("click", () => {
  const field = node("input");
  field.type = "date";
  field.setAttribute("aria-label", "ไปที่วันที่");
  field.value = [selectedDate.getFullYear(), selectedDate.getMonth() + 1, selectedDate.getDate()].map(value => String(value).padStart(2, "0")).join("-");
  field.addEventListener("change", () => {
    if (!field.value) return;
    selectedDate = new Date(field.value + "T00:00");
    drawPage();
    controls.close();
  });
  showControls("ไปที่วันที่", [field, menuItem("วันนี้", () => { selectedDate = new Date(); drawPage(); })]);
});
byId("share-control").addEventListener("click", () => {
  selectPage("settings");
  if (!workspace) byId("show-connect").click();
});
function openEditor(key, slot) {
  if (shared || busy) return;
  if (demo) setDemo(false);
  if (key === "class" && !displayed?.subjects.length) return;
  const dialog = byId("edit-" + key);
  const form = byId("new-" + key);
  form.reset();
  dialog.querySelector(".popup-status").textContent = "";
  if (key === "class") {
    editedClass = slot;
    byId("title-class").textContent = slot ? "แก้ไขคาบเรียน" : "เพิ่มคาบเรียน";
    byId("class-day").value = slot?.weekday ?? (selectedDate.getDay() + 6) % 7;
    byId("class-start").value = time(slot?.start ?? 540);
    byId("class-end").value = time(slot?.end ?? 600);
    byId("class-kind").value = slot?.kind ?? "";
    byId("class-building").value = slot?.building ?? "";
    byId("class-room").value = slot?.room ?? "";
    if (slot) byId("class-subject").value = slot.subjectID;
  }
  if (key === "task") {
    const tomorrow = addDays(new Date(), 1);
    tomorrow.setMinutes(tomorrow.getMinutes() - tomorrow.getTimezoneOffset());
    byId("task-due").value = tomorrow.toISOString().slice(0, 16);
  }
  dialog.showModal();
}
function viewClass(slot) {
  if (!readOnly()) { openEditor("class", slot); return; }
  const subject = displayed.subjects.find(item => item.id === slot.subjectID);
  showControls(subject?.name || "คาบเรียน", [
    row(subject?.code || days[slot.weekday], `${days[slot.weekday]} · ${time(slot.start)} – ${time(slot.end)}`),
    row("สถานที่", [slot.building, slot.room].filter(Boolean).join(" ") || "ยังไม่ระบุ")
  ]);
}
byId("add-class").addEventListener("click", () => openEditor("subject"));
byId("schedule-more").addEventListener("click", () => showControls("ตัวเลือกตารางเรียน", [
  menuItem("เพิ่มคาบเรียน", () => openEditor("class"), readOnly() || !displayed?.subjects.length),
  menuItem("เพิ่มงาน", () => openEditor("task"), shared),
  menuItem("ดูงานทั้งหมด", () => selectPage("tasks"), displayed?.selection?.tasks === false),
  ...(workspace ? [] : [menuItem(demo ? "กลับไปข้อมูลจริง" : "ดูตัวอย่าง", () => setDemo(!demo))])
]));

function renderNextUp({ subjects, classes, tasks, selection }) {
  const now = new Date();
  const subjectNames = new Map(subjects.map(subject => [subject.id, subject.name]));
  const next = selection?.timetable === false ? null : classes.reduce((first, slot) => {
    const start = addDays(weekStart(now), slot.weekday);
    start.setHours(0, slot.start, 0, 0);
    if (start < now) start.setDate(start.getDate() + 7);
    const title = subjectNames.get(slot.subjectID);
    return title && (!first || start < first.start) ? { title, start, slot } : first;
  }, null);
  nextClass = next;
  const task = selection?.tasks === false ? null : tasks.find(item => item.status !== "Done");
  const detail = next ? `${shortDate.format(next.start)} · ${time(next.slot.start)} – ${time(next.slot.end)}` : "";
  const taskDetail = task ? date.format(localDate(task.due)) : "";
  const classTitle = next?.title || "ไม่มีคาบถัดไป";
  const taskTitle = task?.title || "ไม่มีงานค้าง";
  byId("next-class").replaceChildren(widgetRow("calendar", classTitle, detail));
  if (next && (next.slot.building || next.slot.room)) byId("next-class").append(node("small", [next.slot.building, next.slot.room].filter(Boolean).join(" "), "muted next-location"));
  byId("widget-term").replaceChildren(widgetRow("graduation", termName(), ""));
  byId("widget-class").replaceChildren(widgetRow("calendar", classTitle, detail));
  byId("widget-task").replaceChildren(widgetRow("tasks", taskTitle, taskDetail));
  byId("widget-class").hidden = selection?.timetable === false;
  byId("widget-task").hidden = selection?.tasks === false;
  byId("windows-widget-option").hidden = !windows || readOnly() || !workspace;
  currentWidgetData = readOnly() ? null : {
    term: termName().slice(0, 100), classTitle: classTitle.slice(0, 160), classDetail: detail,
    taskTitle: taskTitle.slice(0, 160), taskDetail,
    expiresAt: Math.min(now.getTime() + 21600000, next?.start.getTime() ?? Infinity),
  };
  pushWidget(byId("windows-widget-enabled").checked ? currentWidgetData : null);
}

function drawPage() {
  const data = displayed;
  const schedule = page === "timetable" || page === "calendar";
  byId("page-title").textContent = page === "overview" ? fullDate.format(selectedDate) : pages[page][1];
  byId("overview-eyebrow").hidden = page !== "overview";
  byId("term-name-line").replaceChildren(document.createTextNode(termName()));
  if (demo) byId("term-name-line").append(node("small", "ตัวอย่าง", "today-badge"));
  byId("today-label").textContent = "วันนี้ " + fullDate.format(new Date());
  byId("compact-term").textContent = termName() + (demo ? " · ตัวอย่าง" : "");
  byId("compact-term").hidden = shared;
  byId("demo-toggle").checked = demo;
  byId("demo-toggle").disabled = !!workspace;
  byId("schedule-modes").hidden = !schedule;
  byId("schedule-layout").hidden = !schedule;
  byId("overview-section").hidden = page !== "overview";
  byId("tasks-section").hidden = page !== "tasks";
  byId("subjects-section").hidden = page !== "subjects";
  byId("events-section").hidden = page !== "calendar" || data?.selection?.events === false;
  byId("notes-section").hidden = page !== "notes";
  byId("analytics-section").hidden = page !== "analytics";
  byId("settings-section").hidden = page !== "settings";
  for (const item of document.querySelectorAll("[data-page]")) {
    if (item.closest(".sidebar, #mobile-navigation")) item.setAttribute("aria-current", item.dataset.page === page ? "page" : "false");
  }
  for (const item of document.querySelectorAll("[data-mode]")) item.setAttribute("aria-pressed", String(item.dataset.mode === mode));
  if (!data) return;
  const { tasks, classes, selection } = data;
  for (const key of ["tasks", "notes", "analytics", "subjects"]) {
    byId("navigation").querySelector(`[data-page="${key}"]`).hidden = key === "subjects" ? selection?.timetable === false : selection?.tasks === false;
  }
  byId("schedule-section").hidden = selection?.timetable === false;
  byId("next-up").hidden = selection?.timetable === false;
  byId("notice-dot").hidden = !tasks.some(task => task.status !== "Done");
  byId("week-tasks").closest("section").hidden = selection?.tasks === false;
  byId("add-class").hidden = shared;
  byId("period-title").textContent = mode === "week" || mode === "list" ? weekLabel(weekStart(selectedDate)) : "เลือกวันที่";
  byId("period-range").textContent = periodLabel(selectedDate, mode);
  byId("compact-range").textContent = mode === "week" || mode === "list"
    ? `${shortDate.format(weekStart(selectedDate))} – ${shortDate.format(addDays(weekStart(selectedDate), 6))}`
    : shortDate.format(selectedDate);
  if (schedule && selection?.timetable !== false) renderSchedule(byId("timetable"), data, selectedDate, mode, day => {
    selectedDate = day; mode = "day"; drawPage();
  }, viewClass);
  const relevant = weekTasks(tasks, selectedDate);
  const open = relevant.filter(task => task.status !== "Done");
  const done = relevant.length - open.length;
  const badge = byId("navigation").querySelector(".task-badge");
  badge.textContent = String(tasks.filter(task => task.status !== "Done").length);
  badge.hidden = badge.textContent === "0";
  byId("week-tasks").replaceChildren(...(open.length ? open.slice(0, 3).map(task => {
    const item = node("div", "", "weekly-task");
    const toggle = node("button", "", "task-checkbox");
    toggle.type = "button";
    toggle.setAttribute("aria-label", "ทำเสร็จแล้ว " + task.title);
    toggle.disabled = readOnly();
    toggle.addEventListener("click", () => toggleTask(task));
    const text = node("div");
    text.append(node("strong", task.title), node("small", "ส่ง " + date.format(localDate(task.due)), "muted"));
    const priority = node("span", { High:"สูง", Medium:"กลาง", Low:"ต่ำ" }[task.priority] || "กลาง", `priority ${task.priority?.toLowerCase() || "medium"}`);
    item.append(toggle, text, priority);
    return item;
  }) : [node("p", "ไม่มีงานค้างสัปดาห์นี้", "muted")]));
  const progress = node("progress");
  progress.max = relevant.length || 1;
  progress.value = done;
  progress.setAttribute("aria-label", "งานเสร็จ");
  const summary = [];
  if (selection?.tasks !== false) {
    const completed = widgetRow("tasks", "งานเสร็จ", `${done} / ${relevant.length}`);
    completed.append(node("strong", `${relevant.length ? Math.round(100 * done / relevant.length) : 0}%`, "summary-percent"));
    summary.push(completed, progress);
  }
  if (selection?.timetable !== false) summary.push(widgetRow("calendar", "คาบเรียน", `${classes.length} คาบ`));
  byId("week-summary").replaceChildren(...summary);
  byId("week-summary").parentElement.hidden = !summary.length;
  if (page === "overview") renderOverview(byId("overview-section"), data, selectedDate, nextClass, day => {
    selectedDate = day; drawPage();
  }, () => selectPage("timetable"));
  if (page === "analytics") renderProgress(byId("analytics"), relevant);
}

function quickResults(search) {
  const needle = byId("quick-search").value.trim().toLocaleLowerCase();
  const data = displayed;
  const items = !data ? [] : search
    ? [...data.subjects.map(item => [item.name, item.code, "subjects"]),
       ...data.tasks.map(item => [item.title, date.format(localDate(item.due)), "tasks"])]
      .filter(item => item.slice(0, 2).some(value => value?.toLocaleLowerCase().includes(needle)))
    : data.tasks.filter(item => item.status !== "Done")
      .map(item => [item.title, date.format(localDate(item.due)), "tasks"]);
  byId("quick-results").replaceChildren(...(items.length ? items.slice(0, 12).map(([title, detail, target]) => {
    const result = node("button", "", "quick-result");
    result.append(node("strong", title), node("small", detail));
    result.addEventListener("click", () => {
      byId("quick-dialog").close();
      selectPage(target);
    });
    return result;
  }) : [node("p", search ? "ไม่พบรายการ" : "ไม่มีงานค้าง", "muted")]));
}
function openQuick(search) {
  byId("quick-title").textContent = search ? "ค้นหา" : "งานที่ใกล้กำหนดส่ง";
  byId("quick-search-label").hidden = !search;
  byId("quick-search").value = "";
  quickResults(search);
  byId("quick-dialog").showModal();
  if (search) byId("quick-search").focus();
}
byId("open-search").addEventListener("click", () => openQuick(true));
byId("open-notices").addEventListener("click", () => openQuick(false));
byId("quick-search").addEventListener("input", () => quickResults(true));

function toggleTask(task) {
  if (readOnly()) return;
  return synchronize(latest => {
    const current = recordsOf(latest, "task").find(value => value.id === task.id);
    if (!current) throw Error("งานนี้ถูกลบจากอีกเครื่องแล้ว");
    return saveTask(latest, { ...current, status: task.status === "Done" ? "To do" : "Done" });
  });
}

byId("windows-widget-enabled").addEventListener("change", event =>
  pushWidget(event.currentTarget.checked ? currentWidgetData : null)
);

function render({ subjects, classes, tasks, events, selection }) {
  tasks = tasks.slice().sort((a, b) => a.due - b.due);
  events = events.slice().sort((a, b) => a.start - b.start);
  displayed = { subjects, classes, tasks, events, selection };
  renderNextUp(displayed);
  for (const button of document.querySelectorAll("[data-editor]")) button.hidden = shared;
  if (shared) for (const dialog of editorDialogs) if (dialog.open) dialog.close();
  const subjectName = id => subjects.find(subject => subject.id === id)?.name || "";
  const list = (id, rows, empty) => byId(id).replaceChildren(...(rows.length ? rows : [node("p", empty, "muted")]));
  list("notes", tasks.filter(task => task.notes).map(task => row(task.title, task.notes)), "ยังไม่มีโน้ต");
  list("subjects", subjects.map(subject => row(subject.name, [subject.code, subject.teacher].filter(Boolean).join(" · "))), "ยังไม่มีวิชา");
  list("events", events.map(event => row(event.title, [
    `${date.format(localDate(event.start))} – ${date.format(localDate(event.end))}`,
    event.location, tasks.find(task => task.id === event.taskID)?.title
  ].filter(Boolean).join(" · "))), "ยังไม่มีกิจกรรม");
  list("tasks", tasks.map(task => {
    const item = row(task.title, [date.format(localDate(task.due)), subjectName(task.subjectID),
      { "To do": "ยังไม่เริ่ม", "In progress": "กำลังทำ", Done: "เสร็จแล้ว" }[task.status]].filter(Boolean).join(" · "));
    if (task.notes) item.append(node("p", task.notes));
    for (const subtask of task.subtasks) item.append(node("span", `${subtask.done ? "✓" : "○"} ${subtask.title}`, "muted"));
    if (readOnly()) return item;
    const toggle = node("button", task.status === "Done" ? "เปิดงานอีกครั้ง" : "ทำเสร็จแล้ว", "plain");
    toggle.addEventListener("click", () => toggleTask(task));
    item.append(toggle);
    return item;
  }), "ยังไม่มีงาน");
  const selected = byId("task-subject").value;
  byId("task-subject").replaceChildren(new Option("ไม่ผูกวิชา", ""), ...subjects.map(subject => new Option(subject.name, subject.id)));
  if (subjects.some(subject => subject.id === selected)) byId("task-subject").value = selected;
  const classSubject = byId("class-subject");
  const classSelected = classSubject.value;
  classSubject.replaceChildren(...subjects.map(subject => new Option(subject.name, subject.id)));
  if (subjects.some(subject => subject.id === classSelected)) classSubject.value = classSelected;
  drawPage();
}

function renderReplica(replica) {
  currentReplica = replica;
  const terms = recordsOf(replica, "term");
  const defaultTerm = terms.find(term => term.id === legacyTermID) || { id: legacyTermID, name: "เทอมเดิม" };
  const choices = [defaultTerm, ...terms.filter(term => term.id !== legacyTermID)
    .sort((a, b) => a.name.localeCompare(b.name, "th"))];
  if (!choices.some(term => term.id === activeTermID)) activeTermID = legacyTermID;
  const picker = byId("term-picker");
  picker.replaceChildren(...choices.map(term => new Option(term.name, term.id)));
  picker.value = activeTermID;
  byId("term-control").hidden = false;
  render(demo ? samplePlanner() : plannerTerm(replica, activeTermID));
}

byId("term-picker").addEventListener("change", event => {
  activeTermID = event.currentTarget.value;
  if (demo) setDemo(false);
  else if (currentReplica) renderReplica(currentReplica);
});

async function synchronize(change) {
  if (busy || (change && readOnly()) || (!workspace && (!device || !change))) return false;
  busy = true;
  const buttons = Array.from(editorDialogs, dialog => dialog.querySelector("button[type=submit]"));
  for (const button of buttons) button.disabled = true;
  for (const toggle of byId("tasks").querySelectorAll("button")) toggle.disabled = true;
  try {
    if (shared) {
      let payload;
      try {
        payload = await cloud.readShare(workspace);
      } catch {
        await disconnect();
        throw Error("เปิดชุดแชร์ไม่ได้ · เชื่อมอินเทอร์เน็ตแล้วลองใหม่");
      }
      if (!payload) {
        await disconnect();
        status("ไม่พบชุดแชร์ ตรวจโค้ดกับรหัส หรือขอชุดแชร์ใหม่");
        return false;
      }
      byId("term-control").hidden = true;
      if (["subjects","tasks","analytics","notes"].includes(page)) page = "timetable";
      render(payload);
      status("อัปเดตชุดแชร์แล้ว · ดูได้อย่างเดียว");
      return true;
    }
    if (change) {
      const state = await (workspace ? localPlanner : device).edit(change);
      renderReplica(state.replica);
      status(workspace ? "บันทึกในเครื่องแล้ว · รอซิงก์" : "บันทึกในเครื่องแล้ว");
      return true;
    }
    try {
      if (!navigator.onLine) throw Error("กำลังออฟไลน์");
      const state = await localPlanner.sync();
      renderReplica(state.replica);
      status(state.conflicts ? "ซิงก์แล้ว · บางรายการใช้การแก้ไขจากอีกเครื่อง" : "ซิงก์แล้ว");
      return true;
    } catch (error) {
      const state = await localPlanner.local();
      if (!state) throw error;
      renderReplica(state.replica);
      const pending = Object.keys(state.pending).length;
      const detail = error.code === "workspace-missing" ? "ไม่พบชุดข้อมูลบนคลาวด์" : "ยังติดต่อคลาวด์ไม่ได้";
      status(pending ? `${detail} · รอซิงก์ ${pending} รายการ` : `${detail} · แสดงข้อมูลในเครื่อง`);
      return true;
    }
  } catch (error) { status(error.message); }
  finally {
    busy = false;
    for (const button of buttons) button.disabled = false;
    for (const toggle of byId("tasks").querySelectorAll("button")) toggle.disabled = false;
    if (change && workspace && navigator.onLine) setTimeout(() => synchronize(), 0);
  }
  return false;
}

async function openWorkspace(code, password) {
  cloud = cloudClient(projectURL, publishableKey);
  const useShare = password.length > 0 || code.trim().length === 6;
  const candidate = useShare ? await shareWorkspace(code, password) : await workspaceFor(code);
  localPlanner = useShare ? undefined : privatePlanner(candidate, cloud, await getStore());
  demo = false;
  workspace = candidate;
  shared = useShare;
  const opened = await synchronize();
  if (!opened) {
    const error = byId("status").textContent;
    await disconnect();
    throw Error(error);
  }
  showMode();
}

byId("join").addEventListener("submit", async event => {
  event.preventDefault();
  if (busy) return;
  const form = event.currentTarget;
  const button = form.querySelector("button");
  button.disabled = true;
  connectionStatus("");
  try {
    await openWorkspace(byId("code").value, byId("share-password").value);
    form.reset();
    byId("connect").hidden = true;
  } catch (error) {
    byId("connect").hidden = false;
    connectionStatus(error.message);
  } finally { button.disabled = false; }
});

let creationCode;
byId("create-sync").addEventListener("click", async event => {
  if (busy || !isLocal()) return;
  const button = event.currentTarget;
  button.disabled = true;
  connectionStatus("");
  try {
    const client = cloudClient(projectURL, publishableKey);
    creationCode ??= Array.from(crypto.getRandomValues(new Uint8Array(16)), byte =>
      byte.toString(16).padStart(2, "0")).join("").toUpperCase();
    const candidate = await workspaceFor(creationCode);
    busy = true;
    try {
      const { replica } = await device.local();
      if (!await client.write(candidate, 0, replica)) await client.read(candidate);
    } finally { busy = false; }
    await openWorkspace(creationCode, "");
    byId("created-code").value = creationCode.match(/.{4}/g).join("-");
    byId("created-code-label").hidden = false;
    byId("create-sync-actions").hidden = false;
    button.hidden = true;
    byId("join").hidden = true;
    connectionStatus("คัดลอกโค้ดไว้ใช้กับอุปกรณ์อื่น · ผู้ที่มีโค้ดนี้แก้ชุดข้อมูลได้");
    creationCode = undefined;
  } catch (error) { connectionStatus(error.message); }
  finally { button.disabled = false; }
});

byId("new-task").addEventListener("submit", async event => {
  event.preventDefault();
  const form = event.currentTarget;
  const title = byId("task-title").value.trim();
  const due = new Date(byId("task-due").value);
  if (!title || Number.isNaN(due.getTime())) return;
  if (due < new Date()) { status("กำหนดส่งต้องอยู่หลังเวลาที่เพิ่มงาน"); return; }
  const task = newTask(title, due, byId("task-subject").value, activeTermID);
  if (await synchronize(replica => saveTask(replica, task))) { form.reset(); form.closest("dialog").close(); }
});
function addEditor(id, entity, valueFor) {
  byId(id).addEventListener("submit", async event => {
    event.preventDefault();
    const form = event.currentTarget;
    const value = valueFor();
    if (!value) { status("ตรวจชื่อและเวลาให้ครบก่อนบันทึก"); return; }
    const id = entity === "class" && editedClass ? editedClass.id : uuid();
    if (await synchronize(replica => saveRecord(replica, entity, { ...value, id }))) {
      form.reset();
      form.closest("dialog").close();
      if (entity === "term") { activeTermID = id; renderReplica(currentReplica); }
    }
  });
}

const valueOf = id => byId(id).value.trim();
const forTerm = () => activeTermID === legacyTermID ? undefined : activeTermID;
const minutes = input => {
  const [hour, minute] = valueOf(input).split(":").map(Number);
  return hour * 60 + minute;
};
byId("class-day").replaceChildren(...days.map((day, weekday) => new Option(day, weekday)));
addEditor("new-term", "term", () => valueOf("term-name") && { name: valueOf("term-name") });
addEditor("new-subject", "subject", () => valueOf("subject-name") && {
  name: valueOf("subject-name"), code: valueOf("subject-code"), teacher: valueOf("subject-teacher"),
  color: Number(valueOf("subject-color")), termID: forTerm()
});
addEditor("new-class", "class", () => {
  const start = minutes("class-start"), end = minutes("class-end");
  if (!(end > start) || !valueOf("class-subject")) return;
  return { ...editedClass, subjectID: valueOf("class-subject"), weekday: Number(valueOf("class-day")),
    start, end, room: valueOf("class-room"), building: valueOf("class-building") || undefined,
    kind: valueOf("class-kind") || undefined };
});
addEditor("new-event", "event", () => {
  const start = new Date(valueOf("event-start")), end = new Date(valueOf("event-end"));
  if (!(end > start) || !valueOf("event-title")) return;
  return { title: valueOf("event-title"), start: swiftDate(start), end: swiftDate(end), location: "", termID: forTerm() };
});

byId("refresh").addEventListener("click", () => synchronize());
byId("show-connect").addEventListener("click", () => {
  byId("connect").hidden = false;
  connectionStatus("");
  byId("code").focus();
});
drawPage();
byId("cancel-connect").addEventListener("click", () => {
  if (busy) return;
  byId("connect").hidden = true;
  byId("created-code").value = "";
  byId("created-code-label").hidden = true;
  byId("join").hidden = false;
  byId("create-sync").hidden = false;
  showMode();
});

async function disconnect() {
  workspace = undefined;
  currentReplica = undefined;
  localPlanner = undefined;
  currentWidgetData = null;
  shared = false;
  demo = false;
  byId("windows-widget-enabled").checked = false;
  pushWidget(null);
  activeTermID = legacyTermID;
  byId("connect").hidden = !!device;
  byId("created-code").value = "";
  byId("created-code-label").hidden = true;
  byId("join").hidden = false;
  byId("create-sync").hidden = false;
  byId("new-task").reset();
  if (device) {
    const { replica } = await device.local();
    let choice;
    try { choice = localStorage.getItem("studyflow-demo"); } catch {}
    demo = choice === "on" || (choice == null && !Object.keys(replica.records).length);
    renderReplica(replica);
    status("");
  } else {
    for (const id of ["timetable", "subjects", "tasks", "events"]) byId(id).replaceChildren();
    status("ยกเลิกการเชื่อมแล้ว");
  }
  showMode();
}
byId("disconnect").addEventListener("click", () => { if (!busy) void disconnect().catch(error => status(error.message)); });
window.addEventListener("online", () => synchronize());
document.addEventListener("visibilitychange", () => {
  if (!document.hidden && navigator.onLine) synchronize();
});
setInterval(() => { if (!document.hidden && navigator.onLine) synchronize(); }, 15000);

(async () => {
  device = await devicePlanner(await getStore());
  await disconnect();
})().catch(() => {
  byId("connect").hidden = false;
  status("เบราว์เซอร์ยังเปิดพื้นที่บันทึกในเครื่องไม่ได้");
});

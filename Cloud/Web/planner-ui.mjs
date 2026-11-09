import { localDate } from "./sync.mjs";

export const days = ["จันทร์", "อังคาร", "พุธ", "พฤหัสบดี", "ศุกร์", "เสาร์", "อาทิตย์"];
export const shortDate = new Intl.DateTimeFormat("th-TH", { day: "numeric", month: "short" });
export const fullDate = new Intl.DateTimeFormat("th-TH", { dateStyle: "full" });
const dateYear = new Intl.DateTimeFormat("th-TH", { day: "numeric", month: "short", year: "numeric" });
export const time = minutes => `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
const tones = ["#57a37d","#47a6f0","#9170d4","#e8964a","#40a3ab","#e85987","#5cba6e","#ebad42","#7587a0","#61bae0"];
const paths = {
  overview: "M3 11l9-8 9 8M5 10v10h5v-6h4v6h5V10",
  timetable: "M5 4h14a2 2 0 012 2v13a2 2 0 01-2 2H5a2 2 0 01-2-2V6a2 2 0 012-2zM3 9h18m-13 4h1m3 0h1m3 0h1m-9 4h1m3 0h1m3 0h1",
  calendar: "M7 3v4m10-4v4M3 9h18M5 5h14a2 2 0 012 2v12a2 2 0 01-2 2H5a2 2 0 01-2-2V7a2 2 0 012-2z",
  tasks: "M9 11l3 3 8-8m0 6v6a2 2 0 01-2 2H6a2 2 0 01-2-2V6a2 2 0 012-2h9",
  subjects: "M12 3l9 5-9 5-9-5 9-5zm-9 9l9 5 9-5M3 16l9 5 9-5",
  notes: "M6 3h12a2 2 0 012 2v14a2 2 0 01-2 2H6a2 2 0 01-2-2V5a2 2 0 012-2zm2 6h8m-8 4h8m-8 4h4",
  analytics: "M4 15h3v6H4zm6-6h3v12h-3zm6-6h3v18h-3z",
  settings: "M12 8a4 4 0 100 8 4 4 0 000-8zM10 2h4l1 3 3 1 3 2-1 3v2l1 3-3 2-3 1-1 3h-4l-1-3-3-1-3-2 1-3v-2L3 8l3-2 3-1z",
  graduation: "M2 9l10-5 10 5-10 5-10-5zm4 2v6l6 3 6-3v-6m4-2v7",
  left: "M15 5l-7 7 7 7", right: "M9 5l7 7-7 7", down: "M5 9l7 7 7-7",
  more: "M5 12h.1m6.9 0h.1m6.9 0h.1",
  share: "M8 8H5v13h14V8h-3m-4 7V2m-4 4 4-4 4 4",
  search: "M10 3a7 7 0 100 14 7 7 0 000-14zm5 12l6 6",
  bell: "M5 17h14l-2-4V9a5 5 0 10-10 0v4zm5 3a2 2 0 004 0",
  profile: "M12 3a9 9 0 100 18 9 9 0 000-18zm0 4a2.5 2.5 0 100 5 2.5 2.5 0 000-5zm-5 11c1-5 9-5 10 0",
  plus: "M12 5v14M5 12h14", clock: "M12 3a9 9 0 100 18 9 9 0 000-18zm0 4v5l3 2",
  pin: "M12 22s6-7 6-12a6 6 0 10-12 0c0 5 6 12 6 12zm0-14a2 2 0 100 4 2 2 0 000-4z"
};

export function icon(name) {
  const ns = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(ns, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("aria-hidden", "true");
  const path = document.createElementNS(ns, "path");
  path.setAttribute("d", paths[name]);
  svg.append(path);
  return svg;
}

export function el(tag, text, css) {
  const result = document.createElement(tag);
  if (text) result.textContent = text;
  if (css) result.className = css;
  return result;
}

export function addDays(date, days) {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}
export const weekday = date => (date.getDay() + 6) % 7;
export function weekStart(date) {
  const result = addDays(date, -weekday(date));
  result.setHours(0, 0, 0, 0);
  return result;
}
const sameDay = (a, b) => a.toDateString() === b.toDateString();

export function weekLabel(start) {
  const thursday = addDays(start, 3);
  const first = weekStart(new Date(thursday.getFullYear(), 0, 4));
  const span = Date.UTC(start.getFullYear(), start.getMonth(), start.getDate()) - Date.UTC(first.getFullYear(), first.getMonth(), first.getDate());
  return `สัปดาห์ที่ ${1 + Math.round(span / 604800000)}`;
}

export function periodLabel(day, mode) {
  if (mode === "month") return new Intl.DateTimeFormat("th-TH", { month: "long", year: "numeric" }).format(day);
  if (mode === "day") return fullDate.format(day);
  return `${shortDate.format(weekStart(day))} – ${dateYear.format(addDays(weekStart(day), 6))}`;
}

function iconText(name, text, css) {
  const result = el("span", "", css);
  result.append(icon(name), document.createTextNode(text));
  return result;
}

function classCard(slot, subject, openClass) {
  const card = el("button", "", "class-card");
  card.type = "button";
  card.addEventListener("click", () => openClass(slot));
  const code = el("strong", subject?.code || subject?.name || "คาบเรียน");
  const title = el("span", subject?.code ? subject.name : "", "class-title");
  const meta = el("div", "", "class-meta");
  const location = [slot.building, slot.room].filter(Boolean).join(" ");
  meta.append(iconText("clock", `${time(slot.start)} – ${time(slot.end)}`));
  if (location) meta.append(iconText("pin", location));
  card.style.setProperty("--tone", tones[Math.abs(subject?.color ?? 0) % tones.length]);
  card.append(code);
  if (slot.kind) card.append(el("span", slot.kind, "class-kind"));
  if (title.textContent) card.append(title);
  card.append(meta);
  card.title = [subject?.code, subject?.name, time(slot.start), time(slot.end), location].filter(Boolean).join(" · ");
  return card;
}

function dayLabel(day, today) {
  const heading = el("h3", days[weekday(day)], "day-label");
  heading.append(el("span", shortDate.format(day)));
  if (sameDay(day, today)) {
    heading.append(el("small", "วันนี้", "today-badge"));
    heading.setAttribute("aria-current", "date");
  }
  return heading;
}

export function renderSchedule(container, data, selected, mode, openDay, openClass) {
  const today = new Date();
  const start = weekStart(selected);
  const subjects = new Map(data.subjects.map(subject => [subject.id, subject]));
  const classes = data.classes.slice().sort((a, b) => a.start - b.start);
  container.className = `schedule schedule-${mode}`;
  container.replaceChildren();
  if (mode === "month") {
    const first = new Date(selected.getFullYear(), selected.getMonth(), 1);
    for (const day of days) container.append(el("div", day, "month-heading"));
    for (let i = 0; i < 42; i++) {
      const day = addDays(weekStart(first), i);
      const button = el("button", String(day.getDate()), "month-day");
      button.type = "button";
      button.setAttribute("aria-label", fullDate.format(day));
      if (sameDay(day, today)) button.setAttribute("aria-current", "date");
      if (day.getMonth() !== first.getMonth()) button.classList.add("outside-month");
      const count = classes.filter(slot => slot.weekday === weekday(day)).length;
      if (count) button.append(el("small", `${count} คาบ`));
      button.addEventListener("click", () => openDay(day));
      container.append(button);
    }
    return;
  }
  if (mode === "list") {
    for (let i = 0; i < 7; i++) {
      const day = addDays(start, i);
      const row = el("section", "", "list-day");
      row.append(dayLabel(day, today));
      const cards = classes.filter(slot => slot.weekday === i);
      row.append(...(cards.length ? cards.map(slot => classCard(slot, subjects.get(slot.subjectID), openClass)) : [el("span", "ไม่มีคาบ", "muted")]));
      container.append(row);
    }
    return;
  }

  const from = Math.min(480, ...classes.map(slot => Math.floor(slot.start / 60) * 60));
  const to = Math.max(1080, ...classes.map(slot => Math.ceil(slot.end / 60) * 60));
  const duration = to - from;
  const grid = el("div", "", "timeline");
  grid.style.setProperty("--hours", duration / 60);
  const head = el("div", "", "timeline-head");
  const ticks = el("div", "", "ticks");
  for (let value = from; value <= to; value += 60) {
    const tick = el("span", time(value));
    tick.style.left = `${100 * (value - from) / duration}%`;
    ticks.append(tick);
  }
  head.append(el("span"), ticks);
  grid.append(head);
  const dates = mode === "day" ? [selected] : days.map((_, i) => addDays(start, i));
  for (const day of dates) {
    const row = el("div", "", "timeline-day");
    const track = el("div", "", "track");
    const laneEnds = [];
    for (const slot of classes.filter(slot => slot.weekday === weekday(day))) {
      let lane = laneEnds.findIndex(end => end <= slot.start);
      if (lane < 0) lane = laneEnds.length;
      laneEnds[lane] = slot.end;
      const card = classCard(slot, subjects.get(slot.subjectID), openClass);
      card.style.setProperty("--start", `${100 * (slot.start - from) / duration}%`);
      card.style.setProperty("--duration", `${100 * (slot.end - slot.start) / duration}%`);
      card.style.setProperty("--lane", lane);
      track.append(card);
    }
    if (laneEnds.length > 1) row.style.setProperty("--lanes", laneEnds.length);
    row.append(dayLabel(day, today), track);
    grid.append(row);
  }
  const minute = today.getHours() * 60 + today.getMinutes();
  if (dates.some(day => sameDay(day, today)) && minute >= from && minute <= to) {
    const marker = el("div", "", "now-line");
    marker.style.setProperty("--position", (minute - from) / duration);
    marker.append(el("span", time(minute)));
    grid.append(marker);
  }
  container.append(grid);
}

export function weekTasks(tasks, selected) {
  const start = weekStart(selected);
  const end = addDays(start, 7);
  return tasks.filter(task => {
    const due = localDate(task.due);
    return due >= start && due < end;
  });
}

export function widgetRow(name, title, detail) {
  const row = el("div", "", "widget-row");
  row.append(icon(name), el("span", title), el("time", detail));
  return row;
}

export function renderProgress(container, tasks) {
  const done = tasks.filter(task => task.status === "Done").length;
  const percent = tasks.length ? Math.round(100 * done / tasks.length) : 0;
  const ring = el("div", "", "progress-ring");
  ring.style.setProperty("--progress", `${percent}%`);
  const center = el("div");
  center.append(el("strong", `${percent}%`), el("small", "เสร็จแล้ว"));
  ring.append(center);
  const legend = el("div", "", "progress-legend");
  legend.append(el("span", `●  เสร็จ   ${done} งาน`), el("span", `○  เหลือ   ${tasks.length - done} งาน`));
  container.replaceChildren(ring, legend);
}

export function renderOverview(container, data, selected, next, selectDate, openSchedule) {
  const today = new Date();
  const start = weekStart(selected);
  const agenda = el("section", "", "panel agenda");
  const title = el("div", "", "rail-heading");
  const open = el("button", "↗ เปิดตารางเรียน", "text-button");
  open.addEventListener("click", openSchedule);
  title.append(el("strong", periodLabel(selected, "week")), open);
  const strip = el("div", "", "week-strip");
  for (let i = 0; i < 7; i++) {
    const day = addDays(start, i);
    const button = el("button", "", sameDay(day, selected) ? "selected" : "");
    button.setAttribute("aria-label", fullDate.format(day));
    button.append(el("span", days[i]), el("strong", String(day.getDate())));
    button.addEventListener("click", () => selectDate(day));
    strip.append(button);
  }
  const entries = [];
  for (const slot of data.classes.filter(slot => slot.weekday === weekday(selected))) {
    const subject = data.subjects.find(subject => subject.id === slot.subjectID);
    entries.push([time(slot.start), subject?.name || "คาบเรียน", [time(slot.end), slot.building, slot.room].filter(Boolean).join(" · ")]);
  }
  for (const task of data.tasks.filter(task => sameDay(localDate(task.due), selected))) {
    const due = localDate(task.due);
    entries.push([time(due.getHours() * 60 + due.getMinutes()), task.title, "กำหนดส่ง"]);
  }
  for (const event of data.events.filter(event => sameDay(localDate(event.start), selected))) {
    const start = localDate(event.start);
    entries.push([time(start.getHours() * 60 + start.getMinutes()), event.title, event.location || "กิจกรรม"]);
  }
  entries.sort((a, b) => a[0].localeCompare(b[0]));
  const agendaHeading = el("div", "", "rail-heading agenda-heading");
  agendaHeading.append(el("h2", "กำหนดการ"), el("span", sameDay(selected, today) ? "วันนี้" : shortDate.format(selected), "muted"));
  agenda.append(title, strip, agendaHeading);
  for (const [hour, name, detail] of entries) {
    const item = el("div", "", "agenda-row");
    const text = el("div");
    text.append(el("strong", name), el("small", detail, "muted"));
    item.append(el("strong", hour), text);
    agenda.append(item);
  }
  if (!entries.length) agenda.append(el("p", "วันนี้ยังไม่มีรายการ", "muted"));
  if (next) {
    const upcoming = el("div", "", "agenda-heading");
    upcoming.append(el("h3", "กำลังจะมาถึง"), widgetRow("calendar", next.title, shortDate.format(next.start)));
    agenda.append(upcoming);
  }
  const side = el("aside", "", "overview-rail");
  const total = data.classes.reduce((count, slot) => count + slot.end - slot.start, 0);
  const tasks = weekTasks(data.tasks, selected);
  const progress = el("div", "", "progress-display");
  renderProgress(progress, tasks);
  side.append(el("h2", "สัปดาห์นี้"), el("p", `${data.classes.length} คาบ · ${(total / 60).toFixed(1)} ชั่วโมง`, "muted"),
    el("h3", "งานครบกำหนดสัปดาห์นี้"), progress, el("h3", "งานที่ต้องติดตาม"));
  for (const task of tasks.filter(task => task.status !== "Done").slice(0, 3)) {
    side.append(widgetRow("tasks", task.title, shortDate.format(localDate(task.due))));
  }
  container.replaceChildren(agenda, side);
}

export function samplePlanner(today = new Date()) {
  const names = [
    ["301493","IE Project 2",1], ["301494","Simulation",5], ["301495","Quality Engineering",6],
    ["301492","Production Planning",1], ["301421","Industrial Engineering Lab",7],
    ["MATH 260","Engineering Mathematics III",6], ["301233","Data Analytics for IE",2],
    ["GEN 101","Technology and Society",1], ["IE 315","Quality Engineering",5]
  ];
  const subjects = names.map(([code, name, color], i) => ({ id: String(i), code, name, color }));
  const slots = [
    [0,0,480,710,"EN 505"],[0,1,780,890,"EN 405"],[0,2,900,1070,"EN 407"],
    [1,3,540,710,"EN 408"],[1,4,780,960,"Lab 2","LAB"],[2,5,540,710,"SC 301"],[2,6,840,1010,"EN 406"],
    [3,1,540,710,"EN 405","LAB"],[3,0,780,950,"EN 410"],[4,7,540,710,"HU 201"],[4,8,840,1010,"EN 407","LAB"]
  ];
  const classes = slots.map(([weekday, subjectID, start, end, room, kind = "LEC"]) =>
    ({ weekday, subjectID: String(subjectID), start, end, room, kind }));
  const tasks = ["รายงาน Simulation","Homework 3","Lab Report 2","ทบทวนสไลด์สัปดาห์นี้","ส่งหัวข้อโปรเจกต์"].map((title, i) => {
    const due = addDays(weekStart(today), [4, 5, 6, 4, 3][i]);
    due.setHours(i === 0 ? 17 : 23, i === 0 ? 0 : 59, 0, 0);
    return { id: String(i), title, due: (due.getTime() - 978307200000) / 1000,
      priority: ["High","Medium","Low","Medium","Medium"][i], status: i >= 3 ? "Done" : "To do", subtasks: [] };
  });
  return { subjects, classes, tasks, events: [] };
}

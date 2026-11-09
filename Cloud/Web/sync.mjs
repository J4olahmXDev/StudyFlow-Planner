const utf8 = new TextEncoder();
const text = new TextDecoder();
const base64 = bytes => btoa(Array.from(bytes, byte => String.fromCharCode(byte)).join(""));
const unbase64 = value => Uint8Array.from(atob(value), character => character.charCodeAt(0));
const hex = bytes => Array.from(bytes, byte => byte.toString(16).padStart(2, "0")).join("");

export function decodeCode(code) {
  const compact = code.replace(/[-\s]/g, "");
  if (!/^[a-f0-9]{32}$/i.test(compact)) throw Error("โค้ดต้องมีเลขหรือ A–F รวม 32 ตัว");
  return Uint8Array.from(compact.match(/../g), pair => parseInt(pair, 16));
}

export async function workspaceFor(code) {
  const bytes = decodeCode(code);
  async function digest(domain) {
    const message = new Uint8Array([...utf8.encode(domain), ...bytes]);
    return new Uint8Array(await crypto.subtle.digest("SHA-256", message));
  }
  const locator = hex(await digest("StudyFlow/workspace/v1:"));
  const key = await crypto.subtle.importKey("raw", await digest("StudyFlow/encryption/v1:"), "AES-GCM", false, ["encrypt", "decrypt"]);
  return { locator, key };
}

export async function shareWorkspace(code, password) {
  const short = code.trim().toUpperCase();
  const secret = password.replace(/[-\s]/g, "").toUpperCase();
  if (!/^[2-9A-HJ-NP-Z]{6}$/.test(short) || !/^[2-9A-HJ-NP-Z]{12}$/.test(secret)) {
    throw Error("กรอกโค้ดแชร์ 6 ตัวและรหัส 12 ตัว");
  }
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", utf8.encode(`StudyFlow/share/v1:${short}:${secret}`)));
  return workspaceFor(hex(bytes.slice(0, 16)));
}

export async function decrypt(ciphertext, workspace) {
  const combined = unbase64(ciphertext);
  const clear = await crypto.subtle.decrypt({ name: "AES-GCM", iv: combined.slice(0, 12) }, workspace.key, combined.slice(12));
  return JSON.parse(text.decode(clear));
}

export async function unpack(ciphertext, workspace) {
  const replica = await decrypt(ciphertext, workspace);
  if (!Number.isSafeInteger(replica.clock) || replica.clock < 0 || !replica.records || !replica.deviceID) {
    throw Error("ข้อมูลซิงก์ไม่ถูกต้อง");
  }
  return replica;
}

export async function pack(replica, workspace) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const sealed = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, workspace.key, utf8.encode(JSON.stringify(replica)));
  return base64(new Uint8Array([...iv, ...new Uint8Array(sealed)]));
}

export function cloudClient(projectURL, publishableKey, fetcher = fetch) {
  if (!projectURL || !publishableKey) throw Error("ยังไม่ได้ตั้งค่าคลาวด์ StudyFlow");
  const project = new URL(projectURL);
  if (project.protocol !== "https:" || !project.hostname.endsWith(".supabase.co")
      || project.username || project.password || project.port || project.search || project.hash || project.pathname !== "/"
      || !/^sb_publishable_\S+$/.test(publishableKey)) throw Error("ยังไม่ได้ตั้งค่าคลาวด์ StudyFlow");
  async function rpc(name, body) {
    const response = await fetcher(new URL(`/rest/v1/rpc/${name}`, project), {
      method: "POST", headers: { apikey: publishableKey, "Content-Type": "application/json" },
      body: JSON.stringify(body), signal: AbortSignal.timeout?.(8000), credentials: "omit", redirect: "error", cache: "no-store"
    });
    if (!response.ok) throw Error("ติดต่อคลาวด์ไม่สำเร็จ");
    return response.json();
  }
  return {
    async readShare(workspace) {
      const rows = await rpc("studyflow_share_read", { p_workspace: workspace.locator });
      if (!rows.length) return null;
      const payload = await decrypt(rows[0].ciphertext, workspace);
      if (!payload.selection || ![payload.subjects, payload.classes, payload.tasks, payload.events].every(Array.isArray)) {
        throw Error("ชุดแชร์ใช้รูปแบบที่อ่านไม่ได้");
      }
      return payload;
    },
    async read(workspace) {
      const rows = await rpc("studyflow_read", { p_workspace: workspace.locator });
      if (!rows.length) {
        const error = Error("ไม่พบชุดข้อมูลของโค้ดนี้");
        error.code = "workspace-missing";
        throw error;
      }
      return { revision: rows[0].revision, replica: await unpack(rows[0].ciphertext, workspace) };
    },
    async write(workspace, revision, replica) {
      return rpc("studyflow_write", {
        p_workspace: workspace.locator, p_expected: revision, p_ciphertext: await pack(replica, workspace)
      });
    }
  };
}

export function recordsOf(replica, type) {
  return Object.values(replica.records)
    .filter(record => record.entity === type && record.operation === "upsert")
    .map(record => JSON.parse(text.decode(unbase64(record.payload))));
}

export const legacyTermID = "00000000-0000-0000-0000-000000000001";

export function plannerTerm(replica, termID) {
  const allSubjects = recordsOf(replica, "subject");
  const knownIDs = new Set(allSubjects.map(subject => subject.id));
  const belongs = value => (value.termID || legacyTermID) === termID;
  const subjects = allSubjects.filter(belongs);
  const subjectIDs = new Set(subjects.map(subject => subject.id));
  return {
    subjects,
    classes: recordsOf(replica, "class").filter(slot =>
      subjectIDs.has(slot.subjectID) || (termID === legacyTermID && !knownIDs.has(slot.subjectID))),
    tasks: recordsOf(replica, "task").filter(belongs),
    events: recordsOf(replica, "event").filter(belongs)
  };
}

export const swiftDate = date => (date.getTime() - 978307200000) / 1000;
export const localDate = date => new Date(date * 1000 + 978307200000);
export const uuid = () => crypto.randomUUID().toUpperCase();

export function saveRecord(replica, entity, value) {
  const id = value.id.toUpperCase();
  const key = `${entity}:${id}`;
  const previous = replica.records[key];
  if (previous?.operation === "delete") throw Error("งานนี้ถูกลบจากอีกเครื่องแล้ว");
  const version = ++replica.clock;
  replica.records[key] = {
    id: uuid(), entity, entityID: id, operation: "upsert",
    baseVersion: previous?.version ?? 0, version, changedAt: swiftDate(new Date()),
    payload: base64(utf8.encode(JSON.stringify({ ...value, id })))
  };
  return replica;
}

export const saveTask = (replica, task) => saveRecord(replica, "task", task);

export function newTask(title, due, subjectID, termID = legacyTermID) {
  return { id: uuid(), title, assigned: swiftDate(new Date()), due: swiftDate(due),
    subjectID: subjectID || undefined, termID: termID === legacyTermID ? undefined : termID, priority: "Medium", status: "To do", subtasks: [], notes: "" };
}

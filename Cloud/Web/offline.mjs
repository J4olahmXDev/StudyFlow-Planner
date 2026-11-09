import { decrypt, pack } from "./sync.mjs";

export function openOfflineStore() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open("studyflow-offline", 1);
    request.onupgradeneeded = () => request.result.createObjectStore("workspaces");
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const db = request.result;
      db.onversionchange = () => db.close();
      resolve({
        read(locator) {
          return new Promise((resolve, reject) => {
            const read = db.transaction("workspaces").objectStore("workspaces").get(locator);
            read.onsuccess = () => resolve(read.result);
            read.onerror = () => reject(read.error);
          });
        },
        replace(locator, previous, next) {
          return new Promise((resolve, reject) => {
            const tx = db.transaction("workspaces", "readwrite");
            const table = tx.objectStore("workspaces");
            const read = table.get(locator);
            let matched = false;
            read.onsuccess = () => {
              matched = read.result === previous;
              if (matched) table.put(next, locator);
            };
            tx.oncomplete = () => resolve(matched);
            tx.onabort = () => reject(tx.error);
          });
        },
      });
    };
  });
}

function wins(record, current) {
  if (!current) return true;
  if (record.operation !== current.operation) return record.operation === "delete";
  if (record.version !== current.version) return record.version > current.version;
  if (record.version === 0 && record.changedAt !== current.changedAt) return record.changedAt > current.changedAt;
  return record.id.toUpperCase() > current.id.toUpperCase();
}

export async function devicePlanner(store) {
  const locator = "local-planner";
  const keyID = "local-planner-key";
  let key = await store.read(keyID);
  if (!key) {
    key = await crypto.subtle.generateKey({ name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
    if (!await store.replace(keyID, undefined, key)) key = await store.read(keyID);
  }
  const workspace = { locator, key };
  const empty = { replica: { clock: 0, deviceID: crypto.randomUUID().toUpperCase(), records: {} }, pending: {} };
  if (!await store.read(locator)) await store.replace(locator, undefined, await pack(empty, workspace));
  return privatePlanner(workspace, null, store);
}

export function privatePlanner(workspace, cloud, store) {
  const read = () => store.read(workspace.locator);
  const replace = async (previous, state) =>
    store.replace(workspace.locator, previous, await pack(state, workspace));
  return {
    async local() {
      const previous = await read();
      return previous ? decrypt(previous, workspace) : null;
    },
    async edit(change) {
      for (let attempt = 0; attempt < 4; attempt++) {
        const previous = await read();
        if (!previous) throw Error("เชื่อมอินเทอร์เน็ตเพื่อดาวน์โหลดข้อมูลก่อน");
        const state = await decrypt(previous, workspace);
        const before = { ...state.replica.records };
        change(state.replica);
        for (const [key, record] of Object.entries(state.replica.records)) {
          if (cloud && before[key]?.id !== record.id) state.pending[key] = record;
        }
        if (await replace(previous, state)) return state;
      }
      throw Error("มีการแก้พร้อมกัน ลองบันทึกอีกครั้ง");
    },
    async sync() {
      for (let attempt = 0; attempt < 4; attempt++) {
        const previous = await read();
        const cached = previous && await decrypt(previous, workspace);
        const { revision, replica } = await cloud.read(workspace);
        let changed = false;
        let conflicts = 0;
        for (const [key, record] of Object.entries(cached?.pending ?? {})) {
          const current = replica.records[key];
          if (record.id === current?.id) continue;
          if (wins(record, current)) {
            replica.records[key] = record;
            replica.clock = Math.max(replica.clock, record.version);
            changed = true;
          } else {
            conflicts++;
          }
        }
        if (changed && !await cloud.write(workspace, revision, replica)) continue;
        const state = { replica, pending: {}, conflicts };
        if (await replace(previous, state)) return state;
      }
      throw Error("มีการแก้พร้อมกัน จะลองซิงก์ใหม่อัตโนมัติ");
    },
  };
}

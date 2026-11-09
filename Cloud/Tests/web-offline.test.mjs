import assert from "node:assert/strict";
import test from "node:test";
import { privatePlanner } from "../Web/offline.mjs";
import { newTask, recordsOf, saveTask, workspaceFor } from "../Web/sync.mjs";

async function harness() {
  const code = "6e".repeat(16);
  const workspace = await workspaceFor(code);
  let ciphertext, revision = 0;
  let remote = { clock: 0, deviceID: crypto.randomUUID(), records: {} };
  const store = {
    async read() { return ciphertext; },
    async replace(locator, previous, next) {
      if (previous !== ciphertext) return false;
      ciphertext = next;
      return true;
    }
  };
  const cloud = {
    online: true, rejectNext: false, loseResponse: false,
    async read() {
      if (!this.online) throw Error("offline");
      return { revision, replica: structuredClone(remote) };
    },
    async write(workspace, expected, replica) {
      if (this.rejectNext) { this.rejectNext = false; return false; }
      assert.equal(expected, revision);
      remote = structuredClone(replica);
      revision++;
      if (this.loseResponse) { this.loseResponse = false; throw Error("connection lost"); }
      return true;
    }
  };
  return {
    cloud, store, workspace, client: () => privatePlanner(workspace, cloud, store),
    external(change) { change(remote); revision++; },
    remote: () => remote,
  };
}

const task = title => newTask(title, new Date("2027-01-31T13:00:00Z"));

test("encrypted offline edit survives reopening and merges alongside another device", async () => {
  const env = await harness();
  const planner = env.client();
  await planner.sync();
  env.cloud.online = false;
  const local = task("Study offline");
  await planner.edit(replica => saveTask(replica, local));
  assert.doesNotMatch(await env.store.read(env.workspace.locator), /Study offline/);
  const reopened = env.client();
  assert.equal(recordsOf((await reopened.local()).replica, "task")[0].title, local.title);
  await assert.rejects(reopened.sync(), /offline/);
  env.external(replica => saveTask(replica, task("From Mac")));
  env.cloud.online = true;
  env.cloud.rejectNext = true;
  const state = await reopened.sync();
  assert.deepEqual(state.pending, {});
  assert.deepEqual(recordsOf(env.remote(), "task").map(value => value.title).sort(), ["From Mac", "Study offline"]);
});

test("remote delete beats an offline task edit", async () => {
  const env = await harness();
  const planner = env.client();
  const original = task("Will be deleted");
  env.external(replica => saveTask(replica, original));
  await planner.sync();
  await planner.edit(replica => saveTask(replica, { ...original, status: "Done" }));
  env.external(replica => {
    const key = "task:" + original.id;
    replica.records[key] = { ...replica.records[key], id: crypto.randomUUID(), operation: "delete" };
  });
  const result = await planner.sync();
  assert.equal(result.conflicts, 1);
  assert.deepEqual(recordsOf(result.replica, "task"), []);
  assert.deepEqual(result.pending, {});
});

test("simultaneous local edits and a lost cloud response preserve both tasks exactly once", async () => {
  const env = await harness();
  await env.client().sync();
  await Promise.all(["One", "Two"].map(title => env.client().edit(replica => saveTask(replica, task(title)))));
  env.cloud.loseResponse = true;
  await assert.rejects(env.client().sync(), /connection lost/);
  assert.equal(Object.keys((await env.client().local()).pending).length, 2);
  const result = await env.client().sync();
  assert.equal(result.conflicts, 0);
  assert.deepEqual(result.pending, {});
  assert.deepEqual(recordsOf(result.replica, "task").map(value => value.title).sort(), ["One", "Two"]);
});

test("new local planner persists a term and task without a code or network", async () => {
  const { devicePlanner } = await import("../Web/offline.mjs");
  const { saveRecord } = await import("../Web/sync.mjs");
  const entries = new Map();
  const store = {
    async read(key) { return entries.get(key); },
    async replace(key, previous, next) {
      if (entries.get(key) !== previous) return false;
      entries.set(key, next);
      return true;
    }
  };
  const planner = await devicePlanner(store);
  const id = crypto.randomUUID().toUpperCase();
  await planner.edit(replica => saveRecord(replica, "term", { id, name: "New term" }));
  await planner.edit(replica => saveTask(replica, { ...task("Local first"), termID: id }));
  const reopened = await devicePlanner(store);
  const state = await reopened.local();
  assert.equal(recordsOf(state.replica, "term")[0].name, "New term");
  assert.equal(recordsOf(state.replica, "task")[0].termID, id);
  assert.deepEqual(state.pending, {});
});

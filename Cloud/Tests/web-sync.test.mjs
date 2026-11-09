import test from "node:test";
import assert from "node:assert/strict";
import { cloudClient, legacyTermID, newTask, pack, plannerTerm, recordsOf, saveTask, unpack, workspaceFor } from "../Web/sync.mjs";

test("shared format and revision checks allow a browser to write a Mac-compatible task", async () => {
  const workspace = await workspaceFor("0011-2233-4455-6677-8899-AABB-CCDD-EEFF");
  assert.equal(workspace.locator, "01eeb89cedcd96406c131ffe10027e7f90f42e7e8eff563a038b1095ac094604");
  let stored = { revision: 1, ciphertext: await pack({
    deviceID: "BB6F56BD-8BC4-4DBD-AFAE-0D83DDC92495", clock: 0, records: {}
  }, workspace) };
  const client = cloudClient("https://studyflow-test.supabase.co", "sb_publishable_test", async (url, request) => {
    const body = JSON.parse(request.body);
    assert.equal(body.p_workspace, workspace.locator);
    if (url.pathname.endsWith("studyflow_read")) return Response.json([stored]);
    if (body.p_expected !== stored.revision) return Response.json(false);
    stored = { revision: stored.revision + 1, ciphertext: body.p_ciphertext };
    return Response.json(true);
  });
  const a = await client.read(workspace);
  const b = await client.read(workspace);
  const task = newTask("QA task", new Date(Date.now() + 3600000), "");
  assert.equal(await client.write(workspace, a.revision, saveTask(a.replica, task)), true);
  assert.equal(await client.write(workspace, b.revision, b.replica), false);
  const latest = await client.read(workspace);
  assert.deepEqual(recordsOf(latest.replica, "task"), [JSON.parse(JSON.stringify(task))]);
  assert.ok(!stored.ciphertext.includes("QA task"));
  const wrong = await workspaceFor("0000-0000-0000-0000-0000-0000-0000-0000");
  await assert.rejects(unpack(stored.ciphertext, wrong));
});

test("scoped shares use the password to read their own endpoint without a write credential", async () => {
  const { shareWorkspace } = await import("../Web/sync.mjs");
  const workspace = await shareWorkspace("abcd23", "efgh-jklm-np45");
  const selection = { timetable: false, tasks: true, events: false };
  const payload = { selection, subjects: [], classes: [], tasks: [], events: [] };
  const ciphertext = await pack(payload, workspace);
  const client = cloudClient("https://studyflow-test.supabase.co", "sb_publishable_test", async (url, request) => {
    assert.equal(url.pathname, "/rest/v1/rpc/studyflow_share_read");
    const body = JSON.parse(request.body);
    assert.deepEqual(Object.keys(body), ["p_workspace"]);
    return Response.json(body.p_workspace === workspace.locator ? [{ ciphertext }] : []);
  });
  assert.deepEqual(await client.readShare(workspace), payload);
  assert.equal(await client.readShare(await shareWorkspace("ABCD23", "EFGHJKLMNP46")), null);
});


test("web-created tasks stay in the selected term and legacy tasks stay separate", () => {
  const termID = "FA181A4A-B70F-45F0-933A-37DB71773174";
  const replica = { clock: 0, records: {} };
  const due = new Date(Date.now() + 3600000);
  const first = newTask("Legacy task", due, "");
  const second = newTask("New term task", due, "", termID);
  saveTask(replica, first);
  saveTask(replica, second);
  assert.deepEqual(plannerTerm(replica, legacyTermID).tasks.map(task => task.id), [first.id]);
  assert.deepEqual(plannerTerm(replica, termID).tasks.map(task => task.id), [second.id]);
});

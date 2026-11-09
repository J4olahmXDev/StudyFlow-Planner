const shellPrefix = "studyflow-shell-";
const shellName = shellPrefix + "2026-11-09.15";
const shellRoot = self.registration.scope;
const shellPaths = [
  "./index.html", "./app.mjs", "./planner-ui.mjs", "./sync.mjs", "./offline.mjs", "./config.mjs",
  "./style.css", "./NotoSansThai-Variable.ttf", "./folio.svg", "./manifest.webmanifest", "./icon-192.png",
  "./icon-512.png", "./widget-card.json", "./widget-preview.png",
];
const shellURLs = new Set(shellPaths.map(path => new URL(path, shellRoot).href));
const indexURL = new URL("./index.html", shellRoot).href;

self.addEventListener("install", event => {
  event.waitUntil(caches.open(shellName).then(cache =>
    cache.addAll([...shellURLs].map(url => new Request(url, { cache: "reload" })))
  ).then(() => self.skipWaiting()));
});

self.addEventListener("activate", event => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith(shellPrefix) && name !== shellName) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", event => {
  if (event.request.method !== "GET") return;
  const url = new URL(event.request.url);
  url.search = "";
  const isHome = event.request.mode === "navigate" && (url.href === shellRoot || url.href === indexURL);
  if (!isHome && !shellURLs.has(url.href)) return;
  event.respondWith((async () => {
    const cache = await caches.open(shellName);
    return await cache.match(isHome ? indexURL : url.href) ?? fetch(event.request);
  })());
});

const tag = "studyflow-next-up";
const cacheName = "studyflow-widget";
const snapshotURL = new URL("./widget-snapshot", self.registration.scope).href;
const templateURL = new URL("./widget-card.json", self.registration.scope).href;

let updates = Promise.resolve();
function enqueue(event, operation) {
  updates = updates.catch(() => {}).then(operation);
  event.waitUntil(updates);
}

async function renderWidget(cache) {
  if (!await self.widgets.getByTag(tag)) return;
  const stored = await (await cache.match(snapshotURL))?.json();
  const data = stored?.expiresAt > Date.now() ? stored : {
    term: "StudyFlow", classTitle: "เปิด StudyFlow เพื่ออัปเดต", taskTitle: "", classDetail: "", taskDetail: "",
  };
  const response = await (await caches.open(shellName)).match(templateURL) ?? await fetch(templateURL);
  if (!response.ok) return;
  await self.widgets.updateByTag(tag, {
    template: await response.text(),
    data: JSON.stringify({ term: data.term || "StudyFlow", classTitle: data.classTitle ?? data.classLine, taskTitle: data.taskTitle ?? data.taskLine, classDetail: data.classDetail || "", taskDetail: data.taskDetail || "", appURL: self.registration.scope }),
  });
}

self.addEventListener("message", event => {
  if (event.data?.type !== "studyflow-widget" || !self.widgets) return;
  enqueue(event, async () => {
    const cache = await caches.open(cacheName);
    const data = event.data.data;
    if (data) await cache.put(snapshotURL, new Response(JSON.stringify(data)));
    else await cache.delete(snapshotURL);
    await renderWidget(cache);
  });
});

for (const name of ["widgetinstall", "widgetresume"]) {
  self.addEventListener(name, event => {
    if (event.widget?.definition.tag === tag) enqueue(event, async () => renderWidget(await caches.open(cacheName)));
  });
}

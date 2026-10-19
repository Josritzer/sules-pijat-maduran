/* SL Relax Admin Web Push service worker. */
self.addEventListener("push", event => {
  let payload = {};
  try { payload = event.data ? event.data.json() : {}; } catch (_) {}
  const title = typeof payload.title === "string" ? payload.title : "Booking baru — SL Relax";
  const options = {
    body: typeof payload.body === "string" ? payload.body : "Ada booking baru yang perlu diperiksa.",
    icon: "/icons/pwa-192.png",
    badge: "/icons/pwa-192.png",
    tag: typeof payload.tag === "string" ? payload.tag : "sl-relax-booking",
    data: { url: typeof payload.url === "string" ? payload.url : "/?admin=1" },
    renotify: true
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", event => {
  event.notification.close();
  const raw = event.notification && event.notification.data && event.notification.data.url;
  let target = "/?admin=1";
  try {
    const candidate = new URL(typeof raw === "string" ? raw : target, self.location.origin);
    if (candidate.origin === self.location.origin) target = candidate.pathname + candidate.search + candidate.hash;
  } catch (_) {}
  event.waitUntil((async () => {
    const clientsList = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const client of clientsList) {
      if (new URL(client.url).origin === self.location.origin) {
        await client.navigate(target);
        return client.focus();
      }
    }
    return self.clients.openWindow(target);
  })());
});

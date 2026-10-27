// Ghidul echipei Madame Magnifique · service worker: doar notificările push.
// (Nu păstrează pagini în cache: ghidul se citește mereu proaspăt din Supabase.)
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));

self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (x) { d = { body: e.data ? e.data.text() : '' }; }
  e.waitUntil(self.registration.showNotification(d.title || 'Madame Magnifique', {
    body: d.body || '',
    tag: d.tag || undefined,
    data: { url: d.url || '#/' },
    icon: 'assets/img/icon-192.png',
    badge: 'assets/img/badge-96.png',
  }));
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = new URL(e.notification.data && e.notification.data.url || '#/', self.registration.scope).href;
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(ferestre => {
    for (const f of ferestre) {
      if (f.url.startsWith(self.registration.scope) && 'focus' in f) {
        if ('navigate' in f) f.navigate(url).catch(() => {});
        return f.focus();
      }
    }
    return self.clients.openWindow(url);
  }));
});

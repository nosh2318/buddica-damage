// BUDDICA 車両チェック Service Worker v1
const CACHE = 'buddica-damage-v1';

self.addEventListener('install', e => {
  // キャッシュはしない（常に最新を取得）
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  // 古いキャッシュを全削除
  e.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.map(k => caches.delete(k)))
  ));
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  // supabase は素通し
  if (e.request.url.includes('supabase.co')) return;
  // 常にネットワークから取得（キャッシュ一切使わない）
  e.respondWith(
    fetch(e.request, { cache: 'no-store' }).catch(() => {
      return new Response('offline', { status: 503 });
    })
  );
});

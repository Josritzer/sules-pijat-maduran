// Cek otomatis bookingpijat.com dengan Playwright
// Cara pakai (sekali pasang):
//   npm install playwright
//   npx playwright install chromium
// Jalankan:
//   node cek-bookingpijat.js

const { chromium } = require('playwright');

const URL = 'https://bookingpijat.com';

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } }); // ukuran HP

  const errorKonsol = [];
  const requestGagal = [];
  page.on('console', (m) => { if (m.type() === 'error') errorKonsol.push(m.text()); });
  page.on('requestfailed', (r) => requestGagal.push(`${r.url()} (${r.failure()?.errorText})`));

  const mulai = Date.now();
  const respon = await page.goto(URL, { waitUntil: 'networkidle', timeout: 60000 });
  const detik = ((Date.now() - mulai) / 1000).toFixed(1);

  const status = respon ? respon.status() : 'tidak ada respon';
  const judul = await page.title();

  // Kumpulkan semua link internal lalu cek satu per satu
  const links = await page.$$eval('a[href]', (as) => [...new Set(as.map((a) => a.href))]);
  const internal = links.filter((l) => l.startsWith(URL));
  const linkRusak = [];
  for (const l of internal) {
    try {
      const r = await page.request.get(l);
      if (r.status() >= 400) linkRusak.push(`${l} -> ${r.status()}`);
    } catch (e) {
      linkRusak.push(`${l} -> gagal dibuka`);
    }
  }

  await page.screenshot({ path: 'hasil-beranda.png', fullPage: true });
  await browser.close();

  const laporan = [
    `Waktu: ${new Date().toLocaleString('id-ID', { timeZone: 'Asia/Jakarta' })}`,
    `Status halaman: ${status}`,
    `Judul: ${judul}`,
    `Waktu muat: ${detik} detik`,
    `Link internal dicek: ${internal.length}, rusak: ${linkRusak.length}`,
    ...linkRusak.map((x) => `  - ${x}`),
    `Error konsol: ${errorKonsol.length}`,
    ...errorKonsol.slice(0, 10).map((x) => `  - ${x}`),
    `Request gagal: ${requestGagal.length}`,
    ...requestGagal.slice(0, 10).map((x) => `  - ${x}`),
    `Screenshot: hasil-beranda.png`,
  ].join('\n');

  console.log(laporan);
  require('fs').writeFileSync('laporan.txt', laporan);
  process.exit(status === 200 && linkRusak.length === 0 ? 0 : 1);
})();

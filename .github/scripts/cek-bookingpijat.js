// Cek otomatis bookingpijat.com dengan Playwright
const { chromium } = require('playwright');
const fs = require('node:fs');

const URL_UTAMA = 'https://bookingpijat.com';
const HOST_VALID = new Set(['bookingpijat.com', 'www.bookingpijat.com']);

(async () => {
  const mulai = Date.now();
  const errorKonsol = [];
  const requestGagal = [];
  const linkRusak = [];
  let browser;
  let status = 'tidak ada respons';
  let judul = '(belum tersedia)';
  let jumlahLink = 0;
  let errorFatal = '';

  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });

    page.on('console', (msg) => {
      if (msg.type() === 'error') errorKonsol.push(msg.text());
    });
    page.on('requestfailed', (req) => {
      requestGagal.push(`${req.url()} (${req.failure()?.errorText || 'request gagal'})`);
    });

    const response = await page.goto(URL_UTAMA, { waitUntil: 'domcontentloaded', timeout: 60000 });
    status = response ? response.status() : 'tidak ada respons';
    await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
    judul = await page.title();

    const pageUrl = new URL(page.url());
    if (!HOST_VALID.has(pageUrl.hostname)) {
      throw new Error(`Situs dialihkan ke host yang tidak diizinkan: ${pageUrl.hostname}`);
    }

    const links = await page.$$eval('a[href]', (as) =>
      [...new Set(as.map((a) => a.href))]
    );
    const internal = links.filter((raw) => {
      try {
        const parsed = new URL(raw);
        return ['http:', 'https:'].includes(parsed.protocol) && HOST_VALID.has(parsed.hostname);
      } catch {
        return false;
      }
    });
    jumlahLink = internal.length;

    for (const link of internal) {
      try {
        const responseLink = await page.request.get(link, { timeout: 15000, maxRedirects: 5 });
        if (responseLink.status() >= 400) linkRusak.push(`${link} -> HTTP ${responseLink.status()}`);
      } catch (error) {
        linkRusak.push(`${link} -> ${error.message}`);
      }
    }

    await page.screenshot({ path: 'hasil-beranda.png', fullPage: true }).catch((error) => {
      errorFatal = `Screenshot gagal: ${error.message}`;
    });
  } catch (error) {
    errorFatal = error.message;
  } finally {
    if (browser) await browser.close().catch(() => {});
  }

  const detik = ((Date.now() - mulai) / 1000).toFixed(1);
  const laporan = [
    `Waktu: ${new Date().toLocaleString('id-ID', { timeZone: 'Asia/Jakarta' })}`,
    `Status halaman: ${status}`,
    `Judul: ${judul}`,
    `Waktu pemeriksaan: ${detik} detik`,
    `Link internal diperiksa: ${jumlahLink}, rusak: ${linkRusak.length}`,
    ...linkRusak.map((item) => `  - ${item}`),
    `Error konsol: ${errorKonsol.length}`,
    ...errorKonsol.slice(0, 10).map((item) => `  - ${item}`),
    `Request gagal: ${requestGagal.length}`,
    ...requestGagal.slice(0, 10).map((item) => `  - ${item}`),
    ...(errorFatal ? [`Kesalahan pemeriksaan: ${errorFatal}`] : []),
    'Screenshot: hasil-beranda.png (jika berhasil dibuat)',
  ].join('\\n');

  console.log(laporan);
  fs.writeFileSync('laporan.txt', laporan);

  const statusOK = status === 200;
  const gagal = !statusOK || linkRusak.length > 0 || errorKonsol.length > 0 ||
    requestGagal.length > 0 || Boolean(errorFatal);
  process.exitCode = gagal ? 1 : 0;
})();

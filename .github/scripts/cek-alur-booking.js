// Pemeriksaan terpadu SL Relax: smoke test + prasyarat alur bisnis.
// Tidak membuat booking, tidak menerima/menolak booking, dan tidak mengirim email
// tanpa konfigurasi eksplisit untuk akun uji. Status BELUM DIUJI bukan dianggap lulus.
const { chromium } = require('playwright');
const fs = require('node:fs');

const BASE_URL = 'https://bookingpijat.com';
const SUPABASE_URL = 'https://tzupkourtcmqemymszgt.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_-0r7zhfsw4-3UPh8ReG6Ag_dwOQQ2K9';
const results = [];
const add = (name, status, detail) => results.push({ name, status, detail });
const timeout = (ms) => new Promise(resolve => setTimeout(resolve, ms));

(async () => {
  let browser;
  const consoleErrors = [];
  const failedRequests = [];
  const brokenLinks = [];
  let pageStatus = 'tidak ada respons';
  let title = '(belum tersedia)';
  let duration = 0;

  try {
    const started = Date.now();
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    page.on('console', msg => { if (msg.type() === 'error') consoleErrors.push(msg.text()); });
    page.on('requestfailed', req => failedRequests.push(`${req.url()} (${req.failure()?.errorText || 'request gagal'})`));

    const response = await page.goto(BASE_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
    pageStatus = response ? response.status() : 'tidak ada respons';
    await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
    title = await page.title();
    const currentHost = new URL(page.url()).hostname;
    if (pageStatus === 200 && ['bookingpijat.com', 'www.bookingpijat.com'].includes(currentHost)) {
      add('Website utama', 'LULUS', `HTTP ${pageStatus}; ${title}`);
    } else add('Website utama', 'GAGAL', `HTTP ${pageStatus}; host ${currentHost}`);

    const links = await page.$$eval('a[href]', as => [...new Set(as.map(a => a.href))]);
    const internal = links.filter(raw => {
      try { const u = new URL(raw); return ['http:', 'https:'].includes(u.protocol) && ['bookingpijat.com', 'www.bookingpijat.com'].includes(u.hostname); }
      catch { return false; }
    });
    for (const link of internal) {
      try {
        const r = await page.request.get(link, { timeout: 15000, maxRedirects: 5 });
        if (r.status() >= 400) brokenLinks.push(`${link} -> HTTP ${r.status()}`);
      } catch (e) { brokenLinks.push(`${link} -> ${e.message}`); }
    }
    add('Tautan internal', brokenLinks.length ? 'GAGAL' : 'LULUS', `${internal.length} diperiksa; ${brokenLinks.length} rusak`);

    const bodyText = await page.locator('body').innerText().catch(() => '');

    // Pemeriksaan UI publik yang aman: hanya membaca halaman, tanpa membuat booking.
    const publicSections = ['#beranda', '#katalog', '#faq', '#pesanan', '#booking-app'];
    const missingSections = [];
    for (const selector of publicSections) {
      if (await page.locator(selector).count() === 0) missingSections.push(selector);
    }
    add('Bagian utama website', missingSections.length ? 'GAGAL' : 'LULUS',
      missingSections.length ? `Bagian tidak ditemukan: ${missingSections.join(', ')}` : `${publicSections.length} bagian utama ditemukan.`);

    const packageCards = page.locator('.sules-catalog-public-card');
    const packageCount = await packageCards.count();
    const packageNames = await packageCards.locator('h3').allTextContents().catch(() => []);
    add('Katalog 5 paket', packageCount === 5 ? 'LULUS' : 'GAGAL',
      `Kartu paket ditemukan: ${packageCount}/5. Nama paket: ${packageNames.map(s => s.trim()).filter(Boolean).join(' | ') || 'tidak terbaca'}`);

    const packageButtons = page.locator('a.sules-public-package-button[href="#booking-app"]');
    const packageButtonCount = await packageButtons.count();
    add('Tombol pilih paket', packageButtonCount === 5 ? 'LULUS' : 'GAGAL',
      `Tombol pilih paket mengarah ke aplikasi booking: ${packageButtonCount}/5.`);

    const publicNav = page.locator('nav[aria-label="Navigasi publik"]');
    const navLabels = await publicNav.locator('a').allTextContents().catch(() => []);
    const invalidNavTargets = await publicNav.locator('a').evaluateAll(links => links
      .map(a => a.getAttribute('href'))
      .filter(href => !href || !document.querySelector(href)));
    add('Navigasi publik', navLabels.length >= 5 && invalidNavTargets.length === 0 ? 'LULUS' : 'GAGAL',
      `Tautan navigasi: ${navLabels.map(s => s.trim()).filter(Boolean).join(', ')}; target tidak ditemukan: ${invalidNavTargets.length}.`);

    const rootCount = await page.locator('#root').count();
    const rootChildren = rootCount ? await page.locator('#root').locator(':scope > *').count().catch(() => 0) : 0;
    add('Aplikasi React termuat', rootCount === 1 && rootChildren > 0 ? 'LULUS' : 'GAGAL',
      `Elemen #root: ${rootCount}; elemen aplikasi di dalam root: ${rootChildren}.`);

    const manifestCount = await page.locator('link[rel="manifest"]').count();
    const serviceWorkerScript = await page.locator('script').evaluateAll(scripts =>
      scripts.some(s => (s.textContent || '').includes('serviceWorker') || (s.src || '').includes('service-worker'))
    ).catch(() => false);
    add('Prasyarat PWA', manifestCount > 0 ? 'LULUS' : 'BELUM DIUJI',
      `Manifest terhubung: ${manifestCount > 0 ? 'ya' : 'tidak ditemukan'}; pendaftaran service worker terlihat di script inline/eksternal: ${serviceWorkerScript ? 'ya' : 'tidak terdeteksi'}.`);
    // Tahap 2: interaksi UI pelanggan yang aman. Tidak mengirim OTP dan tidak membuat booking.
    const accountShortcut = page.locator('a.site-app-shortcut[aria-label="Buka Akun"]');
    // Shortcut header disembunyikan pada viewport ponsel; DOM click tetap menguji
    // handler navigasi yang sama tanpa mengubah viewport atau data pengguna.
    if (await accountShortcut.count()) {
      await accountShortcut.evaluate(el => el.click()).catch(() => {});
      await page.waitForTimeout(700);
    }
    const customerRoot = page.locator('#root');
    // Tab Akun menampilkan ringkasan akun terlebih dahulu; masuk ke form OTP
    // lewat tombol Masuk. Exact match menghindari tombol "Masuk ke Admin".
    const loginButton = customerRoot.getByRole('button', { name: 'Masuk', exact: true });
    if (await loginButton.isVisible().catch(() => false)) {
      await loginButton.click().catch(() => {});
      await page.waitForTimeout(500);
    }
    const emailInput = customerRoot.locator('input[type="email"]');
    const sendOtpButton = customerRoot.getByRole('button', { name: /Kirim Kode OTP/ });
    await emailInput.waitFor({ state: 'visible', timeout: 5000 }).catch(() => {});
    const emailVisible = await emailInput.isVisible().catch(() => false);
    const sendOtpVisible = await sendOtpButton.isVisible().catch(() => false);
    add('Form akun pelanggan', emailVisible && sendOtpVisible ? 'LULUS' : 'GAGAL',
      `Kolom email terlihat: ${emailVisible ? 'ya' : 'tidak'}; tombol Kirim Kode OTP terlihat: ${sendOtpVisible ? 'ya' : 'tidak'}. Tombol tidak ditekan agar email tidak terkirim.`);

    const bookingWords = /buat booking|buat pesanan|pesan sekarang|pilih paket|jadwal booking/i.test(bodyText);
    add('Antarmuka booking', bookingWords ? 'LULUS' : 'BELUM DIUJI',
      bookingWords ? 'Teks alur booking ditemukan; booking nyata belum dibuat.' : 'Tombol/alur booking belum teridentifikasi dari tampilan awal; booking nyata tidak dibuat.');

    // Read-only availability probe of Supabase Auth configuration; does not sign in or mutate data.
    try {
      const authResponse = await page.request.get(`${SUPABASE_URL}/auth/v1/settings`, {
        headers: { apikey: SUPABASE_ANON_KEY }, timeout: 15000
      });
      if (authResponse.ok()) add('Koneksi Supabase Auth', 'LULUS', `Endpoint pengaturan Auth merespons HTTP ${authResponse.status()}.`);
      else add('Koneksi Supabase Auth', 'GAGAL', `Endpoint Auth merespons HTTP ${authResponse.status()}.`);
    } catch (e) { add('Koneksi Supabase Auth', 'GAGAL', e.message); }

    duration = ((Date.now() - started) / 1000).toFixed(1);
  } catch (e) {
    add('Pemeriksaan browser', 'GAGAL', e.message);
  } finally {
    if (browser) await browser.close().catch(() => {});
  }

  add('OTP email end-to-end', 'BELUM DIUJI', 'Memerlukan akses aman ke kotak masuk akun uji untuk mengambil OTP aktual; kode tidak boleh ditebak atau disimpan di repo.');
  add('Membuat booking baru', 'BELUM DIUJI', 'Memerlukan sesi akun uji yang sudah terverifikasi dan skenario data uji terkontrol.');
  add('Bentrok jadwal & penerimaan Admin', 'BELUM DIUJI', 'Memerlukan booking uji dan sesi Admin uji; tidak dijalankan pada data pelanggan.');
  add('GPS & biaya perjalanan', 'BELUM DIUJI', 'Memerlukan sesi pelanggan uji dan lokasi/tautan peta uji; belum mengubah atau membuat booking.');
  add('Notifikasi email', 'BELUM DIUJI', 'Tidak mengirim email dalam tes ini; perlu verifikasi terkontrol untuk email pelanggan dan Admin.');
  add('Supabase keseluruhan (DB/RPC/Edge/Realtime)', 'BELUM DIUJI', 'Tes ini hanya memeriksa endpoint Auth secara read-only, bukan seluruh tabel, RPC, Edge Functions, atau Realtime.');
  add('Pembayaran iPaymu', 'BELUM DIIMPLEMENTASIKAN', 'Integrasi iPaymu belum tersedia.');

  if (consoleErrors.length) add('Error konsol browser', 'GAGAL', `${consoleErrors.length} error; ${consoleErrors.slice(0, 5).join(' | ')}`);
  else add('Error konsol browser', 'LULUS', '0 error konsol yang terdeteksi.');
  if (failedRequests.length) add('Request browser gagal', 'GAGAL', `${failedRequests.length}; ${failedRequests.slice(0, 5).join(' | ')}`);
  else add('Request browser gagal', 'LULUS', '0 request gagal yang terdeteksi.');

  const lines = [
    `Waktu: ${new Date().toLocaleString('id-ID', { timeZone: 'Asia/Jakarta' })}`,
    `Waktu pemeriksaan: ${duration} detik`,
    '',
    ...results.map(r => `[${r.status}] ${r.name}\n  ${r.detail}`),
    '',
    `Ringkasan: ${results.filter(r => r.status === 'LULUS').length} LULUS; ${results.filter(r => r.status === 'GAGAL').length} GAGAL; ${results.filter(r => r.status.startsWith('BELUM')).length} BELUM DIUJI/DIIMPLEMENTASIKAN.`
  ];
  const report = lines.join('\n');
  console.log(report);
  fs.writeFileSync('laporan-alur-booking.txt', report);
  fs.writeFileSync('hasil-alur-booking.json', JSON.stringify({ checkedAt: new Date().toISOString(), results }, null, 2));
  // This supplementary suite should not hide failures in the existing strict smoke test.
  // Its explicit blockers remain visible in the report without falsely claiming full E2E coverage.
})();

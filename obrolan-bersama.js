(function () {
  "use strict";
  if (window.__slRelaxChatInstalled) return;
  window.__slRelaxChatInstalled = true;

  const css = `
    #sl-chat-launcher{position:fixed;right:14px;bottom:calc(82px + env(safe-area-inset-bottom,0px));z-index:9990;border:0;border-radius:999px;padding:12px 16px;background:linear-gradient(135deg,#234e80,#6b55c9);color:white;box-shadow:0 8px 26px #142c4a40;font:700 14px system-ui;display:flex;align-items:center;gap:9px;cursor:pointer}
    #sl-chat-launcher i{width:9px;height:9px;border-radius:50%;background:#9ca3af;box-shadow:0 0 0 3px #ffffff24}
    #sl-chat-launcher.is-online i{background:#22c55e;box-shadow:0 0 0 3px #22c55e2e}
    #sl-chat-panel{position:fixed;right:12px;bottom:calc(140px + env(safe-area-inset-bottom,0px));z-index:9991;width:min(360px,calc(100vw - 24px));height:min(520px,calc(100dvh - 185px));min-height:300px;background:#fff;color:#17283d;border:1px solid #dbe5f1;border-radius:20px;box-shadow:0 18px 60px #10274438;display:none;overflow:hidden;font:14px/1.4 system-ui}
    #sl-chat-panel *{box-sizing:border-box}#sl-chat-panel.open{display:flex;flex-direction:column}
    .slch-head{padding:15px;background:linear-gradient(120deg,#18324b,#425aa8);color:#fff;display:flex;align-items:center;gap:10px}
    .slch-icon{width:38px;height:38px;border-radius:13px;background:#ffffff20;display:grid;place-items:center;font-size:20px}
    .slch-title{font-weight:800;font-size:15px}.slch-sub{font-size:11px;color:#dbeafe}
    #slch-close{margin-left:auto;border:0;background:#ffffff20;color:#fff;width:32px;height:32px;border-radius:10px;font-size:21px}
    .slch-status{padding:7px 14px;background:#f5f8fc;border-bottom:1px solid #e6edf5;display:flex;justify-content:space-between;align-items:center;color:#64748b;font-size:11px}
    #slch-connection{display:flex;align-items:center;gap:6px}#slch-connection:before{content:"";width:7px;height:7px;border-radius:50%;background:#9ca3af}
    #slch-connection.is-online:before{background:#22c55e}
    #slch-feed{flex:1;min-height:0;overflow-y:auto;padding:12px;background:linear-gradient(180deg,#f8fbff,#f4f6fc);display:flex;flex-direction:column;gap:9px}
    .slch-note{font-size:11px;color:#64748b;background:#edf3fb;padding:9px 10px;border-radius:10px}
    .slch-msg{max-width:88%;align-self:flex-start;background:#fff;border:1px solid #e2eaf4;border-radius:4px 14px 14px 14px;padding:8px 10px;overflow-wrap:anywhere}
    .slch-msg.mine{align-self:flex-end;background:#e8efff;border-color:#d5e0ff;border-radius:14px 4px 14px 14px}
    .slch-name{font-weight:800;font-size:11px;color:#465db1;margin-bottom:3px}.slch-name.slch-admin{display:inline-flex;align-items:center;gap:5px;color:#a56b00;background:linear-gradient(135deg,#fff6d8,#ffe9a8);border:1px solid #e5bf54;border-radius:999px;padding:3px 8px;letter-spacing:.2px}.slch-name.slch-admin:before{content:'◆';font-size:10px;color:#c18b12}.slch-body{white-space:pre-wrap;word-break:break-word}
    .slch-time{font-size:9px;color:#8390a4;text-align:right;margin-top:4px}
    .slch-entry{padding:10px 12px;background:#fff;border-top:1px solid #e4ebf3}
    .slch-row{display:flex;gap:7px;margin-bottom:8px}
    .slch-row textarea{min-width:0;flex:1;border:1px solid #d8e2ee;border-radius:10px;padding:9px;font:13px system-ui;color:#17283d;background:#fff;resize:none;max-height:86px}
    .slch-row button{border:0;border-radius:10px;background:#425bb7;color:#fff;font-weight:800;padding:9px 11px}
    .slch-row button:disabled,.slch-row textarea:disabled{opacity:.5}
    .slch-foot{font-size:10px;color:#8793a5}.slch-error{font-size:11px;color:#b42318;margin-bottom:4px}
    @media(max-width:480px){#sl-chat-launcher{right:10px;bottom:calc(76px + env(safe-area-inset-bottom,0px));padding:11px 13px}#sl-chat-panel{right:8px;bottom:calc(132px + env(safe-area-inset-bottom,0px));width:calc(100vw - 16px);height:min(560px,calc(100dvh - 174px))}}
    body.sules-admin-mode #sl-chat-launcher,body.sules-admin-mode #sl-chat-panel{display:none!important}
  `;
  const style = document.createElement("style");
  style.textContent = css;
  document.head.appendChild(style);

  const button = document.createElement("button");
  button.id = "sl-chat-launcher";
  button.type = "button";
  button.setAttribute("aria-label", "Buka Obrolan Bersama");
  button.setAttribute("aria-expanded", "false");
  button.innerHTML = '<i aria-hidden="true"></i><span>Obrolan Bersama</span>';

  const panel = document.createElement("section");
  panel.id = "sl-chat-panel";
  panel.setAttribute("role", "dialog");
  panel.setAttribute("aria-label", "Obrolan Bersama SL RELAX");
  panel.innerHTML = '<header class="slch-head"><div class="slch-icon">💬</div><div><div class="slch-title">Obrolan Bersama</div><div class="slch-sub">Ruang publik SL RELAX</div></div><button id="slch-close" aria-label="Tutup obrolan" type="button">×</button></header><div class="slch-status"><span id="slch-connection">Menghubungkan…</span><span id="slch-online">0 di ruang</span></div><div id="slch-feed" aria-live="polite"><div class="slch-note">Memuat percakapan…</div></div><form class="slch-entry" id="slch-form"><div class="slch-row"><textarea id="slch-input" rows="1" maxlength="240" placeholder="Login untuk ikut mengobrol…" aria-label="Tulis pesan" disabled></textarea><button id="slch-send" type="submit" disabled>Kirim</button></div><div id="slch-error" class="slch-error" role="status"></div><div id="slch-foot" class="slch-foot">Pengunjung tanpa login dapat membaca. Masuk ke akun SL RELAX untuk mengirim pesan.</div></form>';
  document.body.append(button, panel);

  const $ = id => panel.querySelector("#" + id);
  const feed = $("slch-feed"), conn = $("slch-connection"), online = $("slch-online");
  const input = $("slch-input"), send = $("slch-send"), error = $("slch-error"), foot = $("slch-foot");
  const seen = new Set();
  let messageChannel = null, presenceChannel = null, authSubscription = null;
  let connected = false, presenceConnected = false, opening = false, currentSession = null, profile = null;

  function safeText(value) { return String(value == null ? "" : value); }
  function trimFeed() { while (feed.children.length > 60) feed.removeChild(feed.firstElementChild); }
  function note(message) {
    const item = document.createElement("div");
    item.className = "slch-note";
    item.textContent = message;
    feed.appendChild(item);
    trimFeed();
    feed.scrollTop = feed.scrollHeight;
  }
  function render(row) {
    if (!row || row.id == null || seen.has(String(row.id)) || row.is_hidden) return;
    const message = safeText(row.message).trim();
    const name = safeText(row.sender_name).trim();
    if (!message || !name) return;
    seen.add(String(row.id));
    const box = document.createElement("article");
    box.className = "slch-msg";
    const title = document.createElement("div");
    title.className = row.is_admin === true ? "slch-name slch-admin" : "slch-name";
    title.textContent = name;
    const body = document.createElement("div");
    body.className = "slch-body";
    body.textContent = message;
    const time = document.createElement("div");
    time.className = "slch-time";
    const date = new Date(row.created_at);
    time.textContent = Number.isNaN(date.getTime()) ? "" : date.toLocaleTimeString("id-ID", { hour: "2-digit", minute: "2-digit" });
    box.append(title, body, time);
    feed.appendChild(box);
    trimFeed();
    feed.scrollTop = feed.scrollHeight;
  }
  function updateStatus(message) {
    const ready = connected && presenceConnected;
    button.classList.toggle("is-online", ready);
    conn.classList.toggle("is-online", ready);
    conn.textContent = message || (ready ? "Obrolan aktif" : "Menghubungkan…");
  }
  function updateComposer() {
    const loggedIn = !!(currentSession && currentSession.user && currentSession.user.id);
    const profileReady = !!(profile && typeof profile.nama === "string" && profile.nama.trim().length >= 2);
    input.disabled = !connected || !loggedIn || !profileReady;
    send.disabled = input.disabled;
    if (!loggedIn) {
      input.placeholder = "Login untuk ikut mengobrol…";
      foot.textContent = "Pengunjung tanpa login dapat membaca. Masuk ke akun SL RELAX untuk mengirim pesan.";
    } else if (!profileReady) {
      input.placeholder = "Lengkapi profil terlebih dahulu…";
      foot.textContent = "Lengkapi nama profil di menu Akun SL RELAX agar nama pengirim jelas.";
    } else {
      input.placeholder = "Tulis pesan…";
      foot.textContent = "Pesan tersimpan dalam riwayat Obrolan Bersama. Jangan bagikan data pribadi.";
    }
  }
  async function refreshAccount(session) {
    try {
      currentSession = session === undefined ? await window.bookingService.getCustomerSession() : session;
      profile = null;
      if (currentSession && currentSession.user && currentSession.user.id) {
        profile = await window.bookingService.getCustomerProfile(currentSession.user.id);
      }
    } catch (_) {
      profile = null;
    }
    updateComposer();
  }
  async function loadHistory() {
    if (feed.firstElementChild && feed.firstElementChild.classList.contains("slch-note") && feed.firstElementChild.textContent === "Memuat percakapan…") feed.firstElementChild.remove();
    try {
      const rows = await window.bookingService.getChatMessages(50);
      if (!rows.length && !feed.children.length) note("Belum ada pesan. Jadilah yang pertama menyapa 😊");
      rows.forEach(render);
    } catch (_) {
      note("Riwayat belum dapat dimuat. Coba tutup lalu buka obrolan kembali.");
    }
  }
  async function connect() {
    if (opening || connected) return;
    opening = true;
    updateStatus("Menghubungkan…");
    await refreshAccount();
    try {
      messageChannel = window.bookingService.subscribeChatMessages(row => render(row), async status => {
        if (status === "SUBSCRIBED") {
          connected = true;
          opening = false;
          updateStatus();
          updateComposer();
          await loadHistory();
        } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") {
          connected = false;
          opening = false;
          updateStatus("Koneksi obrolan terputus");
          updateComposer();
        }
      });
      presenceChannel = window.bookingService.subscribeChatPresence(count => {
        online.textContent = count + " di ruang";
      }, status => {
        presenceConnected = status === "SUBSCRIBED";
        if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") {
          presenceConnected = false;
        }
        updateStatus();
      });
    } catch (_) {
      opening = false;
      connected = false;
      updateStatus("Obrolan belum dapat tersambung");
      updateComposer();
    }
  }
  async function disconnect() {
    const oldMessages = messageChannel, oldPresence = presenceChannel;
    messageChannel = null;
    presenceChannel = null;
    connected = false;
    presenceConnected = false;
    opening = false;
    updateStatus("Obrolan ditutup");
    updateComposer();
    try { await window.bookingService.removeChatChannel(oldMessages); } catch (_) {}
    try { await window.bookingService.removeChatChannel(oldPresence); } catch (_) {}
  }
  function open() {
    panel.classList.add("open");
    button.setAttribute("aria-expanded", "true");
    error.textContent = "";
    feed.replaceChildren();
    seen.clear();
    note("Memuat percakapan…");
    if (!connected && !opening) void connect();
  }
  function close() {
    panel.classList.remove("open");
    button.setAttribute("aria-expanded", "false");
    void disconnect();
  }

  button.addEventListener("click", () => panel.classList.contains("open") ? close() : open());
  $("slch-close").addEventListener("click", close);
  $("slch-form").addEventListener("submit", async event => {
    event.preventDefault();
    error.textContent = "";
    const text = input.value.trim();
    if (!text) return;
    if (!currentSession || !currentSession.user || !currentSession.user.id) {
      error.textContent = "Masuk ke akun SL RELAX terlebih dahulu untuk mengirim pesan.";
      return;
    }
    if (!profile || !profile.nama || profile.nama.trim().length < 2) {
      error.textContent = "Lengkapi nama profil di menu Akun sebelum mengirim pesan.";
      return;
    }
    send.disabled = true;
    try {
      const row = await window.bookingService.sendChatMessage(text);
      render(row);
      input.value = "";
      input.style.height = "auto";
    } catch (e) {
      const detail = safeText(e && e.message).toLowerCase();
      if (detail.includes("lengkapi nama profil")) error.textContent = "Lengkapi nama profil di menu Akun sebelum mengirim pesan.";
      else if (detail.includes("login") || detail.includes("permission") || detail.includes("jwt")) error.textContent = "Sesi login tidak aktif. Masuk kembali ke akun SL RELAX.";
      else error.textContent = "Pesan belum terkirim. Periksa koneksi lalu coba lagi.";
    } finally {
      updateComposer();
    }
  });
  input.addEventListener("input", () => {
    input.style.height = "auto";
    input.style.height = Math.min(input.scrollHeight, 86) + "px";
  });
  document.addEventListener("keydown", event => {
    if (event.key === "Escape" && panel.classList.contains("open")) close();
  });
  if (window.bookingService && typeof window.bookingService.subscribeCustomerAuthChanges === "function") {
    authSubscription = window.bookingService.subscribeCustomerAuthChanges((_event, session) => {
      void refreshAccount(session);
    });
  }
  window.addEventListener("pagehide", () => {
    void disconnect();
    if (authSubscription && window.bookingService) {
      window.bookingService.removeCustomerAuthSubscription(authSubscription);
      authSubscription = null;
    }
  });
})();
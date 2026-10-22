(function () {
  "use strict";
  if (window.__slRelaxChatInstalled) return;
  window.__slRelaxChatInstalled = true;

  const css = `
    #sl-chat-launcher{position:fixed;right:14px;bottom:calc(82px + env(safe-area-inset-bottom,0px));z-index:9990;border:0;border-radius:999px;padding:12px 16px;background:linear-gradient(135deg,#234e80,#6b55c9);color:white;box-shadow:0 8px 26px #142c4a40;font:700 14px system-ui;display:flex;align-items:center;gap:9px;cursor:pointer}
    #sl-chat-launcher i{width:9px;height:9px;border-radius:50%;background:#9ca3af;box-shadow:0 0 0 3px #ffffff24}
    #sl-chat-launcher.is-online i{background:#22c55e;box-shadow:0 0 0 3px #22c55e2e}
    #sl-chat-panel{position:fixed;right:12px;bottom:calc(140px + env(safe-area-inset-bottom,0px));z-index:9991;width:min(460px,calc(100vw - 24px));height:min(680px,calc(100dvh - 150px));min-height:300px;background:#10182d;color:#f4f7ff;border:1px solid #29385c;border-radius:20px;box-shadow:0 18px 60px #10274438;display:none;overflow:hidden;font:14px/1.4 system-ui}
    #sl-chat-panel *{box-sizing:border-box}#sl-chat-panel.open{display:flex;flex-direction:column}
    .slch-head{padding:15px;background:linear-gradient(120deg,#10182d,#263e83 58%,#5940a7);color:#fff;display:flex;align-items:center;gap:10px}
    .slch-icon{width:38px;height:38px;border-radius:13px;background:#ffffff20;display:grid;place-items:center;font-size:20px}
    .slch-title{font-weight:800;font-size:15px}.slch-sub{font-size:11px;color:#dbeafe}
    #slch-close{margin-left:auto;border:0;background:#ffffff20;color:#fff;width:32px;height:32px;border-radius:10px;font-size:21px}
    .slch-status{padding:7px 14px;background:#151f38;border-bottom:1px solid #293653;display:flex;justify-content:space-between;align-items:center;color:#aab8d4;font-size:11px}
    #slch-connection{display:flex;align-items:center;gap:6px}#slch-connection:before{content:"";width:7px;height:7px;border-radius:50%;background:#9ca3af}
    #slch-connection.is-online:before{background:#22c55e}
     #slch-feed{flex:1;min-height:0;overflow-y:auto;padding:8px 10px 10px;background:linear-gradient(180deg,#10182d,#131d35);display:flex;flex-direction:column;gap:2px;position:relative}
    .slch-note{font-size:10px;color:#c1cde5;background:#202d4b;border:1px solid #2b3b61;padding:7px 8px;border-radius:9px}
    #slch-typing{display:none;align-items:center;gap:4px;height:20px;padding:0 14px 5px;background:#10182d}
    #slch-typing.is-active{display:flex}
    #slch-typing span{width:5px;height:5px;border-radius:50%;background:#a5b4fc;animation:slch-dot-bounce .9s infinite ease-in-out}
    #slch-typing span:nth-child(2){animation-delay:.15s}
    #slch-typing span:nth-child(3){animation-delay:.3s}
    @keyframes slch-dot-bounce{0%,60%,100%{transform:translateY(0);opacity:.5}30%{transform:translateY(-4px);opacity:1}}
    @media(prefers-reduced-motion:reduce){#slch-typing span{animation:none;opacity:1}}
    .slch-msg{width:fit-content;max-width:88%;align-self:flex-start;background:linear-gradient(145deg,#202e50,#252b4a);color:#f5f7ff;border:1px solid #3b4f7c;border-radius:4px 11px 11px 11px;padding:2px 9px;overflow-wrap:anywhere;box-shadow:0 2px 7px #050b1818}
    .slch-msg.mine{align-self:flex-end;background:linear-gradient(135deg,#245be8,#6549c7);color:#fff;border-color:#7c83f5;border-radius:11px 4px 11px 11px;box-shadow:0 2px 7px #4038a52b}
    .slch-name{font-weight:800;font-size:10px;color:#b8c9ff;margin-bottom:0}.slch-name.slch-admin{display:inline-flex;align-items:center;gap:4px;color:#c9a96e;background:transparent;border:0;border-radius:0;padding:0;letter-spacing:.1px}.slch-name.slch-admin:before{content:'◆';font-size:7px;color:#c9a96e}.slch-body{white-space:pre-wrap;overflow-wrap:anywhere;word-break:normal;font-size:13px;line-height:1.2;letter-spacing:.02px}
    .slch-mention{color:#a5b4fc;font-weight:900;text-shadow:0 0 10px #818cf833}.slch-msg.mine .slch-mention{color:#f0d9ff;text-shadow:0 0 8px #c084fc55}
    .slch-quoted{display:block;width:100%;margin:0 0 4px;padding:5px 7px;border:0;border-left:3px solid #a5b4fc;border-radius:5px;background:#ffffff12;color:inherit;text-align:left;cursor:pointer;min-width:0}
    .slch-quoted-name{display:block;font-size:10px;font-weight:800;color:#c4b5fd;margin-bottom:2px}
    .slch-quoted-text{display:block;font-size:11px;line-height:1.3;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:#e2e8f0}
    .slch-msg.mine .slch-quoted{border-left-color:#f0d9ff;background:#ffffff18}
    .slch-msg.mine .slch-quoted-name{color:#f0d9ff}
    .slch-time{font-size:9px;color:#b4c0dc;text-align:right;margin-top:0}
    .slch-reply{align-self:flex-start;margin-top:2px;border:1px solid #5369a0;border-radius:999px;padding:2px 7px;background:#1a2744;color:#c7d2fe;font:700 10px system-ui;cursor:pointer}.slch-reply:active{background:#344b88}
    .slch-reply-preview{display:none;align-items:center;gap:8px;margin-bottom:8px;padding:7px 8px;border:1px solid #465c91;border-left:3px solid #8b7bff;border-radius:9px;background:#182744;min-width:0}
    .slch-reply-preview.is-active{display:flex}
    .slch-reply-preview-content{display:flex;align-items:center;gap:8px;min-width:0;flex:1;overflow:hidden}
    .slch-reply-preview-name{flex:0 1 92px;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:10px;font-weight:700;color:#b8a8ff;margin:0}
    .slch-reply-preview-text{flex:1;min-width:0;font-size:11px;color:#dbe5ff;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .slch-reply-cancel{flex:0 0 28px;width:28px;height:28px;padding:0!important;border:0;border-radius:8px;background:#ffffff12!important;color:#dbe5ff;font-size:20px;line-height:1;cursor:pointer}
    .slch-entry{padding:12px;background:#111a30;border-top:1px solid #35466c}
    .slch-row{display:flex;gap:7px;margin-bottom:8px}
    .slch-row textarea{min-width:0;flex:1;border:1px solid #465c91;border-radius:12px;padding:10px 11px;font:14px/1.45 system-ui;color:#f4f7ff;background:#182744;resize:none;max-height:120px}
    .slch-row button{border:0;border-radius:10px;background:linear-gradient(135deg,#245beb,#7654e8);color:#fff;font-weight:800;padding:8px 10px}
    .slch-row button:disabled,.slch-row textarea:disabled{opacity:.5}
    .slch-foot{font-size:9px;color:#a5b2cc}.slch-error{font-size:10px;color:#ff9caa;margin-bottom:4px}
    @media(max-width:480px){#sl-chat-launcher{right:10px;bottom:calc(76px + env(safe-area-inset-bottom,0px));padding:11px 13px}#sl-chat-panel{right:6px;bottom:calc(132px + env(safe-area-inset-bottom,0px));width:calc(100vw - 12px);height:min(640px,calc(100dvh - 158px));border-radius:18px}.slch-msg{max-width:92%}.slch-body{width:fit-content;max-width:100%;font-size:13px;line-height:1.2}}

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
  panel.innerHTML = '<header class="slch-head"><div class="slch-icon">💬</div><div><div class="slch-title">Obrolan Bersama</div><div class="slch-sub">Ruang publik SL RELAX</div></div><button id="slch-close" aria-label="Tutup obrolan" type="button">×</button></header><div class="slch-status"><span id="slch-connection">Menghubungkan…</span><span id="slch-online">0 di ruang</span></div><div id="slch-feed" aria-live="polite"><div class="slch-note">Memuat percakapan…</div></div><div id="slch-typing" aria-label="Pengguna sedang mengetik" aria-live="polite"><span></span><span></span><span></span></div><form class="slch-entry" id="slch-form"><div id="slch-reply-preview" class="slch-reply-preview" role="status" aria-live="polite"><div class="slch-reply-preview-content"><div id="slch-reply-preview-name" class="slch-reply-preview-name"></div><div id="slch-reply-preview-text" class="slch-reply-preview-text"></div></div><button id="slch-reply-cancel" class="slch-reply-cancel" type="button" aria-label="Batalkan balasan">×</button></div><div class="slch-row"><textarea id="slch-input" rows="1" maxlength="240" placeholder="Login untuk ikut mengobrol…" aria-label="Tulis pesan" disabled></textarea><button id="slch-send" type="submit" disabled>Kirim</button></div><div id="slch-error" class="slch-error" role="status"></div><div id="slch-foot" class="slch-foot">Pengunjung tanpa login dapat membaca. Masuk ke akun SL RELAX untuk mengirim pesan.</div></form>';
  
  document.body.append(button, panel);

  const $ = id => panel.querySelector("#" + id);
  const feed = $("slch-feed"), conn = $("slch-connection"), online = $("slch-online");
  const input = $("slch-input"), send = $("slch-send"), error = $("slch-error"), foot = $("slch-foot");
  const typingIndicator = $("slch-typing");
  const replyPreview = $("slch-reply-preview"), replyPreviewName = $("slch-reply-preview-name"), replyPreviewText = $("slch-reply-preview-text");
  const seen = new Set();
  let messageChannel = null, presenceChannel = null, typingChannel = null, authSubscription = null;
  let connected = false, presenceConnected = false, typingConnected = false, opening = false, currentSession = null, profile = null;
  let replyTarget = null, typingStopTimer = null, localTypingActive = false;
  const remoteTypingPeers = new Set(), remoteTypingTimers = new Map();
  function clearRemoteTyping() { remoteTypingTimers.forEach(timer => window.clearTimeout(timer)); remoteTypingTimers.clear(); remoteTypingPeers.clear(); typingIndicator.classList.remove("is-active"); }
  function broadcastTyping(isTyping) { if (typingConnected && typingChannel) void window.bookingService.sendChatTyping(typingChannel, isTyping); }
  function markLocalTyping() {
    if (input.disabled || !typingConnected || !typingChannel) return;
    if (!localTypingActive) { localTypingActive = true; broadcastTyping(true); }
    if (typingStopTimer) window.clearTimeout(typingStopTimer);
    typingStopTimer = window.setTimeout(() => { localTypingActive = false; broadcastTyping(false); typingStopTimer = null; }, 1800);
  }
  function stopLocalTyping() {
    if (typingStopTimer) window.clearTimeout(typingStopTimer);
    typingStopTimer = null;
    if (localTypingActive) broadcastTyping(false);
    localTypingActive = false;
  }

  function safeText(value) { return String(value == null ? "" : value); }
  function updateReplyPreview() {
    const active = !!replyTarget;
    replyPreview.classList.toggle("is-active", active);
    // Inline display prevents site-wide CSS from hiding the reply preview.
    replyPreview.style.display = active ? "flex" : "none";
    if (active) {
      replyPreviewName.textContent = replyTarget.name;
      const excerpt = replyTarget.message.replace(/\s+/g, " ").trim();
      replyPreviewText.textContent = excerpt.length > 120 ? excerpt.slice(0, 117) + "…" : excerpt;
      replyPreviewText.title = replyTarget.message;
    } else {
      replyPreviewName.textContent = "";
      replyPreviewText.textContent = "";
      replyPreviewText.removeAttribute("title");
    }
  }
  function cancelReply() {
    replyTarget = null;
    updateReplyPreview();
    input.style.height = "auto";
    input.style.height = Math.min(input.scrollHeight, 86) + "px";
    input.focus();
  }
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
    box.dataset.messageId = String(row.id);
    const title = document.createElement("div");
    title.className = row.is_admin === true ? "slch-name slch-admin" : "slch-name";
    title.textContent = name;
    if (row.reply_to_message) {
      const quote = document.createElement("button");
      quote.type = "button";
      quote.className = "slch-quoted";
      quote.setAttribute("aria-label", "Pesan yang dibalas dari " + safeText(row.reply_to_name));
      const quoteName = document.createElement("span");
      quoteName.className = "slch-quoted-name";
      quoteName.textContent = safeText(row.reply_to_name) || "Pesan";
      const quoteText = document.createElement("span");
      quoteText.className = "slch-quoted-text";
      quoteText.textContent = safeText(row.reply_to_message).replace(/\s+/g, " ").trim();
      quote.title = safeText(row.reply_to_message);
      quote.append(quoteName, quoteText);
      if (row.reply_to_id != null) {
        quote.addEventListener("click", () => {
          const original = feed.querySelector('[data-message-id="' + String(row.reply_to_id).replace(/[^0-9]/g, "") + '"]');
          if (original) {
            original.scrollIntoView({ behavior: "smooth", block: "center" });
            original.animate([{ outline: "2px solid #c4b5fd" }, { outline: "2px solid transparent" }], { duration: 1100 });
          }
        });
      } else {
        quote.disabled = true;
        quote.style.cursor = "default";
      }
      box.appendChild(quote);
    }
    const body = document.createElement("div");
    body.className = "slch-body";
    const mention = message.match(/^(@[^\s]+)([\s\S]*)$/);
    if (mention) {
      const highlighted = document.createElement("span");
      highlighted.className = "slch-mention";
      highlighted.textContent = mention[1];
      body.append(highlighted, document.createTextNode(mention[2]));
    } else {
      body.textContent = message;
    }
    const time = document.createElement("div");
    time.className = "slch-time";
    const date = new Date(row.created_at);
    time.textContent = Number.isNaN(date.getTime()) ? "" : date.toLocaleTimeString("id-ID", { hour: "2-digit", minute: "2-digit" });
    box.append(title, body, time);
    const reply = document.createElement("button");
    reply.type = "button";
    reply.className = "slch-reply";
    reply.textContent = "Balas";
    reply.setAttribute("aria-label", "Balas pesan " + name);
    reply.addEventListener("click", () => {
      if (input.disabled) {
        error.textContent = !currentSession || !currentSession.user || !currentSession.user.id
          ? "Masuk ke akun SL RELAX terlebih dahulu untuk membalas pesan."
          : "Lengkapi nama profil di menu Akun sebelum membalas pesan.";
        return;
      }
      error.textContent = "";
      replyTarget = { id: row.id, name, message };
      updateReplyPreview();
      input.focus();
      input.style.height = "auto";
      input.style.height = Math.min(input.scrollHeight, 86) + "px";
      input.setSelectionRange(input.value.length, input.value.length);
    });
    box.appendChild(reply);
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
      typingChannel = window.bookingService.subscribeChatTyping(payload => {
        const peerKey = String(payload.client_key || "");
        if (!peerKey) return;
        const oldTimer = remoteTypingTimers.get(peerKey);
        if (oldTimer) window.clearTimeout(oldTimer);
        if (payload.is_typing === true) {
          remoteTypingPeers.add(peerKey);
          typingIndicator.classList.add("is-active");
          remoteTypingTimers.set(peerKey, window.setTimeout(() => {
            remoteTypingTimers.delete(peerKey);
            remoteTypingPeers.delete(peerKey);
            typingIndicator.classList.toggle("is-active", remoteTypingPeers.size > 0);
          }, 2200));
        } else {
          remoteTypingTimers.delete(peerKey);
          remoteTypingPeers.delete(peerKey);
          typingIndicator.classList.toggle("is-active", remoteTypingPeers.size > 0);
        }
      }, status => {
        typingConnected = status === "SUBSCRIBED";
        if (!typingConnected) { stopLocalTyping(); clearRemoteTyping(); }
      });
    } catch (_) {
      opening = false;
      connected = false;
      updateStatus("Obrolan belum dapat tersambung");
      updateComposer();
    }
  }
  async function disconnect() {
    const oldMessages = messageChannel, oldPresence = presenceChannel, oldTyping = typingChannel;
    stopLocalTyping();
    clearRemoteTyping();
    messageChannel = null;
    presenceChannel = null;
    typingChannel = null;
    connected = false;
    presenceConnected = false;
    typingConnected = false;
    opening = false;
    updateStatus("Obrolan ditutup");
    updateComposer();
    try { await window.bookingService.removeChatChannel(oldMessages); } catch (_) {}
    try { await window.bookingService.removeChatChannel(oldPresence); } catch (_) {}
    try { await window.bookingService.removeChatChannel(oldTyping); } catch (_) {}
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
  $("slch-reply-cancel").addEventListener("click", cancelReply);
  $("slch-form").addEventListener("submit", async event => {
    event.preventDefault();
    error.textContent = "";
    const text = input.value.trim();
    stopLocalTyping();
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
      const row = await window.bookingService.sendChatMessage(text, replyTarget ? replyTarget.id : null);
      render(row);
      input.value = "";
      replyTarget = null;
      updateReplyPreview();
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
    if (input.value.trim()) markLocalTyping(); else stopLocalTyping();
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
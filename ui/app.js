// Actual Budget's tabs on the chassis window: Budgets, Sign-in, and the HTTPS part of Site address.
(function (P) {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  function abUrl(st) { return ((st.app || {}).url || "").replace(/\/$/, ""); }
  function touched(id) { ["input", "change"].forEach(function (e) { $(id).addEventListener(e, function () { $(id).dataset.touched = "1"; }); }); }
  function quiet(id, v) { if (!$(id).dataset.touched) $(id).value = v == null ? "" : v; }
  function size(b) { return b >= 1048576 ? (b / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round((b || 0) / 1024)) + " KB"; }

  // ---------------------------------------------------------------- Budgets
  ["st-days", "lm-mb"].forEach(touched);
  P.register("budgets", {
    render: function (st) {
      var a = st.app || {}, list = (a.budgets || []), live = list.filter(function (b) { return !b.deleted; }), t = $("bd-tiles");
      document.querySelectorAll(".ab-link").forEach(function (x) { x.href = abUrl(st) || "#"; });
      var last = live.reduce(function (m, b) { return Math.max(m, b.changed || 0); }, 0);
      P.clear(t); P.tile(t, String(live.length), live.length === 1 ? "budget" : "budgets"); P.tile(t, last ? P.ago(last) : "–", "last sync");
      P.tile(t, String(a.sessions || 0), "devices signed in");
      quiet("st-days", String(a.stale_days == null ? 14 : a.stale_days)); quiet("lm-mb", String(a.limit_mb || 20));
      var tb = $("bd-list"), sig = JSON.stringify(list); if (tb.dataset.sig === sig) return; tb.dataset.sig = sig; P.clear(tb);
      if (!list.length) { var r0 = P.el("tr"), c0 = P.cell("No budgets here yet. Open Actual, make a budget (or import one from YNAB or a file), and it syncs here.", "empty"); c0.colSpan = 4; r0.appendChild(c0); tb.appendChild(r0); }
      list.forEach(function (b) {
        var who = P.el("div"); who.appendChild(P.el("b", b.name));
        var chip = b.deleted ? P.chip("deleted in Actual", "") : b.encrypted ? P.chip("encrypted", "ok") : P.el("span", "");
        var tr = P.row(tb, [P.cell(who), size(b.size), b.changed ? P.ago(b.changed) : "–", P.cell(chip, "n")]);
        if (b.deleted) tr.className = "muted-row";
      });
    },
    tiles: function (t, st) { var l = ((st.app || {}).budgets || []).filter(function (b) { return !b.deleted; }); P.tile(t, String(l.length), l.length === 1 ? "budget" : "budgets"); }
  });
  $("st-save").onclick = function () { P.act("stale", { days: $("st-days").value }).then(function () { $("st-days").dataset.touched = ""; }); };
  $("lm-save").onclick = function () { P.act("limit", { mb: $("lm-mb").value }).then(function () { $("lm-mb").dataset.touched = ""; }); };

  // ---------------------------------------------------------------- Sign-in
  P.register("signin", {
    render: function (st) {
      var a = st.app || {}, t = $("si-tiles"), tls = a.tls || {};
      P.clear(t); P.tile(t, a.method === "openid" ? "OpenID" : "password", "sign-in"); P.tile(t, String(a.sessions || 0), "devices signed in");
      if (a.qr && $("si-qr").dataset.qr !== a.qr) { $("si-qr").src = "data:image/png;base64," + a.qr; $("si-qr").dataset.qr = a.qr; }
      $("si-url").textContent = a.url || "";
      $("si-cert").textContent = tls.source === "self" ? "The certificate is self-signed: the phone warns once — accept it, or use a trusted certificate (Site address)." : "";
    }
  });
  P.register("secretNote", function () { return "Use it to sign in to Actual on each device, then keep it in your password manager."; });
  $("pw-new").onclick = function () { P.act("newpw", { signout: $("pw-out").checked ? 1 : 0 }, "Make a new server password? The old one stops working." + ($("pw-out").checked ? " Every device will have to sign in again." : "")); };
  $("so-all").onclick = function () { P.act("signout", {}, "Sign out every device? Each one signs in again with the password; nothing in the budgets is lost."); };

  // ---------------------------------------------------------------- Site address: HTTPS
  P.register("site", {
    fill: function (st) { var t = (st.app && st.app.tls) || {}; $("set-tls").value = t.mode || "dsm"; },
    values: function () { return { tls: $("set-tls").value }; },
    render: function (st) {
      var t = (st.app && st.app.tls) || {}, c = t.cert, tb = $("tls-info"), note = $("tls-note"), acts = $("tls-actions"); P.clear(tb); P.clear(acts);
      $("tls-card").hidden = !t.mode || t.mode === "off";
      if (!t.mode || t.mode === "off") return;
      if (!c) { P.kv(tb, "Certificate", "none yet — it's made or read when Actual starts"); note.textContent = ""; return; }
      P.kv(tb, "From", t.source === "dsm" ? "DSM (the system default certificate)" : "the package (self-signed)");
      P.kv(tb, "Issued to", c.subject || "–"); P.kv(tb, "Issued by", c.self_signed ? "itself (self-signed)" : (c.issuer || "–"));
      P.kv(tb, "Expires", (c.expires || "–") + (typeof c.days_left === "number" ? " (" + (c.days_left < 0 ? "expired" : c.days_left + " days") + ")" : ""));
      if (c.names) P.kv(tb, "Names", c.names.replace(/,/g, ", "));
      note.textContent = t.mode === "dsm" && t.source === "self" ? "DSM's certificate wasn't found on this system, so a self-signed one is in use."
        : c.self_signed ? "Self-signed: each browser and phone warns once. For no warnings, use a trusted certificate (Let's Encrypt in DSM, made the system default)."
        : "Browsers trust this certificate as long as they reach Actual by one of its names.";
      acts.appendChild(P.btn(t.mode === "dsm" ? "Read DSM's certificate again" : "Make a new self-signed certificate", "", function () { P.act("refreshcert", {}, t.mode === "dsm" ? null : "Make a new self-signed certificate?"); }));
    }
  });
  $("set-tls").addEventListener("change", function () { $("set-url").dataset.touched = "1"; var u = $("set-url").value.trim(); if ($("set-tls").value !== "off" && /^http:\/\//.test(u)) $("set-url").value = "https://" + u.slice(7); });

  // ---------------------------------------------------------------- Storage
  P.register("storage", { render: function (app, st, box) {
    P.clear(box); var c = P.el("div", null, "card"); c.appendChild(P.el("h2", "Inside the data volume")); var tbl = P.el("table"), tb = P.el("tbody"); tbl.appendChild(tb); c.appendChild(tbl);
    [["Budgets (files and sync history)", app.budgets], ["The server's account", app.account]].forEach(function (p) { P.kv(tb, p[0], P.mb(p[1] || 0), true); });
    box.appendChild(c);
  } });
})(window.Panel);

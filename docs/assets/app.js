/*
  Manual do Framework: registro de páginas, navegação em árvore, busca com sinônimos e realce de Luau.
  Funciona aberto direto do disco (file://): o conteúdo vem de content/*.js por <script>, sem fetch.

  Conteúdo (content/*.js):
    DOCS.page({ id, title, parent, kw, lead, html, src })      página de texto
    DOCS.group({ ... mesmos campos ... })                         página que lista as funções filhas
    DOCS.fn(groupId, { name, title?, call, desc, args, ret, ex, exDesc, notes, see, kw })
  Helpers: C(código) bloco Luau, E(texto) escapa HTML, L(id, texto?) link, T(cabeçalhos, linhas) tabela,
           N(html) nota, W(html) aviso.
*/
(function () {
  "use strict";

  var DOCS = (window.DOCS = { pages: {}, children: {}, roots: [], synonyms: [] });

  // ---------------------------------------------------------------- helpers de conteúdo
  function esc(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  window.E = esc;
  window.C = function (code) {
    var text = String(code).replace(/^\n+/, "").replace(/\s+$/, "");
    // tira a indentação comum (o código vem indentado dentro do template)
    var lines = text.split("\n");
    var min = Infinity;
    lines.forEach(function (l) {
      if (!l.trim()) return;
      var m = l.match(/^[ \t]*/)[0].length;
      if (m < min) min = m;
    });
    if (min !== Infinity && min > 0) lines = lines.map(function (l) { return l.slice(min); });
    return '<pre class="code"><code data-lang="lua">' + esc(lines.join("\n")) + "</code></pre>";
  };
  window.L = function (id, text) {
    return '<a href="#' + id + '"' + (text ? "" : " data-auto") + ">" + (text || id) + "</a>";
  };
  window.T = function (head, rows, cls) {
    var h = "<tr>" + head.map(function (c) { return "<th>" + c + "</th>"; }).join("") + "</tr>";
    var b = rows.map(function (r) {
      return "<tr>" + r.map(function (c) { return "<td>" + c + "</td>"; }).join("") + "</tr>";
    }).join("");
    return '<div class="table-wrap"><table' + (cls ? ' class="' + cls + '"' : "") + "><thead>" + h + "</thead><tbody>" + b + "</tbody></table></div>";
  };
  window.N = function (html) { return '<div class="callout note">' + html + "</div>"; };
  window.W = function (html) { return '<div class="callout warn">' + html + "</div>"; };

  // ---------------------------------------------------------------- registro
  function register(p) {
    if (!p.id || !p.title) throw new Error("página sem id/título: " + JSON.stringify(p).slice(0, 80));
    if (DOCS.pages[p.id]) throw new Error("id duplicado: " + p.id);
    DOCS.pages[p.id] = p;
    var parent = p.parent || "";
    if (parent) (DOCS.children[parent] = DOCS.children[parent] || []).push(p.id);
    else DOCS.roots.push(p.id);
    return p;
  }
  DOCS.page = function (p) { p.kind = p.kind || "page"; return register(p); };
  DOCS.group = function (p) { p.kind = "group"; return register(p); };
  DOCS.fn = function (groupId, f) {
    var id = groupId + "." + f.name;
    return register({
      id: id, title: f.title || f.name, parent: groupId, kind: "fn", fn: f, kw: f.kw || "", src: f.src,
    });
  };

  // ---------------------------------------------------------------- render de função
  function plain(html) {
    return String(html || "").replace(/<[^>]+>/g, " ").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
      .replace(/&quot;/g, '"').replace(/&amp;/g, "&").replace(/\s+/g, " ").trim();
  }
  function firstSentence(html) {
    var t = plain(html);
    var m = t.match(/^(.{20,}?[.:;])(\s|$)/);
    return m ? m[1] : t;
  }
  function fnHtml(p) {
    var f = p.fn;
    var out = "";
    out += '<p class="lead">' + (f.desc || "") + "</p>";
    out += "<h4>Sintaxe</h4>" + C(f.call || f.name).replace('class="code"', 'class="code syntax"');
    out += "<h4>Argumentos</h4>";
    if (f.args && f.args.length) {
      out += T(["Argumento", "Tipo", "Descrição"], f.args.map(function (a) {
        return ["<code>" + esc(a[0]) + "</code>", "<code>" + esc(a[1]) + "</code>", a[2] || ""];
      }));
    } else out += "<p>Nenhum.</p>";
    out += "<h4>Retorna</h4><p>" + (f.ret || "Nada.") + "</p>";
    if (f.notes) out += f.notes;
    if (f.ex) {
      out += "<h4>Exemplo</h4>" + C(f.ex);
      if (f.exDesc) out += "<p>" + f.exDesc + "</p>";
    }
    return out;
  }
  function groupList(p) {
    var kids = (DOCS.children[p.id] || []).map(function (id) { return DOCS.pages[id]; });
    var fns = kids.filter(function (k) { return k.kind === "fn"; });
    var others = kids.filter(function (k) { return k.kind !== "fn"; });
    var out = "";
    if (fns.length) {
      out += "<h2>Funções</h2>" + T(["Função", "Descrição"], fns.map(function (k) {
        return ['<a href="#' + k.id + '"><code>' + esc(k.title) + "</code></a>", esc(firstSentence(k.fn.desc))];
      }), "fn-list");
    }
    if (others.length) {
      out += "<h2>Nesta seção</h2><div class=\"cards\">" + others.map(function (k) {
        return '<a class="card" href="#' + k.id + '"><b>' + esc(k.title) + "</b><span>" + esc(firstSentence(k.lead || k.html || "")) + "</span></a>";
      }).join("") + "</div>";
    }
    return out;
  }

  // ---------------------------------------------------------------- realce de Luau
  var KW = {};
  "and break continue do else elseif end false for function if in local nil not or repeat return then true until while export type"
    .split(" ").forEach(function (k) { KW[k] = 1; });
  var BI = {};
  ("self game workspace script Vector3 CFrame Enum Instance task require table math string pairs ipairs print warn typeof " +
    "tostring tonumber setmetatable getmetatable os tick error pcall xpcall select next rawget rawset Color3 RaycastParams " +
    "OverlapParams Players RunService debug coroutine utf8 buffer")
    .split(" ").forEach(function (k) { BI[k] = 1; });
  var TOK = /(--\[(=*)\[[\s\S]*?\]\2\]|--[^\n]*)|(\[(=*)\[[\s\S]*?\]\4\]|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')|(\b0x[0-9a-fA-F_]+\b|\b\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?\b)|([A-Za-z_]\w*)/g;
  function highlight(src) {
    var out = "", last = 0, m;
    TOK.lastIndex = 0;
    while ((m = TOK.exec(src))) {
      out += esc(src.slice(last, m.index));
      var t = m[0], cls = null;
      if (m[1]) cls = "com";
      else if (m[3]) cls = "str";
      else if (m[5]) cls = "num";
      else if (m[6]) {
        if (KW[t]) cls = "kw";
        else if (BI[t]) cls = "bi";
        else if (/^\s*\(/.test(src.slice(TOK.lastIndex, TOK.lastIndex + 3))) cls = "fn";
      }
      out += cls ? '<span class="tk-' + cls + '">' + esc(t) + "</span>" : esc(t);
      last = TOK.lastIndex;
    }
    return out + esc(src.slice(last));
  }

  // ---------------------------------------------------------------- normalização e busca
  function norm(s) {
    return String(s || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  }
  DOCS.norm = norm;
  var INDEX = [];
  var SYN = []; // grupos normalizados
  function buildIndex() {
    SYN = DOCS.synonyms.map(function (g) { return g.map(norm); });
    INDEX = Object.keys(DOCS.pages).map(function (id) {
      var p = DOCS.pages[id];
      var body = p.kind === "fn"
        ? [p.fn.call, plain(p.fn.desc), (p.fn.args || []).map(function (a) { return a[0] + " " + plain(a[2]); }).join(" "),
           plain(p.fn.ret), plain(p.fn.notes), p.fn.ex || "", plain(p.fn.exDesc)].join(" ")
        : plain((p.lead || "") + " " + (p.html || ""));
      return {
        id: id, p: p,
        title: norm(p.title), kw: norm(p.kw || "") + " " + norm(id.replace(/[.\-]/g, " ")),
        body: norm(body), raw: body,
      };
    });
  }
  function expand(token) {
    var set = {};
    set[token] = 1;
    SYN.forEach(function (g) {
      var hit = g.some(function (term) {
        return term === token || (token.length >= 3 && term.indexOf(token) === 0) || (term.length >= 4 && token.indexOf(term) === 0);
      });
      if (hit) g.forEach(function (term) { set[term] = 1; });
    });
    return Object.keys(set);
  }
  function wordHit(hay, term) {
    var i = hay.indexOf(term);
    if (i < 0) return 0;
    var before = i === 0 ? " " : hay[i - 1];
    return /[a-z0-9_]/.test(before) ? 1 : 2; // 2 = começo de palavra
  }
  DOCS.search = function (q) {
    var tokens = norm(q).split(/[^a-z0-9_]+/).filter(function (t) { return t.length >= 2; });
    if (!tokens.length) return { results: [], extra: [] };
    var expansions = tokens.map(expand);
    var extra = [];
    expansions.forEach(function (ex, i) {
      ex.forEach(function (t) { if (t !== tokens[i] && extra.indexOf(t) < 0 && extra.length < 8) extra.push(t); });
    });
    var results = [];
    INDEX.forEach(function (e) {
      var total = 0;
      for (var i = 0; i < tokens.length; i++) {
        var best = 0;
        expansions[i].forEach(function (term) {
          var exact = term === tokens[i];
          var w = exact ? 1 : 0.6;
          var s = 0, h;
          if (e.title === term) s = Math.max(s, 30);
          if ((h = wordHit(e.title, term))) s = Math.max(s, (h === 2 ? 14 : 7));
          if ((h = wordHit(e.kw, term))) s = Math.max(s, (h === 2 ? 8 : 4));
          if ((h = wordHit(e.body, term))) s = Math.max(s, (h === 2 ? 3 : 1.2));
          best = Math.max(best, s * w);
        });
        if (best === 0) return; // todo termo precisa casar com algo
        total += best;
      }
      if (e.p.kind === "fn") total *= 1.05;
      results.push({ e: e, score: total });
    });
    results.sort(function (a, b) { return b.score - a.score || a.e.p.title.length - b.e.p.title.length; });
    return { results: results.slice(0, 14), extra: extra, terms: [].concat.apply([], expansions) };
  };
  function snippet(e, terms) {
    var body = e.body, raw = e.raw;
    var at = -1, len = 0;
    terms.forEach(function (t) {
      var i = body.indexOf(t);
      if (i >= 0 && (at < 0 || i < at)) { at = i; len = t.length; }
    });
    if (at < 0) return esc(raw.slice(0, 110)) + (raw.length > 110 ? "…" : "");
    var start = Math.max(0, at - 50), end = Math.min(raw.length, at + len + 70);
    return (start > 0 ? "…" : "") + esc(raw.slice(start, at)) + "<mark>" + esc(raw.slice(at, at + len)) + "</mark>" +
      esc(raw.slice(at + len, end)) + (end < raw.length ? "…" : "");
  }

  // ---------------------------------------------------------------- árvore e páginas
  function pathOf(id) {
    var path = [], p = DOCS.pages[id];
    while (p) { path.unshift(p); p = p.parent && DOCS.pages[p.parent]; }
    return path;
  }
  // Ordem do menu: p.order (menor primeiro); sem order, a ordem de registro, depois dos ordenados
  var SEQ = {};
  function sortChildren() {
    var n = 0;
    Object.keys(DOCS.pages).forEach(function (id) { SEQ[id] = n++; });
    function key(id) { var p = DOCS.pages[id]; return p.order != null ? p.order : 100000 + SEQ[id]; }
    function cmp(a, b) { return key(a) - key(b); }
    DOCS.roots.sort(cmp);
    Object.keys(DOCS.children).forEach(function (k) { DOCS.children[k].sort(cmp); });
  }
  var FLAT = [];
  function flatten(ids) {
    ids.forEach(function (id) { FLAT.push(id); flatten(DOCS.children[id] || []); });
  }
  var openSet = {};
  function loadOpen() {
    try { openSet = JSON.parse(localStorage.getItem("fwdocs-open") || "{}") || {}; } catch (e) { openSet = {}; }
  }
  function saveOpen() {
    try { localStorage.setItem("fwdocs-open", JSON.stringify(openSet)); } catch (e) {}
  }
  var CHEVRON = '<svg viewBox="0 0 24 24" width="12" height="12" aria-hidden="true"><path d="M9 6l6 6-6 6" stroke="currentColor" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  function treeHtml(ids) {
    return "<ul>" + ids.map(function (id) {
      var p = DOCS.pages[id], kids = DOCS.children[id] || [];
      var open = openSet[id] ? " open" : "";
      return '<li data-id="' + id + '" class="' + open + '"><div class="node">' +
        '<button class="twisty' + (kids.length ? "" : " leaf") + '" aria-label="Abrir ou fechar ' + esc(p.title) + '" tabindex="' + (kids.length ? 0 : -1) + '">' + CHEVRON + "</button>" +
        '<a href="#' + id + '" class="' + (p.kind === "fn" ? "fn" : "") + '">' + esc(p.title) + "</a></div>" +
        (kids.length ? treeHtml(kids) : "") + "</li>";
    }).join("") + "</ul>";
  }
  function syncTree(id) {
    var tree = document.getElementById("tree");
    pathOf(id).forEach(function (p) {
      if (DOCS.children[p.id]) {
        openSet[p.id] = true;
        var li = tree.querySelector('li[data-id="' + cssEsc(p.id) + '"]');
        if (li) li.classList.add("open");
      }
    });
    saveOpen();
    tree.querySelectorAll("a.current").forEach(function (a) { a.classList.remove("current"); });
    var cur = tree.querySelector('li[data-id="' + cssEsc(id) + '"] > .node > a');
    if (cur) {
      cur.classList.add("current");
      var r = cur.getBoundingClientRect(), side = document.getElementById("sidebar").getBoundingClientRect();
      if (r.top < side.top + 40 || r.bottom > side.bottom - 20) cur.scrollIntoView({ block: "center" });
    }
  }
  function cssEsc(s) { return String(s).replace(/(["\\])/g, "\\$1"); }

  var highlightTerms = null;
  function render(id) {
    var content = document.getElementById("content");
    var p = DOCS.pages[id];
    if (!p) {
      var guess = DOCS.search(id.replace(/[.\-_]/g, " ")).results.slice(0, 6);
      content.innerHTML = '<article class="page"><h1>Página não encontrada</h1><p class="lead">Não existe página <code>' + esc(id) +
        "</code>.</p>" + (guess.length ? "<p>Talvez você procure:</p><ul>" + guess.map(function (r) {
          return '<li><a href="#' + r.e.id + '">' + esc(r.e.p.title) + "</a></li>";
        }).join("") + "</ul>" : "") + "</article>";
      document.title = "Não encontrada · Manual do Framework";
      return;
    }
    var path = pathOf(id);
    var crumbs = '<div class="crumbs">' + path.slice(0, -1).map(function (x) {
      return '<a href="#' + x.id + '">' + esc(x.title) + '</a><span class="sep">›</span>';
    }).join("") + "</div>";
    var title = p.kind === "fn" ? "<code>" + esc(p.title) + "</code>" : esc(p.title);
    var body = p.kind === "fn" ? fnHtml(p) : ((p.lead ? '<p class="lead">' + p.lead + "</p>" : "") + (p.html || ""));
    if (p.kind === "group") body += groupList(p);
    else if (p.kind === "page" && DOCS.children[id]) body += groupList(p);
    var src = p.src ? '<p class="src">Fonte: <code>' + esc(p.src) + "</code></p>" : "";
    var see = p.kind === "fn" && p.fn.see && p.fn.see.length
      ? "<h4>Veja também</h4><div class=\"see\">" + p.fn.see.map(function (s) { return L(s); }).join("") + "</div>" : "";
    var i = FLAT.indexOf(id), prev = FLAT[i - 1], next = FLAT[i + 1];
    var pager = '<nav class="pager">' +
      (prev ? '<a class="prev" href="#' + prev + '"><small>Anterior</small>' + esc(DOCS.pages[prev].title) + "</a>" : "") +
      (next ? '<a class="next" href="#' + next + '"><small>Próxima</small>' + esc(DOCS.pages[next].title) + "</a>" : "") + "</nav>";
    content.innerHTML = '<article class="page">' + crumbs + "<h1>" + title + "</h1>" + src + body + see + pager + "</article>";

    // links automáticos: o texto vira o título da página
    content.querySelectorAll("a[data-auto]").forEach(function (a) {
      var target = DOCS.pages[a.getAttribute("href").slice(1)];
      if (target) a.innerHTML = target.kind === "fn" ? "<code>" + esc(target.title) + "</code>" : esc(target.title);
      else a.classList.add("broken");
    });
    // índice da página (guias longos)
    var h2s = content.querySelectorAll(".page > h2");
    if (p.kind === "page" && h2s.length >= 3) {
      var toc = document.createElement("div");
      toc.className = "toc";
      h2s.forEach(function (h, n) {
        h.id = "s" + n;
        var a = document.createElement("a");
        a.textContent = h.textContent;
        a.href = "javascript:void 0";
        a.addEventListener("click", function () { h.scrollIntoView({ behavior: "smooth", block: "start" }); });
        toc.appendChild(a);
      });
      var anchor = content.querySelector(".lead") || content.querySelector("h1");
      anchor.parentNode.insertBefore(toc, anchor.nextSibling);
    }
    // realce de código e botão de copiar
    content.querySelectorAll("pre.code > code").forEach(function (code) {
      var text = code.textContent;
      code.innerHTML = highlight(text);
      var btn = document.createElement("button");
      btn.className = "copy-btn";
      btn.type = "button";
      btn.textContent = "Copiar";
      btn.addEventListener("click", function () {
        var done = function () { btn.textContent = "Copiado"; setTimeout(function () { btn.textContent = "Copiar"; }, 1200); };
        if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, function () {});
        else {
          var ta = document.createElement("textarea"); ta.value = text; document.body.appendChild(ta); ta.select();
          try { document.execCommand("copy"); done(); } catch (e) {} ta.remove();
        }
      });
      code.parentNode.appendChild(btn);
    });
    if (highlightTerms) { markTerms(content.querySelector(".page"), highlightTerms); highlightTerms = null; }
    document.title = p.title + " · Manual do Framework";
    syncTree(id);
    window.scrollTo(0, 0);
    content.focus({ preventScroll: true });
  }
  function markTerms(root, terms) {
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        var el = n.parentNode;
        if (!n.nodeValue.trim() || el.closest("pre, .crumbs, .pager, h1, .toc, mark")) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      },
    });
    var nodes = [], n, count = 0;
    while ((n = walker.nextNode())) nodes.push(n);
    terms = terms.filter(function (t) { return t.length >= 3; }).sort(function (a, b) { return b.length - a.length; });
    nodes.forEach(function (node) {
      if (count > 40) return;
      var text = node.nodeValue, low = norm(text);
      for (var k = 0; k < terms.length; k++) {
        var i = low.indexOf(terms[k]);
        if (i >= 0) {
          var after = node.splitText(i);
          after.splitText(terms[k].length);
          var mark = document.createElement("mark");
          mark.textContent = after.nodeValue;
          after.parentNode.replaceChild(mark, after);
          count++;
          return;
        }
      }
    });
  }

  // ---------------------------------------------------------------- UI da busca
  function bindSearch() {
    var input = document.getElementById("searchInput");
    var box = document.getElementById("searchResults");
    var active = -1, last = null;
    function close() { box.hidden = true; input.setAttribute("aria-expanded", "false"); active = -1; }
    function show() {
      var q = input.value.trim();
      if (q.length < 2) { close(); return; }
      last = DOCS.search(q);
      var html = "";
      if (last.extra.length) html += '<div class="hint">Também buscando: ' + last.extra.map(esc).join(", ") + "</div>";
      if (!last.results.length) html += '<div class="no-results">Nada encontrado para <b>' + esc(q) + "</b>. Tente outra palavra (ex.: dano, status, empurrar, carta).</div>";
      html += last.results.map(function (r, i) {
        var path = pathOf(r.e.id).slice(0, -1).map(function (x) { return x.title; }).join(" › ");
        var t = r.e.p.kind === "fn" ? "<code>" + esc(r.e.p.title) + "</code>" : esc(r.e.p.title);
        return '<a class="result" role="option" data-i="' + i + '" href="#' + r.e.id + '"><div class="result-title">' + t +
          '</div><div class="result-path">' + esc(path) + '</div><div class="result-snip">' + snippet(r.e, last.terms) + "</div></a>";
      }).join("");
      box.innerHTML = html;
      box.hidden = false;
      input.setAttribute("aria-expanded", "true");
      active = -1;
    }
    function setActive(i) {
      var items = box.querySelectorAll(".result");
      if (!items.length) return;
      active = (i + items.length) % items.length;
      items.forEach(function (el, k) { el.classList.toggle("active", k === active); });
      items[active].scrollIntoView({ block: "nearest" });
    }
    function go(i) {
      if (!last || !last.results[i]) return;
      highlightTerms = last.terms;
      var id = last.results[i].e.id;
      close();
      input.blur();
      if (location.hash.slice(1) === id) render(id); else location.hash = id;
    }
    input.addEventListener("input", show);
    input.addEventListener("focus", function () { if (input.value.trim().length >= 2) show(); });
    input.addEventListener("keydown", function (ev) {
      if (ev.key === "ArrowDown") { ev.preventDefault(); setActive(active + 1); }
      else if (ev.key === "ArrowUp") { ev.preventDefault(); setActive(active - 1); }
      else if (ev.key === "Enter") { ev.preventDefault(); go(active >= 0 ? active : 0); }
      else if (ev.key === "Escape") { close(); input.blur(); }
    });
    box.addEventListener("mousedown", function (ev) {
      var a = ev.target.closest(".result");
      if (a) { ev.preventDefault(); go(+a.getAttribute("data-i")); }
    });
    document.addEventListener("click", function (ev) { if (!ev.target.closest(".search")) close(); });
    document.addEventListener("keydown", function (ev) {
      var typing = /INPUT|TEXTAREA/.test(document.activeElement && document.activeElement.tagName);
      if (!typing && (ev.key === "/" || ((ev.ctrlKey || ev.metaKey) && ev.key.toLowerCase() === "k"))) {
        ev.preventDefault(); input.focus(); input.select();
      }
    });
  }

  // ---------------------------------------------------------------- partida
  DOCS.start = function () {
    loadOpen();
    sortChildren();
    flatten(DOCS.roots);
    buildIndex();
    var tree = document.getElementById("tree");
    tree.innerHTML = treeHtml(DOCS.roots);
    tree.addEventListener("click", function (ev) {
      var tw = ev.target.closest(".twisty");
      if (tw) {
        var li = tw.closest("li"), id = li.getAttribute("data-id");
        li.classList.toggle("open");
        openSet[id] = li.classList.contains("open") || undefined;
        saveOpen();
        return;
      }
      if (ev.target.closest("a") && window.matchMedia("(max-width: 900px)").matches) toggleNav(false);
    });
    document.getElementById("expandAll").addEventListener("click", function () {
      tree.querySelectorAll("li").forEach(function (li) {
        if (DOCS.children[li.getAttribute("data-id")]) { li.classList.add("open"); openSet[li.getAttribute("data-id")] = true; }
      });
      saveOpen();
    });
    document.getElementById("collapseAll").addEventListener("click", function () {
      tree.querySelectorAll("li.open").forEach(function (li) { li.classList.remove("open"); });
      openSet = {};
      saveOpen();
      syncTree(location.hash.slice(1) || "inicio");
    });
    function toggleNav(open) {
      document.body.classList.toggle("nav-open", open);
      document.getElementById("scrim").hidden = !open;
      document.getElementById("menuBtn").setAttribute("aria-expanded", String(open));
    }
    document.getElementById("menuBtn").addEventListener("click", function () {
      toggleNav(!document.body.classList.contains("nav-open"));
    });
    document.getElementById("scrim").addEventListener("click", function () { toggleNav(false); });
    document.getElementById("themeBtn").addEventListener("click", function () {
      var root = document.documentElement;
      var cur = root.getAttribute("data-theme") ||
        (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
      var next = cur === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try { localStorage.setItem("fwdocs-theme", next); } catch (e) {}
    });
    bindSearch();
    function route() { render(decodeURIComponent(location.hash.slice(1)) || "inicio"); }
    window.addEventListener("hashchange", route);
    route();
  };

  // Para validação fora do navegador (node): links quebrados e páginas sem pai
  DOCS.check = function () {
    var problems = [];
    Object.keys(DOCS.pages).forEach(function (id) {
      var p = DOCS.pages[id];
      if (p.parent && !DOCS.pages[p.parent]) problems.push(id + ": pai inexistente " + p.parent);
      var html = (p.html || "") + (p.lead || "") + (p.fn ? [p.fn.desc, p.fn.ret, p.fn.notes, p.fn.exDesc].join(" ") : "");
      (html.match(/href="#([^"]+)"/g) || []).forEach(function (h) {
        var t = h.slice(7, -1);
        if (!DOCS.pages[t]) problems.push(id + ": link para " + t);
      });
      if (p.fn && p.fn.see) p.fn.see.forEach(function (t) { if (!DOCS.pages[t]) problems.push(id + ": veja também " + t); });
    });
    return problems;
  };
})();

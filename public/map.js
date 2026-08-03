/**
 * Yozgat Map — interactive Docker service topology graph.
 */
(function () {
  const NODE_W = 240;
  const NODE_H = 168;
  const GAP_X = 80;
  const GAP_Y = 100;
  const EXTERNAL_W = 160;

  function healthClass(h) {
    const s = (h || "").toLowerCase();
    if (s === "healthy" || s === "ok") return "ok";
    if (s === "warning" || s === "warn") return "warn";
    if (s === "error" || s === "bad") return "bad";
    return "neutral";
  }

  function statusChipClass(status) {
    const s = (status || "").toLowerCase();
    if (s === "running") return "status-running";
    if (s === "starting") return "status-starting";
    if (s === "stopped" || s === "external") return "status-stopped";
    return "status-error";
  }

  function formatBytes(n) {
    if (n == null || n <= 0) return "—";
    if (n >= 1024 * 1024 * 1024) return (n / (1024 * 1024 * 1024)).toFixed(1) + " GiB";
    if (n >= 1024 * 1024) return (n / (1024 * 1024)).toFixed(0) + " MiB";
    if (n >= 1024) return (n / 1024).toFixed(0) + " KiB";
    return n + " B";
  }

  function meterClass(pct) {
    if (pct == null) return "";
    if (pct >= 85) return "bad";
    if (pct >= 65) return "warn";
    return "";
  }

  class YozgatMap {
    constructor(root) {
      this.root = root;
      this.viewport = root.querySelector(".map-viewport");
      this.edgesSvg = root.querySelector(".map-edges");
      this.nodesLayer = root.querySelector(".map-nodes");
      this.minimap = root.querySelector(".map-minimap");
      this.emptyEl = root.querySelector(".map-empty");
      this.loadingEl = root.querySelector(".map-loading");

      this.nodes = [];
      this.edges = [];
      this.positions = new Map();
      this.expanded = new Set();
      this.searchQuery = "";

      this.scale = 1;
      this.panX = 0;
      this.panY = 0;
      this.draggingNode = null;
      this.panning = false;
      this.lastPointer = null;

      this.bindViewport();
    }

    bindViewport() {
      this.viewport.addEventListener("wheel", (e) => this.onWheel(e), { passive: false });
      this.viewport.addEventListener("pointerdown", (e) => this.onPointerDown(e));
      window.addEventListener("pointermove", (e) => this.onPointerMove(e));
      window.addEventListener("pointerup", () => this.onPointerUp());
    }

    setData(nodes, edges) {
      this.nodes = nodes || [];
      this.edges = edges || [];
      this.positions.clear();
      this.autoLayout();
      this.render();
    }

    setLoading(on) {
      if (this.loadingEl) this.loadingEl.hidden = !on;
    }

    autoLayout() {
      const byTier = new Map();
      for (const n of this.nodes) {
        const t = n.tier != null ? n.tier : 2;
        if (!byTier.has(t)) byTier.set(t, []);
        byTier.get(t).push(n);
      }

      const tiers = Array.from(byTier.keys()).sort((a, b) => a - b);
      let y = 40;

      for (const tier of tiers) {
        const row = byTier.get(tier);
        row.sort((a, b) => a.name.localeCompare(b.name));
        const rowWidth = row.reduce((sum, n) => sum + (n.kind === "external" ? EXTERNAL_W : NODE_W) + GAP_X, -GAP_X);
        let x = Math.max(40, (2400 - rowWidth) / 2);

        for (const n of row) {
          const w = n.kind === "external" ? EXTERNAL_W : NODE_W;
          this.positions.set(n.id, { x, y, w, h: n.kind === "external" ? 72 : NODE_H });
          x += w + GAP_X;
        }
        y += NODE_H + GAP_Y;
      }
    }

    fitView() {
      if (!this.nodes.length) return;
      let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
      for (const [id, p] of this.positions) {
        minX = Math.min(minX, p.x);
        minY = Math.min(minY, p.y);
        maxX = Math.max(maxX, p.x + p.w);
        maxY = Math.max(maxY, p.y + p.h);
      }

      const pad = 60;
      const rect = this.viewport.getBoundingClientRect();
      const graphW = maxX - minX + pad * 2;
      const graphH = maxY - minY + pad * 2;
      this.scale = Math.min(rect.width / graphW, rect.height / graphH, 1.2);
      this.panX = (rect.width - graphW * this.scale) / 2 - (minX - pad) * this.scale;
      this.panY = (rect.height - graphH * this.scale) / 2 - (minY - pad) * this.scale;
      this.applyTransform();
      this.drawEdges();
      this.drawMinimap();
    }

    setSearch(q) {
      this.searchQuery = (q || "").trim().toLowerCase();
      this.renderNodes();
      this.drawEdges();
    }

    refresh() {
      this.renderNodes();
      this.drawEdges();
      this.drawMinimap();
    }

    updateStats(nodes, edges) {
      this.nodes = nodes || [];
      this.edges = edges || [];
      this.renderNodes();
      this.drawEdges();
    }

    applyTransform() {
      const t = `translate(${this.panX}px, ${this.panY}px) scale(${this.scale})`;
      this.nodesLayer.style.transform = t;
      this.edgesSvg.style.transform = t;
    }

    render() {
      if (this.emptyEl) {
        this.emptyEl.hidden = this.nodes.some((n) => n.kind === "service");
      }
      this.renderNodes();
      this.drawEdges();
      this.drawMinimap();
      requestAnimationFrame(() => this.fitView());
    }

    renderNodes() {
      this.nodesLayer.innerHTML = "";
      for (const n of this.nodes) {
        if (n.kind === "external") continue;
        this.nodesLayer.appendChild(this.createNodeEl(n));
      }
      for (const n of this.nodes) {
        if (n.kind !== "external") continue;
        this.nodesLayer.appendChild(this.createNodeEl(n));
      }
    }

    createNodeEl(n) {
      const pos = this.positions.get(n.id) || { x: 0, y: 0, w: NODE_W, h: NODE_H };
      const el = document.createElement("div");
      el.className = "map-node" + (n.kind === "external" ? " external" : "");
      el.dataset.id = n.id;
      el.style.transform = `translate(${pos.x}px, ${pos.y}px)`;
      el.style.width = pos.w + "px";

      const q = this.searchQuery;
      const match =
        !q ||
        n.name.toLowerCase().includes(q) ||
        (n.image && n.image.toLowerCase().includes(q));
      if (q && !match) el.classList.add("is-dimmed");
      if (q && match) el.classList.add("is-highlight");

      const cpu = n.cpuPercent != null ? n.cpuPercent.toFixed(1) : null;
      const mem = n.memoryPercent != null ? n.memoryPercent.toFixed(1) : null;
      const replicas = n.replicas > 1 ? n.replicas + " replicas" : null;

      el.innerHTML =
        '<div class="map-node-card">' +
        '<div class="map-node-header">' +
        '<div><div class="map-node-title">' + escapeHtml(n.name) + "</div>" +
        (n.image ? '<div class="map-node-image">' + escapeHtml(shortImage(n.image)) + "</div>" : "") +
        "</div>" +
        '<span class="health-dot ' + healthClass(n.health) + '" title="' + escapeHtml(n.health || "") + '"></span>' +
        "</div>" +
        '<div class="map-node-meta">' +
        '<span class="map-chip ' + statusChipClass(n.status) + '">' + escapeHtml(n.status) + "</span>" +
        (replicas ? '<span class="map-chip">' + escapeHtml(replicas) + "</span>" : "") +
        (n.deployedAt ? '<span class="map-chip">' + escapeHtml(relativeTime(n.deployedAt)) + "</span>" : "") +
        "</div>" +
        (cpu != null
          ? meterHtml("CPU", cpu, n.cpuPercent)
          : "") +
        (mem != null
          ? meterHtml("Memory", mem, n.memoryPercent)
          : "") +
        (n.ports && n.ports.length
          ? '<div class="map-node-ports">' + escapeHtml(n.ports.slice(0, 3).join(" · ")) + "</div>"
          : "") +
        (n.containers && n.containers.length > 1
          ? containerExpandHtml(n)
          : "") +
        "</div>";

      el.addEventListener("pointerdown", (e) => this.startNodeDrag(e, n.id));
      return el;
    }

    startNodeDrag(e, id) {
      if (e.button !== 0) return;
      e.stopPropagation();
      this.draggingNode = id;
      this.lastPointer = { x: e.clientX, y: e.clientY };
      const el = this.nodesLayer.querySelector('[data-id="' + id + '"]');
      if (el) el.classList.add("is-dragging");
      this.viewport.setPointerCapture(e.pointerId);
    }

    onPointerDown(e) {
      if (this.draggingNode) return;
      if (e.target.closest(".map-node")) return;
      this.panning = true;
      this.lastPointer = { x: e.clientX, y: e.clientY };
      this.viewport.classList.add("is-panning");
    }

    onPointerMove(e) {
      if (!this.lastPointer) return;
      const dx = e.clientX - this.lastPointer.x;
      const dy = e.clientY - this.lastPointer.y;
      this.lastPointer = { x: e.clientX, y: e.clientY };

      if (this.draggingNode) {
        const pos = this.positions.get(this.draggingNode);
        if (pos) {
          pos.x += dx / this.scale;
          pos.y += dy / this.scale;
          const el = this.nodesLayer.querySelector('[data-id="' + this.draggingNode + '"]');
          if (el) el.style.transform = "translate(" + pos.x + "px, " + pos.y + "px)";
          this.drawEdges();
          this.drawMinimap();
        }
        return;
      }

      if (this.panning) {
        this.panX += dx;
        this.panY += dy;
        this.applyTransform();
        this.drawMinimap();
      }
    }

    onPointerUp() {
      if (this.draggingNode) {
        const el = this.nodesLayer.querySelector('[data-id="' + this.draggingNode + '"]');
        if (el) el.classList.remove("is-dragging");
      }
      this.draggingNode = null;
      this.panning = false;
      this.lastPointer = null;
      this.viewport.classList.remove("is-panning");
    }

    onWheel(e) {
      e.preventDefault();
      const rect = this.viewport.getBoundingClientRect();
      const mx = e.clientX - rect.left;
      const my = e.clientY - rect.top;
      const prev = this.scale;
      const factor = e.deltaY < 0 ? 1.08 : 1 / 1.08;
      this.scale = Math.min(2.5, Math.max(0.25, this.scale * factor));
      this.panX = mx - ((mx - this.panX) * this.scale) / prev;
      this.panY = my - ((my - this.panY) * this.scale) / prev;
      this.applyTransform();
      this.drawMinimap();
    }

    drawEdges() {
      const svg = this.edgesSvg;
      while (svg.firstChild) svg.removeChild(svg.firstChild);

      const q = this.searchQuery;
      const highlightIds = new Set();
      if (q) {
        for (const n of this.nodes) {
          if (
            n.name.toLowerCase().includes(q) ||
            (n.image && n.image.toLowerCase().includes(q))
          ) {
            highlightIds.add(n.id);
          }
        }
      }

      for (const edge of this.edges) {
        const from = this.positions.get(edge.from);
        const to = this.positions.get(edge.to);
        if (!from || !to) continue;

        const x1 = from.x + from.w / 2;
        const y1 = from.y + from.h;
        const x2 = to.x + to.w / 2;
        const y2 = to.y;

        const midY = y1 + (y2 - y1) / 2;
        const d = "M" + x1 + " " + y1 + " L" + x1 + " " + midY + " L" + x2 + " " + midY + " L" + x2 + " " + y2;

        const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
        path.setAttribute("d", d);
        if (q && (highlightIds.has(edge.from) || highlightIds.has(edge.to))) {
          path.classList.add("highlight");
        }
        svg.appendChild(path);
      }
    }

    drawMinimap() {
      if (!this.minimap) return;
      this.minimap.innerHTML = "";

      let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
      for (const p of this.positions.values()) {
        minX = Math.min(minX, p.x);
        minY = Math.min(minY, p.y);
        maxX = Math.max(maxX, p.x + p.w);
        maxY = Math.max(maxY, p.y + p.h);
      }
      if (!isFinite(minX)) return;

      const mw = this.minimap.clientWidth;
      const mh = this.minimap.clientHeight;
      const gw = maxX - minX + 40;
      const gh = maxY - minY + 40;
      const s = Math.min(mw / gw, mh / gh);

      for (const n of this.nodes) {
        if (n.kind === "external") continue;
        const p = this.positions.get(n.id);
        if (!p) continue;
        const dot = document.createElement("div");
        dot.className = "map-minimap-node";
        dot.style.left = (p.x - minX + 20) * s + "px";
        dot.style.top = (p.y - minY + 20) * s + "px";
        dot.style.width = Math.max(4, p.w * s * 0.25) + "px";
        dot.style.height = Math.max(3, 8) + "px";
        this.minimap.appendChild(dot);
      }

      const rect = this.viewport.getBoundingClientRect();
      const vx = (-this.panX / this.scale + minX - 20) * s;
      const vy = (-this.panY / this.scale + minY - 20) * s;
      const vw = (rect.width / this.scale) * s;
      const vh = (rect.height / this.scale) * s;

      const vp = document.createElement("div");
      vp.className = "map-minimap-viewport";
      vp.style.left = vx + "px";
      vp.style.top = vy + "px";
      vp.style.width = vw + "px";
      vp.style.height = vh + "px";
      this.minimap.appendChild(vp);
    }
  }

  function meterHtml(label, text, pct) {
    return (
      '<div class="map-meter">' +
      '<div class="map-meter-label"><span>' + label + '</span><span>' + text + "%</span></div>" +
      '<div class="map-meter-bar"><div class="map-meter-fill ' +
      meterClass(pct) +
      '" style="width:' +
      Math.min(100, Math.max(0, pct)) +
      '%"></div></div></div>'
    );
  }

  function containerExpandHtml(n) {
    let rows = "";
    for (const c of n.containers) {
      rows +=
        '<div class="map-container-row"><span>' +
        escapeHtml(c.name) +
        '</span><span class="health-dot ' +
        healthClass(c.health) +
        '"></span></div>';
    }
    return (
      '<details class="map-node-expand"><summary>Containers (' +
      n.containers.length +
      ")</summary><div class=\"map-container-list\">" +
      rows +
      "</div></details>"
    );
  }

  function shortImage(img) {
    if (!img) return "";
    const parts = img.split("/");
    const last = parts[parts.length - 1];
    return last.length > 42 ? last.slice(0, 40) + "…" : last;
  }

  function relativeTime(iso) {
    try {
      const d = new Date(iso.includes("T") ? iso : iso.replace(" ", "T") + "Z");
      const sec = (Date.now() - d.getTime()) / 1000;
      if (sec < 60) return "just now";
      if (sec < 3600) return Math.floor(sec / 60) + "m ago";
      if (sec < 86400) return Math.floor(sec / 3600) + "h ago";
      return Math.floor(sec / 86400) + "d ago";
    } catch {
      return iso;
    }
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  window.YozgatMap = YozgatMap;
})();

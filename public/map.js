/**
 * Yozgat Map — global Docker service topology graph.
 *
 * Renders every project and environment as a hierarchy of boxes:
 * project band → environment box → service cards. Services flow
 * horizontally left-to-right (Internet → Proxy → Services → Databases).
 * View-only: no node drag, wheel zoom + pan + fit view + minimap remain.
 */
(function () {
  const NODE_W = 240;
  const NODE_H = 148;
  const GAP_X = 56;
  const GAP_Y = 28;
  const EXTERNAL_W = 150;
  const EXTERNAL_H = 64;
  const ENV_PAD = 24;
  const ENV_HEADER = 32;
  const CAPTION_H = 14;
  const ENV_GAP = 32;
  const PROJ_LEFT = 24;
  const PROJ_PAD = 20;
  const PROJ_HEADER = 60;
  const PROJ_GAP = 56;

  const SVG_NS = "http://www.w3.org/2000/svg";

  const CLOUD_ICON =
    '<svg viewBox="0 0 24 24" class="map-external-icon" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z"/></svg>';

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

  function meterClass(pct) {
    if (pct == null) return "";
    if (pct >= 85) return "bad";
    if (pct >= 65) return "warn";
    return "";
  }

  function edgeLabel(kind) {
    if (kind === "ingress") return "HTTP/HTTPS";
    if (kind === "proxy") return "TCP";
    if (kind === "depends_on") return "Depends On";
    return "Internal Network";
  }

  function tierCaption(tier) {
    if (tier == null || tier <= 0) return "";
    if (tier === 1) return "Proxy";
    if (tier === 4) return "Data";
    return "Services";
  }

  function needsDot(h) {
    const s = (h || "").toLowerCase();
    return s === "warning" || s === "warn" || s === "error" || s === "bad";
  }

  // Orthogonal route between two points. Left-to-right edges bend at the
  // midpoint horizontally; backwards edges bend vertically instead.
  function orthogonalPoints(x1, y1, x2, y2) {
    if (x2 >= x1) {
      const midX = x1 + (x2 - x1) / 2;
      return [[x1, y1], [midX, y1], [midX, y2], [x2, y2]];
    }
    const midY = y1 + (y2 - y1) / 2;
    return [[x1, y1], [x1, midY], [x2, midY], [x2, y2]];
  }

  function pathFromPoints(pts) {
    return pts
      .map((p, i) => (i === 0 ? "M" : "L") + p[0] + " " + p[1])
      .join(" ");
  }

  class YozgatMap {
    constructor(root) {
      this.root = root;
      const wrap = root.closest(".map-viewport-wrap") || root;
      this.viewport = root.classList.contains("map-viewport") ? root : root.querySelector(".map-viewport");
      this.edgesSvg = this.viewport.querySelector(".map-edges");
      this.nodesLayer = this.viewport.querySelector(".map-nodes");
      this.minimap = wrap.querySelector(".map-minimap");
      this.emptyEl = wrap.querySelector(".map-empty");
      this.loadingEl = wrap.querySelector(".map-loading");

      this.projects = [];
      this.layout = null; // { projects: [{ left, top, width, height, envs: [...] }] }
      this.positions = new Map();
      this.measuredHeights = new Map();
      this.projectRects = [];
      this.envRects = [];
      this.globalEdges = [];
      this.searchQuery = "";

      this.scale = 1;
      this.panX = 0;
      this.panY = 0;
      this.panning = false;
      this.lastPointer = null;

      this.minimapScale = 0;
      this.minimapMinX = 0;
      this.minimapMinY = 0;
      this.minimapDragging = false;

      this.bindViewport();
      this.bindMinimap();
    }

    bindViewport() {
      this.viewport.addEventListener("wheel", (e) => this.onWheel(e), { passive: false });
      this.viewport.addEventListener("pointerdown", (e) => this.onPointerDown(e));
      window.addEventListener("pointermove", (e) => this.onPointerMove(e));
      window.addEventListener("pointerup", () => this.onPointerUp());
    }

    bindMinimap() {
      if (!this.minimap) return;
      this.minimap.addEventListener("pointerdown", (e) => this.onMinimapPointer(e));
      window.addEventListener("pointermove", (e) => {
        if (this.minimapDragging) this.onMinimapPointer(e);
      });
      window.addEventListener("pointerup", () => {
        this.minimapDragging = false;
      });
    }

    setHierarchy(projects) {
      this.projects = projects || [];
      this.computeLayout();
      this.renderNodes();
      this.measureHeights();
      this.computeLayout();
      this.render();
    }

    updateHierarchy(projects) {
      this.projects = projects || [];
      this.computeLayout();
      this.renderNodes();
      this.measureHeights();
      this.computeLayout();
      this.renderNodes();
      this.drawEdges();
      this.drawMinimap();
    }

    // After a first render pass, read the real content height of every
    // rendered card so the second layout pass uses measured heights instead
    // of the fixed NODE_H estimate (cards are content-driven).
    measureHeights() {
      this.measuredHeights.clear();
      for (const node of this.nodesLayer.querySelectorAll(".map-node")) {
        const id = node.dataset.id;
        if (id) this.measuredHeights.set(id, node.offsetHeight);
      }
    }

    setLoading(on) {
      const el = this.loadingEl || document.getElementById("map-loading");
      if (!el) return;
      el.hidden = !on;
      el.style.display = on ? "flex" : "none";
    }

    computeLayout() {
      this.positions.clear();
      this.projectRects = [];
      this.envRects = [];
      this.globalEdges = [];
      const projects = [];
      let projTop = PROJ_PAD;

      for (const project of this.projects) {
        const envs = [];
        let maxEnvH = 0;
        let envRowW = 0;

        for (const env of project.environments || []) {
          const l = this.layoutEnv(project, env);
          envs.push(l);
          maxEnvH = Math.max(maxEnvH, l.height);
          envRowW += l.width + ENV_GAP;
        }
        envRowW = Math.max(0, envRowW - ENV_GAP);

        // Project wraps its environments tightly; no fixed minimum width.
        const width = Math.max(PROJ_PAD * 2 + envRowW, 220);
        const height = PROJ_HEADER + maxEnvH + PROJ_PAD;
        const envLeft = Math.max(PROJ_PAD, (width - envRowW) / 2);

        let envX = envLeft;
        for (const l of envs) {
          l.left = envX;
          l.top = PROJ_HEADER;

          this.envRects.push({
            x: PROJ_LEFT + envX,
            y: projTop + l.top,
            w: l.width,
            h: l.height,
          });

          for (const e of l.edges) this.globalEdges.push(e);

          for (const n of l.nodes) {
            const p = l.positions.get(n.__scope + n.id);
            if (!p) continue;
            this.positions.set(n.__scope + n.id, {
              x: PROJ_LEFT + envX + p.x,
              y: projTop + l.top + p.y,
              w: p.w,
              h: p.h,
            });
          }

          envX += l.width + ENV_GAP;
        }

        this.projectRects.push({ x: PROJ_LEFT, y: projTop, w: width, h: height });
        projects.push({ left: PROJ_LEFT, top: projTop, width, height, envs, source: project });
        projTop += height + PROJ_GAP;
      }

      this.layout = { projects };
    }

    // Layout one environment as a horizontal execution flow. Tiers become
    // columns ordered left-to-right (0=Internet, 1=Proxy, 2/3=Services,
    // 4=Databases); nodes inside a column stack vertically. Columns are
    // vertically centered within the tallest column so the Internet card
    // sits beside the service stack instead of leaving a lower-left void.
    layoutEnv(project, env) {
      const prefix = "p" + project.id + "e" + env.id + ":";
      const nodes = (env.nodes || []).slice();

      const nodeIds = new Set();
      for (const n of nodes) {
        n.__scope = prefix;
        nodeIds.add(prefix + n.id);
      }

      const edges = [];
      for (const e of env.edges || []) {
        const from = prefix + e.from;
        const to = prefix + e.to;
        if (nodeIds.has(from) && nodeIds.has(to)) edges.push({ from, to, kind: e.kind });
      }

      const byTier = new Map();
      for (const n of nodes) {
        const t = n.tier != null ? n.tier : 2;
        if (!byTier.has(t)) byTier.set(t, []);
        byTier.get(t).push(n);
      }

      const tiers = Array.from(byTier.keys()).sort((a, b) => a - b);
      const positions = new Map();
      const colHeights = new Map();
      const colWidths = new Map();

      for (const tier of tiers) {
        const col = byTier.get(tier);
        col.sort((a, b) => a.name.localeCompare(b.name));
        let colW = 0;
        let colH = 0;
        for (const n of col) {
          const w = n.kind === "external" ? EXTERNAL_W : NODE_W;
          const h = this.cardHeight(n, prefix);
          colW = Math.max(colW, w);
          colH += h + GAP_Y;
        }
        colHeights.set(tier, Math.max(0, colH - GAP_Y));
        colWidths.set(tier, colW);
      }

      let maxColH = 0;
      for (const h of colHeights.values()) maxColH = Math.max(maxColH, h);
      const yBase = ENV_HEADER + CAPTION_H;

      let x = ENV_PAD;
      let envW = ENV_PAD;
      const tierCols = [];
      for (const tier of tiers) {
        const col = byTier.get(tier);
        const colW = colWidths.get(tier);
        const colH = colHeights.get(tier);
        const yOff = (maxColH - colH) / 2;
        let y = yBase + yOff;
        for (const n of col) {
          const w = n.kind === "external" ? EXTERNAL_W : NODE_W;
          const h = this.cardHeight(n, prefix);
          positions.set(prefix + n.id, { x, y, w, h });
          y += h + GAP_Y;
        }
        tierCols.push({ tier, x, w: colW, top: yBase + yOff });
        envW = x + colW;
        x += colW + GAP_X;
      }

      return {
        env,
        prefix,
        nodes,
        edges,
        tierCols,
        positions,
        width: Math.max(envW + ENV_PAD, ENV_PAD * 2 + 120),
        height: Math.max(yBase + maxColH + ENV_PAD, ENV_HEADER + CAPTION_H + 24),
      };
    }

    // Height of a single card: measured value when available, otherwise the
    // fixed estimate for the node kind.
    cardHeight(n, prefix) {
      const measured = this.measuredHeights.get(prefix + n.id);
      if (measured != null) return measured;
      return n.kind === "external" ? EXTERNAL_H : NODE_H;
    }

    fitView() {
      if (!this.positions.size) return;
      let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
      for (const p of this.positions.values()) {
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

    matchesSearch(str) {
      return String(str || "").toLowerCase().includes(this.searchQuery);
    }

    envMatch(project, env) {
      if (!this.searchQuery) return true;
      if (!project) return false;
      return (
        this.matchesSearch(project.name) ||
        this.matchesSearch(project.projectType) ||
        this.matchesSearch(env.name) ||
        this.matchesSearch(env.slug)
      );
    }

    applyTransform() {
      const t = `translate(${this.panX}px, ${this.panY}px) scale(${this.scale})`;
      this.nodesLayer.style.transform = t;
      this.edgesSvg.style.transform = t;
    }

    render() {
      const hasServices = this.projects.some((p) =>
        (p.environments || []).some((e) => (e.nodes || []).some((n) => n.kind !== "external"))
      );
      if (this.emptyEl) this.emptyEl.hidden = hasServices;
      this.renderNodes();
      this.drawEdges();
      this.drawMinimap();
      requestAnimationFrame(() => this.fitView());
    }

    renderNodes() {
      this.nodesLayer.innerHTML = "";
      if (!this.layout) return;

      for (const proj of this.layout.projects) {
        const band = this.createProjectBand(proj);
        this.nodesLayer.appendChild(band);
      }
    }

    createProjectBand(proj) {
      const el = document.createElement("div");
      el.className = "map-project";
      el.style.left = proj.left + "px";
      el.style.top = proj.top + "px";
      el.style.width = proj.width + "px";
      el.style.height = proj.height + "px";

      const source = proj.source;
      const envCount = proj.envs.length;
      const meta = source
        ? '<div class="map-project-meta">' +
          escapeHtml(envCount + (envCount === 1 ? " environment" : " environments")) +
          (source.projectType ? " · " + escapeHtml(source.projectType) : "") +
          "</div>"
        : "";
      const header = document.createElement("div");
      header.className = "map-project-header";
      header.innerHTML =
        '<div class="map-project-titles">' +
        "<strong>" + escapeHtml(source ? source.name : "Project") + "</strong>" +
        meta +
        "</div>" +
        (source
          ? '<span class="status-pill ' + statusClass(source.status) + '">' + escapeHtml(source.status) + "</span>"
          : "");
      el.appendChild(header);

      for (const env of proj.envs) {
        el.appendChild(this.createEnvBox(env, source));
      }

      return el;
    }

    createEnvBox(env, source) {
      const box = document.createElement("div");
      box.className = "map-env";
      box.dataset.prefix = env.prefix;
      box.style.left = env.left + "px";
      box.style.top = env.top + "px";
      box.style.width = env.width + "px";
      box.style.height = env.height + "px";

      const envMatch = this.searchQuery ? this.envMatch(source, env.env) : true;
      if (this.searchQuery && !envMatch) box.classList.add("is-dimmed");

      const port = env.env && env.env.hostPort != null ? " · :" + env.env.hostPort : "";
      const title = env.env ? env.env.name + " (" + env.env.slug + ")" + port : "";
      const header = document.createElement("div");
      header.className = "map-env-header";
      header.textContent = title;
      box.appendChild(header);

      const svg = document.createElementNS(SVG_NS, "svg");
      svg.setAttribute("class", "map-env-edges");
      svg.setAttribute("width", env.width);
      svg.setAttribute("height", env.height);
      box.appendChild(svg);

      const nodesEl = document.createElement("div");
      nodesEl.className = "map-env-nodes";
      for (const n of env.nodes) {
        const pos = env.positions.get(env.prefix + n.id);
        if (!pos) continue;
        nodesEl.appendChild(this.createNodeEl(n, pos, envMatch));
      }
      box.appendChild(nodesEl);

      return box;
    }

    createNodeEl(n, pos, envMatch) {
      const el = document.createElement("div");
      el.className = "map-node" + (n.kind === "external" ? " external" : "");
      el.dataset.id = n.__scope + n.id;
      el.style.transform = `translate(${pos.x}px, ${pos.y}px)`;
      el.style.width = pos.w + "px";

      const q = this.searchQuery;
      const nodeMatch =
        !q ||
        this.matchesSearch(n.name) ||
        (n.image && this.matchesSearch(n.image));
      if (q && !envMatch && !nodeMatch) el.classList.add("is-dimmed");
      if (q && (nodeMatch || envMatch)) el.classList.add("is-highlight");

      // External node: cloud icon only (Internet).
      if (n.kind === "external") {
        el.innerHTML =
          '<div class="map-node-card">' +
          '<div class="map-external-icon">' + CLOUD_ICON + "</div>" +
          '<div class="map-node-title">' + escapeHtml(n.name) + "</div>" +
          "</div>";
        return el;
      }

      const cpu = n.cpuPercent != null ? n.cpuPercent.toFixed(1) : null;
      const mem = n.memoryPercent != null ? n.memoryPercent.toFixed(1) : null;

      el.innerHTML =
        '<div class="map-node-card">' +
        '<div class="map-node-header">' +
        '<div class="map-node-title">' + escapeHtml(n.name) + "</div>" +
        (needsDot(n.health)
          ? '<span class="health-dot ' + healthClass(n.health) + '" title="' + escapeHtml(n.health || "") + '"></span>'
          : "") +
        "</div>" +
        '<div class="map-node-meta">' +
        '<span class="map-chip ' + statusChipClass(n.status) + '">' + escapeHtml(n.status) + "</span>" +
        "</div>" +
        (cpu != null ? meterHtml("CPU", cpu, n.cpuPercent) : "") +
        (mem != null ? meterHtml("Memory", mem, n.memoryPercent) : "") +
        (n.ports && n.ports.length
          ? '<div class="map-node-ports">' + escapeHtml(n.ports.slice(0, 3).join(" · ")) + "</div>"
          : "") +
        "</div>";

      return el;
    }

    onPointerDown(e) {
      if (e.target.closest(".map-node") || e.target.closest(".map-env-header")) return;
      this.panning = true;
      this.lastPointer = { x: e.clientX, y: e.clientY };
      this.viewport.classList.add("is-panning");
    }

    onPointerMove(e) {
      if (!this.lastPointer) return;
      const dx = e.clientX - this.lastPointer.x;
      const dy = e.clientY - this.lastPointer.y;
      this.lastPointer = { x: e.clientX, y: e.clientY };

      if (this.panning) {
        this.panX += dx;
        this.panY += dy;
        this.applyTransform();
        this.drawMinimap();
      }
    }

    onPointerUp() {
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
      if (!this.layout) return;
      for (const proj of this.layout.projects) {
        for (const env of proj.envs) {
          const svg = this.nodesLayer.querySelector(
            '.map-env[data-prefix="' + env.prefix + '"] .map-env-edges'
          );
          if (!svg) continue;
          while (svg.firstChild) svg.removeChild(svg.firstChild);

          const q = this.searchQuery;
          const highlightIds = new Set();
          if (q) {
            for (const n of env.nodes) {
              if (this.matchesSearch(n.name) || (n.image && this.matchesSearch(n.image))) {
                highlightIds.add(env.prefix + n.id);
              }
            }
          }

          // Tier captions above each column (Proxy / Services / Data).
          for (const tc of env.tierCols || []) {
            const label = tierCaption(tc.tier);
            if (!label) continue;
            const text = document.createElementNS(SVG_NS, "text");
            text.setAttribute("class", "map-tier-caption");
            text.setAttribute("x", tc.x + tc.w / 2);
            text.setAttribute("y", Math.max(9, tc.top - 7));
            text.setAttribute("text-anchor", "middle");
            text.textContent = label;
            svg.appendChild(text);
          }

          for (const edge of env.edges) {
            const from = env.positions.get(edge.from);
            const to = env.positions.get(edge.to);
            if (!from || !to) continue;

            // Connect the right edge of `from` to the left edge of `to`.
            const x1 = from.x + from.w;
            const y1 = from.y + from.h / 2;
            const x2 = to.x;
            const y2 = to.y + to.h / 2;

            const pts = orthogonalPoints(x1, y1, x2, y2);
            const d = pathFromPoints(pts);

            const path = document.createElementNS(SVG_NS, "path");
            path.setAttribute("d", d);
            path.setAttribute("stroke-linejoin", "round");
            path.setAttribute("stroke-linecap", "round");
            if (q && (highlightIds.has(edge.from) || highlightIds.has(edge.to))) {
              path.classList.add("highlight");
            }
            svg.appendChild(path);

            // Label above the horizontal run for forward edges; beside the
            // vertical run for backwards edges. Skip when the run is too
            // short for the label to fit.
            const run = x2 - x1;
            if (run < 48 && run >= 0) continue;
            const text = document.createElementNS(SVG_NS, "text");
            text.setAttribute("class", "map-edge-label");
            text.setAttribute("text-anchor", "middle");
            if (run >= 0) {
              text.setAttribute("x", x1 + Math.min(run / 2, 44));
              text.setAttribute("y", Math.max(9, y1 - 6));
            } else {
              text.setAttribute("x", x1 + (x2 - x1) / 2);
              text.setAttribute("y", Math.max(9, y1 + (y2 - y1) / 2 - 5));
            }
            text.textContent = edgeLabel(edge.kind);
            svg.appendChild(text);
          }
        }
      }
    }

    drawMinimap() {
      if (!this.minimap) return;
      this.minimap.innerHTML = "";
      if (!this.projectRects.length) return;

      let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
      for (const p of this.projectRects) {
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

      this.minimapScale = s;
      this.minimapMinX = minX - 20;
      this.minimapMinY = minY - 20;

      // Simplified connection lines first (under everything else).
      const svg = document.createElementNS(SVG_NS, "svg");
      svg.setAttribute("class", "map-minimap-svg");
      this.minimap.appendChild(svg);
      for (const e of this.globalEdges) {
        const a = this.positions.get(e.from);
        const b = this.positions.get(e.to);
        if (!a || !b) continue;
        const line = document.createElementNS(SVG_NS, "line");
        line.setAttribute("x1", ((a.x + a.w / 2) - minX + 20) * s);
        line.setAttribute("y1", ((a.y + a.h / 2) - minY + 20) * s);
        line.setAttribute("x2", ((b.x + b.w / 2) - minX + 20) * s);
        line.setAttribute("y2", ((b.y + b.h / 2) - minY + 20) * s);
        line.setAttribute("class", "map-minimap-line");
        svg.appendChild(line);
      }

      for (const p of this.projectRects) {
        const el = document.createElement("div");
        el.className = "map-minimap-project";
        el.style.left = (p.x - minX + 20) * s + "px";
        el.style.top = (p.y - minY + 20) * s + "px";
        el.style.width = Math.max(1, p.w * s) + "px";
        el.style.height = Math.max(1, p.h * s) + "px";
        this.minimap.appendChild(el);
      }

      for (const p of this.envRects) {
        const el = document.createElement("div");
        el.className = "map-minimap-env";
        el.style.left = (p.x - minX + 20) * s + "px";
        el.style.top = (p.y - minY + 20) * s + "px";
        el.style.width = Math.max(1, p.w * s) + "px";
        el.style.height = Math.max(1, p.h * s) + "px";
        this.minimap.appendChild(el);
      }

      for (const p of this.positions.values()) {
        const dot = document.createElement("div");
        dot.className = "map-minimap-node";
        dot.style.left = (p.x - minX + 20) * s + "px";
        dot.style.top = (p.y - minY + 20) * s + "px";
        dot.style.width = Math.max(2, p.w * s * 0.35) + "px";
        dot.style.height = Math.max(2, 6) + "px";
        this.minimap.appendChild(dot);
      }

      const rect = this.viewport.getBoundingClientRect();
      const vx = (-this.panX / this.scale - minX + 20) * s;
      const vy = (-this.panY / this.scale - minY + 20) * s;
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

    // Clicking or dragging inside the minimap moves the main canvas so the
    // pointer location becomes the centre of the viewport (zoom is kept).
    onMinimapPointer(e) {
      if (!this.minimapScale || !this.scale) return;
      this.minimapDragging = true;
      if (e.preventDefault) e.preventDefault();

      const rect = this.minimap.getBoundingClientRect();
      const mx = e.clientX - rect.left;
      const my = e.clientY - rect.top;
      const gx = mx / this.minimapScale + this.minimapMinX;
      const gy = my / this.minimapScale + this.minimapMinY;

      const vr = this.viewport.getBoundingClientRect();
      this.panX = vr.width / 2 - gx * this.scale;
      this.panY = vr.height / 2 - gy * this.scale;
      this.applyTransform();
      this.drawMinimap();
    }
  }

  function meterHtml(label, text, pct) {
    // Tiny values make a 5px bar invisible; render label-only instead.
    const tiny = pct != null && pct < 2;
    return (
      '<div class="map-meter">' +
      '<div class="map-meter-label"><span>' + label + '</span><span>' + text + "%</span></div>" +
      (tiny
        ? ""
        : '<div class="map-meter-bar"><div class="map-meter-fill ' +
          meterClass(pct) +
          '" style="width:' +
          Math.min(100, Math.max(0, pct)) +
          '%"></div></div>') +
      "</div>"
    );
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

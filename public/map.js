/**
 * Yozgat Map — global Docker service topology graph.
 *
 * Renders every project and environment as a hierarchy of boxes:
 * project band → environment box → service cards. View-only: no node drag,
 * wheel zoom + pan + fit view + minimap remain.
 */
(function () {
  const NODE_W = 240;
  const NODE_H = 168;
  const GAP_X = 60;
  const GAP_Y = 80;
  const EXTERNAL_W = 160;
  const ENV_PAD = 24;
  const ENV_HEADER = 36;
  const ENV_GAP = 40;
  const PROJ_PAD = 20;
  const PROJ_HEADER = 42;
  const PROJ_GAP = 56;

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
      this.searchQuery = "";

      this.scale = 1;
      this.panX = 0;
      this.panY = 0;
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

    setHierarchy(projects) {
      this.projects = projects || [];
      this.computeLayout();
      this.render();
    }

    updateHierarchy(projects) {
      this.projects = projects || [];
      this.computeLayout();
      this.renderNodes();
      this.drawEdges();
      this.drawMinimap();
    }

    setLoading(on) {
      const el = this.loadingEl || document.getElementById("map-loading");
      if (!el) return;
      el.hidden = !on;
      el.style.display = on ? "flex" : "none";
    }

    computeLayout() {
      this.positions.clear();
      const projects = [];
      let projTop = PROJ_PAD;

      for (const project of this.projects) {
        const envs = [];
        let maxEnvH = 0;
        let envRowW = 0;

        for (const env of project.environments) {
          const l = this.layoutEnv(project, env);
          envs.push(l);
          maxEnvH = Math.max(maxEnvH, l.height);
          envRowW += l.width + ENV_GAP;
        }
        envRowW = Math.max(0, envRowW - ENV_GAP);

        const width = Math.max(PROJ_PAD * 2 + envRowW, 600);
        const height = PROJ_HEADER + maxEnvH + PROJ_PAD;
        const envLeft = Math.max(PROJ_PAD, (width - envRowW) / 2);

        let envX = envLeft;
        for (const l of envs) {
          l.left = envX;
          l.top = PROJ_HEADER;
          l.height = maxEnvH;

          for (const n of l.nodes) {
            const p = l.positions.get(n.__scope + n.id);
            if (!p) continue;
            this.positions.set(n.__scope + n.id, {
              x: proj.left + envX + p.x,
              y: projTop + l.top + p.y,
              w: p.w,
              h: p.h,
              envId: l.env.id,
            });
          }

          envX += l.width + ENV_GAP;
        }

        projects.push({ left: 40, top: projTop, width, height, envs, source: project });
        projTop += height + PROJ_GAP;
      }

      this.layout = { projects };
    }

    layoutEnv(project, env) {
      const prefix = "p" + project.id + "e" + env.id + ":";
      const nodes = (env.nodes || []).filter((n) => n.id !== "internet" && n.name !== "traefik");

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
      let envW = ENV_PAD * 2;
      let y = ENV_HEADER;

      for (const tier of tiers) {
        const row = byTier.get(tier);
        row.sort((a, b) => a.name.localeCompare(b.name));
        const rowWidth = row.reduce((s, n) => s + (n.kind === "external" ? EXTERNAL_W : NODE_W) + GAP_X, -GAP_X);
        let x = ENV_PAD;
        for (const n of row) {
          const w = n.kind === "external" ? EXTERNAL_W : NODE_W;
          const h = n.kind === "external" ? 72 : NODE_H;
          positions.set(prefix + n.id, { x, y, w, h });
          x += w + GAP_X;
        }
        envW = Math.max(envW, ENV_PAD * 2 + rowWidth);
        y += NODE_H + GAP_Y;
      }

      return {
        env,
        prefix,
        nodes,
        edges,
        positions,
        width: envW,
        height: Math.max(y + ENV_PAD, ENV_HEADER + 60),
      };
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
        p.environments.some((e) => (e.nodes || []).length > 0)
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
      const header = document.createElement("div");
      header.className = "map-project-header";
      header.innerHTML =
        "<strong>" + escapeHtml(source ? source.name : "Project") + "</strong>" +
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

      const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      svg.className = "map-env-edges";
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

          for (const edge of env.edges) {
            const from = env.positions.get(edge.from);
            const to = env.positions.get(edge.to);
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

      for (const p of this.positions.values()) {
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

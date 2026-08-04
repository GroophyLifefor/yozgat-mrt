/**
 * Example topology renderer for InfinityCanvas.
 *
 * Converts topology data into child boxes, service cards, and edges.
 * The canvas still owns transforms and interaction; this file only
 * decides what the content looks like and where it goes.
 */
(function () {
  const TIER_GAP = 64; // minimum horizontal gap between tier columns
  const EDGE_GAP_PER_CHAR = 12; // extra column gap per label character
  const ENV_GAP = 48;
  const NODE_GAP = 28;
  const NODE_W = 200;
  const NODE_H = 138;
  const EXTERNAL_W = 140;
  const EXTERNAL_H = 64;
  const ENV_PAD = 24;
  const ENV_HEADER = 40;
  const ENV_CAPTION = 18;
  const PROJECT_GAP = 70;

  function escapeHtml(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function healthDot(health) {
    const s = (health || "").toLowerCase();
    const cls =
      s === "healthy" || s === "ok" ? "ok"
      : s === "warning" || s === "warn" ? "warn"
      : s === "error" || s === "bad" ? "bad"
      : "";
    return cls ? '<span class="health-dot ' + cls + '" title="' + escapeHtml(health) + '"></span>' : "";
  }

  function statusChip(status) {
    const s = (status || "").toLowerCase();
    const cls =
      s === "running" ? "status-running"
      : s === "starting" ? "status-starting"
      : s === "stopped" || s === "external" ? "status-stopped"
      : "status-error";
    return '<span class="tp-chip ' + cls + '">' + escapeHtml(status) + "</span>";
  }

  function formatBytes(bytes) {
    if (bytes == null) return "";
    const gb = bytes / (1024 * 1024 * 1024);
    if (gb >= 1) return gb.toFixed(2).replace(/\.?0+$/, "") + " GB";
    const mb = bytes / (1024 * 1024);
    if (mb >= 1) return mb.toFixed(1) + " MB";
    const kb = bytes / 1024;
    return Math.round(kb) + " KB";
  }

  function meter(label, pct, text) {
    if (pct == null && text == null) return "";
    const value = text != null ? text : pct.toFixed(1) + "%";
    const cls = pct != null && pct >= 85 ? " bad" : pct != null && pct >= 65 ? " warn" : "";
    return (
      '<div class="tp-meter">' +
      '<div class="tp-meter-label"><span>' + label + "</span><span>" + value + "</span></div>" +
      (pct == null
        ? ""
        : '<div class="tp-meter-bar"><div class="tp-meter-fill' + cls + '" style="width:' +
          Math.min(100, Math.max(0, pct)) + '%"></div></div>') +
      "</div>"
    );
  }

  function tierCaption(tier) {
    if (tier == null || tier <= 0) return "";
    if (tier === 1) return "Proxy";
    if (tier === 4) return "Data";
    return "Services";
  }

  class TopologyRenderer {
    constructor(canvas) {
      this.canvas = canvas;
      this.searchQuery = "";
      this.searchIndex = new Map();
    }

    render(topology, fit) {
      this.canvas.clear();
      this.searchIndex.clear();
      let projectY = 40;
      for (const project of topology.projects || []) {
        const layout = this.layoutProject(project);
        this.addProject(project, layout, projectY);
        projectY += layout.height + PROJECT_GAP;
      }
      if (fit !== false) this.canvas.fit();
    }

    setSearch(query) {
      this.searchQuery = (query || "").trim().toLowerCase();
      this.applySearch();
    }

    // Bottom-up dimming: a node stays visible if its own text matches the
    // query or any descendant does. Empty query clears everything.
    applySearch() {
      const q = this.searchQuery;
      if (!q) {
        for (const node of this.canvas.nodes.values()) {
          node.element.classList.remove("is-dimmed");
        }
        return;
      }

      const selfMatch = new Map();
      const children = new Map();
      for (const node of this.canvas.nodes.values()) {
        const text = this.searchIndex.get(node.id) || "";
        selfMatch.set(node.id, text.toLowerCase().includes(q));
        if (node.parent) {
          if (!children.has(node.parent)) children.set(node.parent, []);
          children.get(node.parent).push(node.id);
        }
      }

      const visible = new Map();
      const compute = (id) => {
        if (visible.has(id)) return visible.get(id);
        let m = selfMatch.get(id);
        for (const child of children.get(id) || []) {
          if (compute(child)) m = true;
        }
        visible.set(id, m);
        return m;
      };

      for (const node of this.canvas.nodes.values()) {
        node.element.classList.toggle("is-dimmed", !compute(node.id));
      }
    }

    layoutProject(project) {
      const environments = [];
      let cursor = 0;
      let maxEnvH = 0;
      for (const environment of project.environments || []) {
        const layout = this.layoutEnvironment(environment);
        environments.push({ environment, layout, x: cursor });
        cursor += layout.width + ENV_GAP;
        maxEnvH = Math.max(maxEnvH, layout.height);
      }
      const innerW = environments.length ? cursor - ENV_GAP : 0;
      return {
        environments,
        width: Math.max(320, innerW + 56),
        height: Math.max(230, maxEnvH + 114),
      };
    }

    layoutEnvironment(environment) {
      const tiers = new Map();
      for (const node of environment.nodes || []) {
        const tier = node.tier == null ? 2 : node.tier;
        if (!tiers.has(tier)) tiers.set(tier, []);
        tiers.get(tier).push(node);
      }

      const columns = Array.from(tiers.entries()).sort((a, b) => a[0] - b[0]);
      const gapWidths = this.computeGapWidths(columns, environment);

      let x = ENV_PAD;
      let maxHeight = 0;
      let contentRight = 0;
      const columnLayouts = [];
      for (let i = 0; i < columns.length; i++) {
        const [tier, nodes] = columns[i];
        const isExternal = nodes[0] && nodes[0].kind === "external";
        const w = isExternal ? EXTERNAL_W : NODE_W;
        const h = isExternal ? EXTERNAL_H : NODE_H;
        const height = nodes.length * h + Math.max(0, nodes.length - 1) * NODE_GAP;
        columnLayouts.push({ tier, nodes, x, width: w, height });
        contentRight = x + w;
        maxHeight = Math.max(maxHeight, height);
        if (i < columns.length - 1) x += w + gapWidths[i];
      }

      return {
        columns: columnLayouts,
        width: Math.max(280, contentRight + ENV_PAD),
        height: Math.max(180, maxHeight + ENV_HEADER + ENV_PAD * 2),
      };
    }

    // Gap between two adjacent tier columns must fit the longest edge label
    // whose horizontal run crosses that gap: minimum TIER_GAP (64px), plus
    // 12px per label character.
    computeGapWidths(columns, environment) {
      const tierOf = new Map();
      for (const [tier, nodes] of columns) {
        for (const n of nodes) tierOf.set(n.id, tier);
      }

      const gaps = [];
      for (let i = 0; i < columns.length - 1; i++) {
        const leftTier = columns[i][0];
        const rightTier = columns[i + 1][0];
        let maxLen = 0;
        for (const edge of environment.edges || []) {
          const fromTier = tierOf.get(edge.from);
          const toTier = tierOf.get(edge.to);
          if (fromTier == null || toTier == null || fromTier > toTier) continue;
          if (fromTier <= leftTier && toTier >= rightTier) {
            maxLen = Math.max(maxLen, String(edge.kind || "").length);
          }
        }
        gaps.push(TIER_GAP + EDGE_GAP_PER_CHAR * maxLen);
      }
      return gaps;
    }

    addProject(project, layout, y) {
      const projectId = "project-" + project.id;
      this.searchIndex.set(projectId, project.name + " " + (project.projectType || ""));
      const envCount = (project.environments || []).length;
      const meta =
        envCount + (envCount === 1 ? " environment" : " environments") +
        (project.projectType ? " · " + project.projectType : "");

      this.canvas.addNode({
        id: projectId,
        type: "container",
        label: project.name,
        x: 40,
        y,
        width: layout.width,
        height: layout.height,
        className: "tp-project",
        html:
          '<div class="tp-project-header">' +
          '<div class="tp-project-titles"><strong>' + escapeHtml(project.name) + "</strong>" +
          '<div class="tp-project-meta">' + escapeHtml(meta) + "</div></div>" +
          '<span class="status-pill">' + escapeHtml(project.status || "unknown") + "</span>" +
          "</div>",
      });

      for (const item of layout.environments) {
        this.addEnvironment(project, projectId, item, y);
      }
    }

    addEnvironment(project, projectId, item, projectY) {
      const environment = item.environment;
      const layout = item.layout;
      const environmentId = projectId + "-environment-" + environment.id;
      this.searchIndex.set(environmentId, environment.name + " " + (environment.slug || ""));

      let header = environment.name;
      if (environment.slug) header += " (" + environment.slug + ")";
      if (environment.hostPort != null) header += " · :" + environment.hostPort;

      let captions = "";
      for (const col of layout.columns) {
        const label = tierCaption(col.tier);
        if (!label) continue;
        captions +=
          '<div class="tier-caption" style="left:' + col.x + "px;top:" + (ENV_HEADER + 2) +
          "px;width:" + col.width + 'px">' + label + "</div>";
      }

      this.canvas.addNode({
        id: environmentId,
        parent: projectId,
        type: "container",
        label: environment.name,
        x: 28 + item.x,
        y: 76,
        width: layout.width,
        height: layout.height,
        className: "tp-environment",
        html: '<div class="tp-env-header">' + escapeHtml(header) + "</div>" + captions,
      });

      const nodeIds = new Map();
      for (const column of layout.columns) {
        const isExternal = column.nodes[0] && column.nodes[0].kind === "external";
        const h = isExternal ? EXTERNAL_H : NODE_H;
        const colOffset = (layout.height - ENV_HEADER - ENV_CAPTION - column.height) / 2 + ENV_HEADER + ENV_CAPTION;
        column.nodes.forEach((node, index) => {
          const id = environmentId + "-node-" + node.id;
          this.searchIndex.set(id, node.name + " " + (node.image || ""));
          nodeIds.set(node.id, id);
          this.canvas.addNode({
            id,
            parent: environmentId,
            label: node.name,
            x: column.x,
            y: colOffset + index * (h + NODE_GAP),
            width: column.width,
            height: h,
            className: isExternal ? "tp-node external" : "tp-node",
            html: this.nodeHtml(node),
            data: node,
          });
        });
      }

      for (const edge of environment.edges || []) {
        const from = nodeIds.get(edge.from);
        const to = nodeIds.get(edge.to);
        if (!from || !to) continue;
        this.canvas.addEdge({ from, to, label: edge.kind || "" });
      }
    }

    nodeHtml(node) {
      if (node.kind === "external") {
        return (
          '<div class="tp-node-icon">☁</div>' +
          '<div class="tp-node-title">' + escapeHtml(node.name) + "</div>"
        );
      }
      return (
        '<div class="tp-node-header">' +
        '<div class="tp-node-title">' + escapeHtml(node.name) + "</div>" +
        healthDot(node.health) +
        "</div>" +
        '<div class="tp-node-meta">' + statusChip(node.status) + "</div>" +
        meter("CPU", node.cpuPercent) +
        meter("Memory", node.memoryPercent, formatBytes(node.memoryBytes)) +
        (node.ports && node.ports.length
          ? '<div class="tp-node-ports">' + escapeHtml(node.ports.slice(0, 3).join(" · ")) + "</div>"
          : "")
      );
    }
  }

  // Field-accurate mock of the global /topology endpoint. Mirrors the schema
  // in src/api/topology.cr (TopologyProjectItem / TopologyEnvItem /
  // TopologyNodeItem / TopologyEdgeItem), including node ids like
  // "service:traefik", edge kinds, and all optional runtime fields.
  const MOCK_TOPOLOGY = {
    projects: [
      {
        id: 1,
        name: "Online Shop",
        projectType: "docker-compose",
        status: "active",
        environments: [
          {
            id: 101,
            slug: "production",
            name: "Production",
            hostPort: 8080,
            deploymentSlug: "prod-20260804-1200",
            updatedAt: "2026-08-04T19:58:00Z",
            nodes: [
              {
                id: "internet",
                kind: "external",
                name: "Internet",
                image: null,
                status: "external",
                health: "healthy",
                cpuPercent: null,
                memoryPercent: null,
                memoryBytes: null,
                ports: [],
                replicas: 0,
                deployedAt: null,
                containers: [],
                tier: 0,
              },
              {
                id: "service:traefik",
                kind: "service",
                name: "traefik",
                image: "traefik:v3.1",
                status: "running",
                health: "healthy",
                cpuPercent: 3.2,
                memoryPercent: 12.4,
                memoryBytes: 134217728,
                ports: ["8080:80", "8443:443"],
                replicas: 1,
                deployedAt: "2026-08-04T12:00:00Z",
                containers: [
                  { id: "ab12cd34", name: "shop-traefik-1", status: "running", health: "healthy" },
                ],
                tier: 1,
              },
              {
                id: "service:web",
                kind: "service",
                name: "web",
                image: "node:20-alpine",
                status: "running",
                health: "healthy",
                cpuPercent: 1.8,
                memoryPercent: 22.1,
                memoryBytes: 268435456,
                ports: ["3000:3000"],
                replicas: 2,
                deployedAt: "2026-08-04T12:00:00Z",
                containers: [
                  { id: "cd34ef56", name: "shop-web-1", status: "running", health: "healthy" },
                  { id: "ef56ab78", name: "shop-web-2", status: "running", health: "healthy" },
                ],
                tier: 2,
              },
              {
                id: "service:api",
                kind: "service",
                name: "api",
                image: "shop-api:1.4.2",
                status: "running",
                health: "healthy",
                cpuPercent: 7.6,
                memoryPercent: 31.8,
                memoryBytes: 402653184,
                ports: ["4000:4000"],
                replicas: 2,
                deployedAt: "2026-08-04T12:00:00Z",
                containers: [
                  { id: "ab78cd90", name: "shop-api-1", status: "running", health: "healthy" },
                  { id: "cd90ab12", name: "shop-api-2", status: "running", health: "healthy" },
                ],
                tier: 3,
              },
              {
                id: "service:postgres",
                kind: "service",
                name: "postgres",
                image: "postgres:16-alpine",
                status: "running",
                health: "warning",
                cpuPercent: 5.4,
                memoryPercent: 48.2,
                memoryBytes: 536870912,
                ports: ["5432:5432"],
                replicas: 1,
                deployedAt: "2026-08-01T09:00:00Z",
                containers: [
                  { id: "ab12ef78", name: "shop-postgres-1", status: "running", health: "warning" },
                ],
                tier: 4,
              },
            ],
            edges: [
              { from: "internet", to: "service:traefik", kind: "ingress" },
              { from: "service:traefik", to: "service:web", kind: "proxy" },
              { from: "service:web", to: "service:api", kind: "proxy" },
              { from: "service:api", to: "service:postgres", kind: "depends_on" },
            ],
          },
          {
            id: 102,
            slug: "staging",
            name: "Staging",
            hostPort: 8081,
            deploymentSlug: "stage-20260804-1100",
            updatedAt: "2026-08-04T19:40:00Z",
            nodes: [
              {
                id: "internet",
                kind: "external",
                name: "Internet",
                image: null,
                status: "external",
                health: "healthy",
                cpuPercent: null,
                memoryPercent: null,
                memoryBytes: null,
                ports: [],
                replicas: 0,
                deployedAt: null,
                containers: [],
                tier: 0,
              },
              {
                id: "service:traefik",
                kind: "service",
                name: "traefik",
                image: "traefik:v3.1",
                status: "running",
                health: "healthy",
                cpuPercent: 1.1,
                memoryPercent: 8.9,
                memoryBytes: 100663296,
                ports: ["8081:80"],
                replicas: 1,
                deployedAt: "2026-08-04T11:00:00Z",
                containers: [
                  { id: "aa11bb22", name: "shop-staging-traefik-1", status: "running", health: "healthy" },
                ],
                tier: 1,
              },
              {
                id: "service:api",
                kind: "service",
                name: "api",
                image: "shop-api:1.4.2-rc1",
                status: "starting",
                health: "warning",
                cpuPercent: 9.2,
                memoryPercent: 15.7,
                memoryBytes: 150994944,
                ports: ["4001:4000"],
                replicas: 1,
                deployedAt: "2026-08-04T11:00:00Z",
                containers: [
                  { id: "bb22cc33", name: "shop-staging-api-1", status: "starting", health: "warning" },
                ],
                tier: 3,
              },
              {
                id: "service:redis",
                kind: "service",
                name: "redis",
                image: "redis:7-alpine",
                status: "stopped",
                health: "error",
                cpuPercent: null,
                memoryPercent: null,
                memoryBytes: null,
                ports: ["6379:6379"],
                replicas: 1,
                deployedAt: "2026-08-01T09:00:00Z",
                containers: [
                  { id: "cc33dd44", name: "shop-staging-redis-1", status: "stopped", health: "error" },
                ],
                tier: 4,
              },
            ],
            edges: [
              { from: "internet", to: "service:traefik", kind: "ingress" },
              { from: "service:traefik", to: "service:api", kind: "proxy" },
              { from: "service:api", to: "service:redis", kind: "depends_on" },
            ],
          },
        ],
      },
      {
        id: 2,
        name: "Metrics Platform",
        projectType: "docker-compose",
        status: "active",
        environments: [
          {
            id: 201,
            slug: "main",
            name: "Main",
            hostPort: null,
            deploymentSlug: "metrics-20260730-0800",
            updatedAt: "2026-08-04T18:00:00Z",
            nodes: [
              {
                id: "internet",
                kind: "external",
                name: "Internet",
                image: null,
                status: "external",
                health: "healthy",
                cpuPercent: null,
                memoryPercent: null,
                memoryBytes: null,
                ports: [],
                replicas: 0,
                deployedAt: null,
                containers: [],
                tier: 0,
              },
              {
                id: "service:collector",
                kind: "service",
                name: "collector",
                image: "prom/prometheus:v2.53",
                status: "running",
                health: "healthy",
                cpuPercent: 11.3,
                memoryPercent: 26.4,
                memoryBytes: 301989888,
                ports: ["9090:9090"],
                replicas: 1,
                deployedAt: "2026-07-30T08:00:00Z",
                containers: [
                  { id: "dd44ee55", name: "metrics-collector-1", status: "running", health: "healthy" },
                ],
                tier: 2,
              },
              {
                id: "service:dashboard",
                kind: "service",
                name: "dashboard",
                image: "grafana/grafana:11.1",
                status: "running",
                health: "healthy",
                cpuPercent: 2.4,
                memoryPercent: 18.5,
                memoryBytes: 201326592,
                ports: ["3001:3000"],
                replicas: 1,
                deployedAt: "2026-07-30T08:00:00Z",
                containers: [
                  { id: "ee55ff66", name: "metrics-dashboard-1", status: "running", health: "healthy" },
                ],
                tier: 3,
              },
              {
                id: "service:timescale",
                kind: "service",
                name: "timescale",
                image: "timescale/timescaledb:2.15-pg16",
                status: "running",
                health: "warning",
                cpuPercent: 14.7,
                memoryPercent: 55.1,
                memoryBytes: 644245094,
                ports: ["5433:5432"],
                replicas: 1,
                deployedAt: "2026-07-30T08:00:00Z",
                containers: [
                  { id: "ff66aa77", name: "metrics-timescale-1", status: "running", health: "warning" },
                ],
                tier: 4,
              },
            ],
            edges: [
              { from: "service:collector", to: "service:timescale", kind: "depends_on" },
              { from: "service:dashboard", to: "service:timescale", kind: "depends_on" },
            ],
          },
        ],
      },
    ],
  };

  window.TopologyRenderer = TopologyRenderer;
  window.MOCK_TOPOLOGY = MOCK_TOPOLOGY;
})();

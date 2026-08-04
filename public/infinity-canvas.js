/**
 * Small reusable infinite canvas.
 *
 * The canvas owns transforms, nodes, edges, child-box clipping, and minimap.
 * Application code owns node content and layout.
 */
(function () {
  const SVG_NS = "http://www.w3.org/2000/svg";
  const ROUTE_MARGIN = 8;
  const CORNER_RADIUS = 7;

  function clamp(v, min, max) {
    return Math.min(max, Math.max(min, v));
  }

  // Orthogonal polyline with rounded corners. Collinear points collapse to
  // straight runs; each 90° turn becomes a small fillet so long detours read
  // as deliberate circuit traces rather than jagged Z-shapes.
  function roundedPath(points, radius) {
    const pts = [];
    for (const p of points) {
      const prev = pts[pts.length - 1];
      if (!prev || prev[0] !== p[0] || prev[1] !== p[1]) pts.push(p);
    }
    if (pts.length < 2) return "";

    const d = ["M " + pts[0][0] + " " + pts[0][1]];
    for (let i = 1; i < pts.length - 1; i++) {
      const p0 = pts[i - 1];
      const p1 = pts[i];
      const p2 = pts[i + 1];
      const v1 = [p1[0] - p0[0], p1[1] - p0[1]];
      const v2 = [p2[0] - p1[0], p2[1] - p1[1]];
      const l1 = Math.hypot(v1[0], v1[1]);
      const l2 = Math.hypot(v2[0], v2[1]);
      if (l1 === 0 || l2 === 0) {
        d.push("L " + p1[0] + " " + p1[1]);
        continue;
      }
      const c = Math.min(radius, l1 / 2, l2 / 2);
      const s = [p1[0] - (v1[0] / l1) * c, p1[1] - (v1[1] / l1) * c];
      const e = [p1[0] + (v2[0] / l2) * c, p1[1] + (v2[1] / l2) * c];
      d.push("L " + s[0] + " " + s[1]);
      d.push("Q " + p1[0] + " " + p1[1] + " " + e[0] + " " + e[1]);
    }
    const last = pts[pts.length - 1];
    d.push("L " + last[0] + " " + last[1]);
    return d.join(" ");
  }

  class InfinityCanvas {
    constructor(viewport, options) {
      this.viewport = viewport;
      this.options = options || {};
      this.content = this.options.content || this.createLayer("infinity-canvas-content");
      this.edges = this.options.edges || this.createSvgLayer();
      this.nodes = new Map();
      this.edgeList = [];
      this.scale = 1;
      this.panX = 0;
      this.panY = 0;
      this.minScale = this.options.minScale || 0.25;
      this.maxScale = this.options.maxScale || 2.5;
      this.panning = false;
      this.lastPointer = null;
      this.minimap = this.options.minimap || null;
      this.minimapScale = 0;
      this.minimapMinX = 0;
      this.minimapMinY = 0;
      this.destroyed = false;

      this.onWheel = (event) => this.handleWheel(event);
      this.onPointerDown = (event) => this.handlePointerDown(event);
      this.onPointerMove = (event) => this.handlePointerMove(event);
      this.onPointerUp = () => this.handlePointerUp();
      this.onMinimapPointer = (event) => this.handleMinimapPointer(event);

      this.viewport.addEventListener("wheel", this.onWheel, { passive: false });
      this.viewport.addEventListener("pointerdown", this.onPointerDown);
      window.addEventListener("pointermove", this.onPointerMove);
      window.addEventListener("pointerup", this.onPointerUp);

      if (this.minimap) {
        this.minimap.addEventListener("pointerdown", this.onMinimapPointer);
      }
      this.content.style.transformOrigin = "0 0";
      this.edges.style.transformOrigin = "0 0";
      this.applyTransform();
    }

    createLayer(className) {
      const layer = document.createElement("div");
      layer.className = className;
      this.viewport.appendChild(layer);
      return layer;
    }

    createSvgLayer() {
      const svg = document.createElementNS(SVG_NS, "svg");
      svg.classList.add("infinity-canvas-edges");
      this.viewport.appendChild(svg);
      return svg;
    }

    addNode(spec) {
      if (!spec || !spec.id) throw new Error("A node requires an id");
      if (this.nodes.has(spec.id)) throw new Error("Duplicate node id: " + spec.id);

      const node = {
        id: String(spec.id),
        parent: spec.parent == null ? null : String(spec.parent),
        type: spec.type || "node",
        x: Number(spec.x) || 0,
        y: Number(spec.y) || 0,
        width: Math.max(0, Number(spec.width) || 0),
        height: Math.max(0, Number(spec.height) || 0),
        label: spec.label == null ? "" : String(spec.label),
        data: spec.data,
        element: null,
      };

      node.element = this.createNodeElement(node, spec);
      this.nodes.set(node.id, node);

      const parent = node.parent ? this.nodes.get(node.parent) : null;
      (parent ? parent.element : this.content).appendChild(node.element);
      this.renderNode(node);
      this.renderEdges();
      this.renderMinimap();
      return node;
    }

    createNodeElement(node, spec) {
      const element = document.createElement("div");
      element.className =
        spec.className || (node.type === "container" ? "infinity-child-box" : "infinity-node");
      element.dataset.nodeId = node.id;
      element.style.position = "absolute";
      element.style.boxSizing = "border-box";

      if (typeof this.options.renderNode === "function") {
        this.options.renderNode(node, element);
      } else if (spec.html != null) {
        element.innerHTML = spec.html;
      } else {
        element.textContent = node.label;
      }
      return element;
    }

    updateNode(id, values) {
      const node = this.nodes.get(String(id));
      if (!node) return;
      Object.assign(node, values || {});
      this.renderNode(node);
      this.renderEdges();
      this.renderMinimap();
    }

    removeNode(id) {
      const node = this.nodes.get(String(id));
      if (!node) return;
      for (const child of Array.from(this.nodes.values())) {
        if (child.parent === node.id) this.removeNode(child.id);
      }
      node.element.remove();
      this.nodes.delete(node.id);
      this.edgeList = this.edgeList.filter((edge) => edge.from !== node.id && edge.to !== node.id);
      this.renderEdges();
      this.renderMinimap();
    }

    addEdge(spec) {
      if (!spec || !spec.from || !spec.to) {
        throw new Error("An edge requires from and to node ids");
      }
      this.edgeList.push({
        from: String(spec.from),
        to: String(spec.to),
        label: spec.label == null ? "" : String(spec.label),
        className: spec.className || "",
      });
      this.renderEdges();
      this.renderMinimap();
    }

    clear() {
      this.nodes.clear();
      this.edgeList = [];
      this.content.innerHTML = "";
      while (this.edges.firstChild) this.edges.firstChild.remove();
      this.renderMinimap();
    }

    renderNode(node) {
      const parent = node.parent ? this.nodes.get(node.parent) : null;
      const maxX = parent ? Math.max(0, parent.width - node.width) : Infinity;
      const maxY = parent ? Math.max(0, parent.height - node.height) : Infinity;
      const x = Math.min(Math.max(0, Number(node.x) || 0), maxX);
      const y = Math.min(Math.max(0, Number(node.y) || 0), maxY);

      node.element.style.left = x + "px";
      node.element.style.top = y + "px";
      node.element.style.width = node.width + "px";
      node.element.style.height = node.height + "px";
      node.element.style.overflow = node.type === "container" ? "hidden" : "";
      node.element.dataset.x = x;
      node.element.dataset.y = y;
    }

    worldRect(node) {
      let x = Number(node.element.dataset.x) || 0;
      let y = Number(node.element.dataset.y) || 0;
      let parent = node.parent ? this.nodes.get(node.parent) : null;
      while (parent) {
        x += Number(parent.element.dataset.x) || 0;
        y += Number(parent.element.dataset.y) || 0;
        parent = parent.parent ? this.nodes.get(parent.parent) : null;
      }
      return { x, y, width: node.width, height: node.height };
    }

    renderEdges() {
      while (this.edges.firstChild) this.edges.firstChild.remove();
      for (const edge of this.edgeList) {
        const from = this.nodes.get(edge.from);
        const to = this.nodes.get(edge.to);
        if (!from || !to) continue;

        const a = this.worldRect(from);
        const b = this.worldRect(to);

        // The source exits through its right edge, the target enters through
        // its left edge. The horizontal run travels on a lane chosen to avoid
        // any node between the two columns.
        const x1 = a.x + a.width;
        const x2 = b.x;
        let lane;
        let points;
        if (x2 >= x1) {
          const y1 = a.y + a.height / 2;
          lane = this.routeLane(x1, y1, x2, from, to);
          const exitY = clamp(lane, a.y + CORNER_RADIUS, a.y + a.height - CORNER_RADIUS);
          const enterY = clamp(lane, b.y + CORNER_RADIUS, b.y + b.height - CORNER_RADIUS);
          points = [[x1, exitY], [x1, lane], [x2, lane], [x2, enterY]];
        } else {
          // Backwards edge: bend vertically in the gap between columns.
          const midY = a.y + a.height / 2 + (b.y + b.height / 2 - (a.y + a.height / 2)) / 2;
          lane = midY;
          points = [[x1, a.y + a.height / 2], [x1, midY], [x2, midY], [x2, b.y + b.height / 2]];
        }

        const path = document.createElementNS(SVG_NS, "path");
        path.setAttribute("d", roundedPath(points, CORNER_RADIUS));
        path.setAttribute("class", edge.className);
        this.edges.appendChild(path);

        if (edge.label) {
          const text = document.createElementNS(SVG_NS, "text");
          text.setAttribute("x", (x1 + x2) / 2);
          text.setAttribute("y", lane - 6);
          text.setAttribute("text-anchor", "middle");
          text.textContent = edge.label;
          this.edges.appendChild(text);
        }
      }
    }

    // Pick a horizontal lane for a forward edge that clears every node
    // between the source and target columns. Prefers the free band nearest
    // the source's vertical centre so the connection stays short.
    routeLane(x1, defaultY, x2, from, to) {
      let minTop = Infinity;
      let maxBottom = -Infinity;
      for (const other of this.nodes.values()) {
        if (other === from || other === to) continue;
        const r = this.worldRect(other);
        if (r.x > x1 && r.x + r.width < x2) {
          minTop = Math.min(minTop, r.y);
          maxBottom = Math.max(maxBottom, r.y + r.height);
        }
      }
      if (!isFinite(minTop)) return defaultY;

      const topLane = minTop - ROUTE_MARGIN;
      const bottomLane = maxBottom + ROUTE_MARGIN;
      return Math.abs(topLane - defaultY) <= Math.abs(bottomLane - defaultY)
        ? topLane
        : bottomLane;
    }

    getBounds() {
      const roots = Array.from(this.nodes.values()).filter((node) => !node.parent);
      if (!roots.length) return { x: 0, y: 0, width: 0, height: 0 };

      let minX = Infinity;
      let minY = Infinity;
      let maxX = -Infinity;
      let maxY = -Infinity;
      for (const node of roots) {
        const rect = this.worldRect(node);
        minX = Math.min(minX, rect.x);
        minY = Math.min(minY, rect.y);
        maxX = Math.max(maxX, rect.x + rect.width);
        maxY = Math.max(maxY, rect.y + rect.height);
      }
      return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
    }

    fit(padding) {
      const bounds = this.getBounds();
      if (!bounds.width || !bounds.height) return;
      const pad = padding == null ? 40 : padding;
      const rect = this.viewport.getBoundingClientRect();
      const width = bounds.width + pad * 2;
      const height = bounds.height + pad * 2;
      this.scale = Math.min(rect.width / width, rect.height / height, 1.2);
      this.panX = (rect.width - width * this.scale) / 2 - (bounds.x - pad) * this.scale;
      this.panY = (rect.height - height * this.scale) / 2 - (bounds.y - pad) * this.scale;
      this.applyTransform();
      this.renderMinimap();
    }

    setTransform(transform) {
      this.scale = Math.min(this.maxScale, Math.max(this.minScale, transform.scale));
      this.panX = Number(transform.x) || 0;
      this.panY = Number(transform.y) || 0;
      this.applyTransform();
      this.renderMinimap();
    }

    getTransform() {
      return { x: this.panX, y: this.panY, scale: this.scale };
    }

    applyTransform() {
      const transform = `translate(${this.panX}px, ${this.panY}px) scale(${this.scale})`;
      this.content.style.transform = transform;
      this.edges.style.transform = transform;
    }

    handlePointerDown(event) {
      if (event.target.closest("[data-node-id]")) return;
      this.panning = true;
      this.lastPointer = { x: event.clientX, y: event.clientY };
      this.viewport.classList.add("is-panning");
    }

    handlePointerMove(event) {
      if (!this.panning || !this.lastPointer) return;
      this.panX += event.clientX - this.lastPointer.x;
      this.panY += event.clientY - this.lastPointer.y;
      this.lastPointer = { x: event.clientX, y: event.clientY };
      this.applyTransform();
      this.renderMinimap();
    }

    handlePointerUp() {
      this.panning = false;
      this.lastPointer = null;
      this.viewport.classList.remove("is-panning");
    }

    handleWheel(event) {
      event.preventDefault();
      const rect = this.viewport.getBoundingClientRect();
      const x = event.clientX - rect.left;
      const y = event.clientY - rect.top;
      const previous = this.scale;
      const factor = event.deltaY < 0 ? 1.08 : 1 / 1.08;
      this.scale = Math.min(this.maxScale, Math.max(this.minScale, previous * factor));
      this.panX = x - ((x - this.panX) * this.scale) / previous;
      this.panY = y - ((y - this.panY) * this.scale) / previous;
      this.applyTransform();
      this.renderMinimap();
    }

    renderMinimap() {
      if (!this.minimap) return;
      this.minimap.innerHTML = "";
      const bounds = this.getBounds();
      if (!bounds.width || !bounds.height) return;

      const width = this.minimap.clientWidth;
      const height = this.minimap.clientHeight;
      const scale = Math.min(width / (bounds.width + 40), height / (bounds.height + 40));
      this.minimapScale = scale;
      this.minimapMinX = bounds.x - 20;
      this.minimapMinY = bounds.y - 20;

      for (const node of this.nodes.values()) {
        const rect = this.worldRect(node);
        const marker = document.createElement("div");
        marker.className = node.type === "container" ? "minimap-box" : "minimap-node";
        marker.style.left = (rect.x - this.minimapMinX) * scale + "px";
        marker.style.top = (rect.y - this.minimapMinY) * scale + "px";
        marker.style.width = Math.max(2, rect.width * scale) + "px";
        marker.style.height = Math.max(2, rect.height * scale) + "px";
        this.minimap.appendChild(marker);
      }

      const viewport = this.viewport.getBoundingClientRect();
      const view = document.createElement("div");
      view.className = "minimap-viewport";
      view.style.left = (-this.panX / this.scale - this.minimapMinX) * scale + "px";
      view.style.top = (-this.panY / this.scale - this.minimapMinY) * scale + "px";
      view.style.width = (viewport.width / this.scale) * scale + "px";
      view.style.height = (viewport.height / this.scale) * scale + "px";
      this.minimap.appendChild(view);
    }

    handleMinimapPointer(event) {
      if (!this.minimapScale) return;
      event.preventDefault();
      const rect = this.minimap.getBoundingClientRect();
      const x = (event.clientX - rect.left) / this.minimapScale + this.minimapMinX;
      const y = (event.clientY - rect.top) / this.minimapScale + this.minimapMinY;
      const viewport = this.viewport.getBoundingClientRect();
      this.panX = viewport.width / 2 - x * this.scale;
      this.panY = viewport.height / 2 - y * this.scale;
      this.applyTransform();
      this.renderMinimap();
    }

    destroy() {
      if (this.destroyed) return;
      this.destroyed = true;
      this.viewport.removeEventListener("wheel", this.onWheel);
      this.viewport.removeEventListener("pointerdown", this.onPointerDown);
      window.removeEventListener("pointermove", this.onPointerMove);
      window.removeEventListener("pointerup", this.onPointerUp);
      if (this.minimap) {
        this.minimap.removeEventListener("pointerdown", this.onMinimapPointer);
      }
    }
  }

  window.InfinityCanvas = InfinityCanvas;
})();

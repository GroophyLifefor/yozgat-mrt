/**
 * Map bootstrap — wires InfinityCanvas + TopologyRenderer to /topology.
 *
 * All layout, card markup, edge routing, and minimap drawing live in the
 * reusable canvas + renderer files; this file only owns auth, fetching,
 * search input, and the topbar controls.
 */
(function () {
  const viewport = document.getElementById("map-root");
  const canvas = new InfinityCanvas(viewport, {
    minimap: document.getElementById("map-minimap"),
    content: viewport.querySelector(".map-nodes"),
    edges: viewport.querySelector(".map-edges"),
  });
  const renderer = new TopologyRenderer(canvas);

  const searchEl = document.getElementById("map-search");
  const statusEl = document.getElementById("map-status");
  const loadingEl = document.getElementById("map-loading");
  const emptyEl = document.getElementById("map-empty");

  let projects = [];
  let pollTimer = null;

  async function init() {
    const user = await requireAuth();
    if (!user) return;
    mountShell(user);

    document.getElementById("btn-refresh").addEventListener("click", loadTopology);
    document.getElementById("btn-fit").addEventListener("click", () => canvas.fit());
    searchEl.addEventListener("input", (e) => renderer.setSearch(e.target.value));

    await loadTopology();
  }

  async function loadTopology() {
    if (pollTimer) clearInterval(pollTimer);
    setLoading(true);
    setStatus("Loading…");

    try {
      const { res, data } = await apiJson("/topology");

      if (!res.ok) {
        setStatus((data && data.error) || "Could not load topology");
        setProjects([]);
        return;
      }

      setProjects((data && data.topology && data.topology.projects) || [], { fit: true });
      pollTimer = setInterval(refreshTopology, 15000);
    } finally {
      setLoading(false);
    }
  }

  async function refreshTopology() {
    const { res, data } = await apiJson("/topology");
    if (!res.ok || !data || !data.topology) return;

    // Re-render without refitting so the user keeps their pan/zoom.
    setProjects(data.topology.projects || [], { fit: false });
  }

  function setProjects(list, opts) {
    projects = list || [];
    renderer.render({ projects }, !opts || opts.fit !== false);
    renderer.setSearch(searchEl.value);

    const hasServices = projects.some((p) =>
      (p.environments || []).some((e) => (e.nodes || []).some((n) => n.kind !== "external"))
    );
    if (emptyEl) emptyEl.hidden = hasServices;
    updateStatus();
  }

  function updateStatus() {
    const envCount = projects.reduce((n, p) => n + (p.environments ? p.environments.length : 0), 0);
    setStatus(projects.length + " projects · " + envCount + " environments");
  }

  function setLoading(on) {
    if (!loadingEl) return;
    loadingEl.hidden = !on;
    loadingEl.style.display = on ? "flex" : "none";
  }

  function setStatus(msg) {
    statusEl.textContent = msg;
  }

  init();
})();

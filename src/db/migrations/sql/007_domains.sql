CREATE TABLE domains (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    environment_id INTEGER NOT NULL REFERENCES environments(id) ON DELETE CASCADE,
    domain_name TEXT NOT NULL,
    service_name TEXT,
    port INTEGER NOT NULL DEFAULT 80,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (project_id, environment_id, domain_name)
);

CREATE INDEX idx_domains_project_env ON domains(project_id, environment_id);
CREATE INDEX idx_domains_domain_name ON domains(domain_name);

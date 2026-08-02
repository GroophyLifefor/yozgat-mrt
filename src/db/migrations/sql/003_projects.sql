CREATE TABLE projects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    repo_url TEXT NOT NULL,
    auth_username TEXT,
    auth_token TEXT,
    webhook_secret TEXT NOT NULL,
    project_type TEXT NOT NULL CHECK (project_type IN ('static', 'dockerfile', 'dockercompose')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_projects_repo_url ON projects(repo_url);

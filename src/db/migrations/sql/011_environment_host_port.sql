ALTER TABLE environments ADD COLUMN host_port INTEGER;

UPDATE environments
SET host_port = (
    SELECT d.assigned_port
    FROM deployments d
    WHERE d.environment_id = environments.id
      AND d.assigned_port IS NOT NULL
    ORDER BY d.id DESC
    LIMIT 1
);

CREATE INDEX idx_environments_host_port ON environments(host_port);

ALTER TABLE deployments ADD COLUMN deployment_slug TEXT;

CREATE UNIQUE INDEX idx_deployments_slug ON deployments(project_id, environment_id, deployment_slug);

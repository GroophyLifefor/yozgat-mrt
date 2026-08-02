ALTER TABLE deployments ADD COLUMN assigned_port INTEGER;

CREATE INDEX idx_deployments_assigned_port ON deployments(assigned_port);

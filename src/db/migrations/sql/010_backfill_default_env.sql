INSERT INTO environments (project_id, name, slug)
SELECT p.id, 'Production', 'prod'
FROM projects p
WHERE NOT EXISTS (
    SELECT 1 FROM environments e WHERE e.project_id = p.id
);

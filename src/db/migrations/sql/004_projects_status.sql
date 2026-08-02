ALTER TABLE projects ADD COLUMN status TEXT NOT NULL DEFAULT 'not_initialized'
    CHECK (status IN (
        'not_initialized',
        'starting',
        'running',
        'stopping',
        'stopped',
        'deploying',
        'failed',
        'exited',
        'removing',
        'unknown'
    ));

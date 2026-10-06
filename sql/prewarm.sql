-- Loads every table and index into shared_buffers right after a database pull, so the first
-- tiles don't wait on disk
CREATE EXTENSION IF NOT EXISTS pg_prewarm;
SELECT count(pg_prewarm(c.oid))
FROM pg_class c
WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'i', 'm');

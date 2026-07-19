-- Keeper server baseline — extensions.
-- pg_cron is the C10 substrate (check-in engine, recaps, awareness decay run server-side).
-- No jobs are scheduled here; per C10 every job is registered in the cron ops README the day
-- it is wired (M6, or M1 if the proxy needs cron hosting).

create extension if not exists pg_cron;

grant usage on schema cron to postgres;

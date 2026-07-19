-- Advisor hardening (lints 0028/0029): trigger / event-trigger functions are not part of the
-- client API surface — remove them from PostgREST's RPC reach. Trigger-typed functions can't
-- actually be invoked via RPC, but the exposed EXECUTE grant is still surface area.
-- (rls_auto_enable is the platform's ensure_rls event trigger — kept, it enforces C2's posture
-- on any future table; only its API-facing grant is revoked here.)

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;

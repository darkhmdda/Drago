-- Drago · borrar el historial de cambios del usuario (para «Borrar todos mis datos»)
--
-- Los datos financieros se borran con push_ledger (subiendo un libro vacío),
-- así los demás dispositivos también reciben la versión limpia. La bitácora
-- (audit_logs) solo permite insertar desde la app; esta función, que solo
-- actúa sobre las filas del propio usuario, permite vaciarla a petición suya.
create or replace function clear_my_audit_log() returns void
language sql security definer set search_path = public as $$
  delete from audit_logs where user_id = auth.uid();
$$;
revoke execute on function clear_my_audit_log() from public, anon;
grant execute on function clear_my_audit_log() to authenticated;

-- Drago · avisos en tiempo real
-- Cuando un dispositivo sube cambios, la versión en sync_state aumenta y
-- Supabase Realtime avisa al instante a los demás dispositivos del usuario.
-- RLS se aplica también a Realtime: cada usuario solo recibe sus propios avisos.
alter publication supabase_realtime add table sync_state;

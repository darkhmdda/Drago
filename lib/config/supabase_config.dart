/// Configuración pública de Supabase.
///
/// La clave *publishable* está diseñada para incluirse en aplicaciones
/// cliente: por sí sola no da acceso a datos, porque todas las tablas están
/// protegidas con RLS y solo usuarios autenticados ven sus propios registros.
/// NUNCA pongas aquí la clave `service_role` ni la contraseña de la base de datos.
class SupabaseConfig {
  static const url = 'https://bygeszaxgqxcxxezsyvx.supabase.co';
  static const publishableKey = 'sb_publishable_fNwa-i-15xyaKFk916ERuw_E0HqEaqS';
}

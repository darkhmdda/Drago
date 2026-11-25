# Conectar Drago con Supabase

Drago guarda todo primero en el dispositivo y funciona sin conexión. Con una cuenta, además:

- respalda tus datos en la nube, y
- los sincroniza entre la computadora (web) y el teléfono (APK).

## 1. Crear las tablas (una sola vez)

1. En el panel de Supabase abre **SQL Editor → New query**.
2. Copia todo el contenido de [`supabase/setup_completo.sql`](../supabase/setup_completo.sql), pégalo y pulsa **Run**.
3. Debe terminar con *Success. No rows returned*. Si sale un error, no lo ejecutes otra vez: copia el mensaje y revísalo.

El script crea las tablas con RLS (cada usuario solo ve sus datos), los permisos solo para usuarios con sesión
iniciada y las funciones `pull_ledger` / `push_ledger` que usa la app para sincronizar.

## 2. Ajustes de autenticación

En **Authentication → Sign In / Providers → Email**:

- **Confirm email**: si lo dejas activo, al crear la cuenta llega un correo con un enlace que hay que abrir antes de
  iniciar sesión. Mientras la versión web no esté publicada, el enlace puede abrir una página que no carga, pero la
  cuenta queda confirmada igual. Para uso personal puedes desactivarlo y entrar directamente.

En **Authentication → URL Configuration**:

- **Site URL**: cuando publiques la versión web, pon aquí su dirección (los enlaces de confirmación y de «Olvidé mi
  contraseña» llevan ahí).

Después de crear tu cuenta, si nadie más va a usar la app, puedes desactivar **Allow new users to sign up** en
**Authentication → Sign In / Providers**. No es obligatorio: RLS ya impide que otra cuenta vea tus datos.

## 3. Usarlo en la app

**Ajustes → Cuenta y sincronización → Iniciar sesión o crear cuenta.**

- El icono de nube arriba a la derecha indica el estado: sincronizado, pendiente, sin conexión o con conflicto.
- Cada cambio se sube unos segundos después. Al abrir la app y cada 2 minutos se revisan cambios de otros dispositivos.
- Si cambiaste datos en dos dispositivos sin conexión, la app **no pisa nada**: te muestra las dos copias y eliges cuál
  conservar.

## Seguridad

- En la app solo van la URL del proyecto y la clave **publishable** (`lib/config/supabase_config.dart`), que están
  pensadas para ser públicas.
- **Nunca** pongas en la app ni compartas la clave `service_role` ni la contraseña de la base de datos.

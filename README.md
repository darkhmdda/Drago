# Drago

*Antes llamado provisionalmente «FinanSync» en los documentos de especificación.*

Aplicación de administración financiera personal para **web** y **Android**, hecha con Flutter.
La especificación completa está en [`docs/especificacion.md`](docs/especificacion.md).

> Regla principal: **nunca confundir el dinero que realmente tienes con el dinero que esperas recibir.**

## Estado actual: v1.0

| Versión | Contenido | Estado |
|---|---|---|
| 0.1 | Saldo físico / digital / total, ingresos, gastos, transferencias, historial | ✅ |
| 0.2 | Deudas, cuotas variables, pagos y abonos parciales, saldo pendiente | ✅ |
| 0.3 | Calendario mensual, semanal y agenda; ingresos y gastos recurrentes; pagos integrados | ✅ |
| 0.4 | Recordatorios de pagos, centro de notificaciones, reportes mensuales, exportación Excel/CSV/PDF | ✅ |
| 0.5 | Proyecciones, gráfica, simulaciones guardables y comparación | ✅ |
| — | Cuenta y sincronización con Supabase (adelantado de la 1.0) | ✅ Ver [docs/supabase.md](docs/supabase.md) |
| 1.0 | Asistente en lenguaje natural (por reglas, sin IA), importar capturas con lectura de texto en el dispositivo, sincronización, respaldo en archivo | ✅ |

### Lo que ya funciona
- **Inicio**: dinero físico, dinero digital y total disponible (solo dinero real), próximo pago, próximo ingreso,
  deudas pendientes, pagos del mes, lista de próximos pagos, resumen del mes y alertas (cuotas vencidas, pagos de la
  semana, saldo proyectado negativo, deudas cuyo monto no coincide con sus cuotas).
- **Cuentas**: varias cuentas físicas o digitales; corrección de saldo con registro del ajuste.
- **Movimientos**: ingreso, gasto, pago de deuda, transferencia (no cuenta como ingreso ni gasto) y ajuste manual.
- **Deudas**: monto original independiente de las cuotas; cuotas con importe y fecha propios; flujo de pago con
  confirmación y descuento único; abonos parciales; edición controlada; liquidación automática.
- **Calendario financiero**:
  - Vistas **mensual**, **semanal** y **agenda**, con colores para ingresos, pagos pendientes, vencidos, pagados y no recibidos.
  - **Reglas recurrentes** de ingresos o gastos: diaria, semanal, quincenal (ej. días 1 y 16), mensual (ajusta el
    día 31 a meses cortos) o cada N días, con fecha final opcional; se pueden pausar, editar o eliminar.
  - Cada fecha se **confirma por separado** (con el importe real), se marca como **no recibida** o se **ajusta**
    sin tocar la regla. Las cuotas de las deudas aparecen solas y vinculadas a su cuota original: nunca se duplican.
  - La agenda muestra el **saldo proyectado** después de cada evento; los ingresos atrasados no se suman hasta confirmarse.
- **Proyecciones** (Reportes → Proyecciones): gráfica del saldo proyectado a 30/60/90 días y simulaciones guardables
  (ingreso extra o recurrente, gasto extraordinario, periodo sin ingresos, cambiar un recurrente, adelantar una cuota)
  comparadas con la proyección base. Nunca modifican los datos reales.
- **Asistente** (icono de chat): «Hoy gasté 80 en comida», «Recibí 400», «Pagué DiDi», «Cambió la cuota de Coppel a 450»,
  «¿Cuánto debo en diciembre?», «¿Cuánto tenía el 20 de noviembre?», «Simula diciembre con 400 semanales». Funciona sin
  IA ni conexión; pregunta cuando hay varias opciones y siempre pide confirmación antes de modificar datos.
- **Importar capturas** (Deudas → Importar captura): lee el texto de una captura o foto de DiDi, Coppel, Mercado Pago…
  (ML Kit en Android, Tesseract en el navegador; la imagen no sale del dispositivo), detecta fechas, importes y saldo
  pendiente, y muestra una tabla «Antes / Detectado». Solo se aplican los cambios que eliges y confirmas; nunca se borran
  cuotas ni se tocan las ya pagadas.
- **Cuenta y sincronización** (opcional): inicio de sesión con correo; los datos se guardan primero en el dispositivo
  y se sincronizan con Supabase; si dos dispositivos cambian a la vez, la app pregunta qué copia conservar.
- **Temas**: Clásico, Clásico oscuro, Ryusui y Nami (Ajustes → Apariencia), con colores de ingresos, gastos y pendientes adaptados a cada uno.
- **Recordatorios**: notificaciones del sistema en Android (1 semana, 2 días, 1 día antes y el día del pago, configurable,
  con hora elegida) que se cancelan al pagar y se mueven si cambia la fecha; centro de notificaciones (campana) en web y Android.
- **Reportes**: resumen mensual con comparación contra el mes anterior, gastos por categoría y pagos por deuda;
  exportación a Excel (Resumen, Movimientos, Deudas, Cuotas, Calendario, Proyección) y CSV, por periodo.
- **Ajustes** (engrane arriba a la derecha): gestión de cuentas, respaldo/restauración en archivo (JSON) e historial de cambios (auditoría).
- Dinero siempre en **centavos enteros**; operaciones **atómicas**.

## Estructura

```
lib/
  config/      Configuración pública de Supabase (URL y clave publishable)
  domain/      Motor financiero en Dart puro (sin Flutter)
    money.dart   Centavos, formato y lectura de importes sin punto flotante
    models.dart  Cuentas, movimientos, deudas, cuotas, ingresos previstos, auditoría
    ledger.dart  Reglas de negocio y cálculos (saldos, pagos, agenda, alertas)
  data/        Estado de la app y almacenamiento local
  ui/          Pantallas
supabase/migrations/  Esquema PostgreSQL con RLS y pago atómico de cuotas
test/          Pruebas (incluye las de la sección 15 de la especificación)
tool/          Generador de datos de ejemplo
```

Los datos se guardan primero **en el dispositivo** (almacenamiento local del navegador o de Android) y, si inicias
sesión, se sincronizan con Supabase. Configuración: [docs/supabase.md](docs/supabase.md).

## Cómo ejecutarlo

Requiere [Flutter](https://docs.flutter.dev/get-started/install) 3.50 o superior.

```bash
flutter pub get
```

```bash
flutter test
```

```bash
flutter run -d chrome
```

La lectura de capturas en la web necesita Tesseract en `web/tesseract/` (no se guarda en el repositorio):

```bash
bash tool/fetch_ocr_web.sh
```

Compilar la versión web (sin depender de CDN, funciona sin conexión a gstatic):

```bash
flutter build web --release --no-web-resources-cdn
```

Compilar el APK de Android (requiere Android SDK). La compilación y publicación automáticas están en [docs/publicacion.md](docs/publicacion.md):

```bash
flutter build apk --release
```

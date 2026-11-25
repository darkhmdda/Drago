# Drago

*Antes llamado provisionalmente «FinanSync» en los documentos de especificación.*

Aplicación de administración financiera personal para **web** y **Android**, hecha con Flutter.
La especificación completa está en [`docs/especificacion.md`](docs/especificacion.md).

> Regla principal: **nunca confundir el dinero que realmente tienes con el dinero que esperas recibir.**

## Estado actual: v0.2 (núcleo financiero + deudas y cuotas)

| Versión | Contenido | Estado |
|---|---|---|
| 0.1 | Saldo físico / digital / total, ingresos, gastos, transferencias, historial | ✅ |
| 0.2 | Deudas, cuotas variables, pagos y abonos parciales, saldo pendiente | ✅ |
| 0.3 | Calendario mensual/semanal, ingresos recurrentes | 🟡 Agenda de próximos eventos e ingresos previstos (sin recurrencias aún) |
| 0.4 | Notificaciones, exportación Excel/CSV | ⏳ |
| 0.5 | Proyecciones y escenarios | 🟡 Saldo proyectado básico en la agenda |
| 1.0 | Asistente, capturas, sincronización con Supabase | ⏳ (esquema SQL listo) |

### Lo que ya funciona
- **Inicio**: dinero físico, dinero digital y total disponible (solo dinero real), próximo pago, próximo ingreso, deudas pendientes, pagos del mes, resumen del mes y alertas (cuotas vencidas, pagos de la semana, saldo insuficiente, deudas cuyo monto no coincide con sus cuotas).
- **Cuentas**: varias cuentas físicas o digitales; corrección de saldo con registro del ajuste.
- **Movimientos**: ingreso, gasto, pago de deuda, transferencia (no cuenta como ingreso ni gasto) y ajuste manual; filtros por tipo y cuenta; eliminación con confirmación.
- **Deudas**: monto original independiente de las cuotas; cuotas con importe y fecha propios; flujo de pago (cuota → importe y fecha → cuenta → fecha real → confirmación → descuento único); abonos parciales; edición de cuota mostrando el valor anterior y el nuevo; la deuda se marca liquidada sola.
- **Agenda**: cuotas pendientes e ingresos previstos de los próximos 90 días, vinculados a su origen (sin duplicados), con saldo proyectado que no toca los saldos reales; permite confirmar ingresos o marcarlos como no recibidos.
- **Ajustes**: gestión de cuentas, respaldo/restauración (JSON por portapapeles) e historial de cambios (auditoría).
- Dinero siempre en **centavos enteros**; operaciones **atómicas** (se aplican sobre una copia y solo se guardan si son válidas).

## Estructura

```
lib/
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

Los datos se guardan hoy **en el dispositivo** (almacenamiento local del navegador o de Android). El esquema de
Supabase (`supabase/migrations`) ya refleja el mismo modelo para la sincronización futura.

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

Compilar la versión web (sin depender de CDN, funciona sin conexión a gstatic):

```bash
flutter build web --release --no-web-resources-cdn
```

Compilar el APK de Android (requiere Android SDK):

```bash
flutter build apk --release
```

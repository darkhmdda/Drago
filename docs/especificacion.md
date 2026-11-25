> **Nombre del proyecto:** **Drago** (definido el 25/11/2026). Durante la planificación se usó el nombre provisional «FinanSync».

Drago
Especificación funcional y técnica del proyecto

Documento base · Versión 1.0 · 25 de noviembre de 2026

DRAGO
1. Descripción general
Drago será una aplicación de administración financiera personal, disponible en dos plataformas:
- Aplicación web para computadora.
- Aplicación Android mediante APK.
Su propósito será permitir al usuario administrar su dinero, controlar deudas, organizar pagos, registrar ingresos, visualizar calendarios financieros y recibir notificaciones sobre compromisos económicos.

La aplicación estará diseñada para reproducir y mejorar el método de organización financiera que hemos desarrollado mediante conversaciones.

No será simplemente un rastreador de gastos. Será un sistema que permita conocer:
- Cuánto dinero tiene realmente el usuario.
- Cuánto dinero tiene disponible en efectivo.
- Cuánto dinero tiene en bancos y tarjetas.
- Cuánto debe pagar.
- Cuándo debe pagar.
- Cuánto dinero espera recibir.
- Cuánto dinero podría tener en el futuro.
- Qué deudas ya fueron pagadas y cuáles siguen pendientes.
Principio fundamental: el dinero real, los ingresos previstos y las simulaciones deben permanecer separados.
2. Estructura principal de la aplicación
La aplicación tendrá seis secciones principales:
1. Inicio.
2. Deudas y pagos.
3. Calendario financiero.
4. Movimientos.
5. Proyecciones.
6. Reportes y exportaciones.
También tendrá una sección de configuración para cuentas, notificaciones, seguridad y preferencias.
2.1 Inicio: saldos actuales
Esta será la pantalla principal.

Deberá mostrar dos tipos de saldo:

Dinero físico
- Efectivo disponible.
- Saldo que el usuario tiene físicamente.
Dinero digital
- Dinero disponible en bancos.
- Dinero disponible en tarjetas.
- Billeteras digitales.
Total disponible

La aplicación sumará ambos saldos:

Total = Dinero físico + Dinero digital

Ejemplo:
Cuenta	Saldo
Dinero físico	$500.00
Dinero digital	$150.00
Total disponible	$650.00

La pantalla principal también mostrará:
- Próximo pago.
- Próximo ingreso.
- Total de deudas pendientes.
- Total de pagos del mes.
- Alertas importantes.
- Resumen de ingresos y gastos.
El total disponible nunca incluirá ingresos previstos, cantidades por cobrar ni dinero hipotético.
2.2 Deudas y pagos
Esta será una de las secciones más importantes.

Permitirá registrar cualquier deuda mediante un formulario.

Datos principales:
Campo	Descripción
Nombre	DiDi Préstamos, Mercado Pago, Coppel, etc.
Monto total	Total que se debe pagar
Fecha de inicio	Fecha en que comenzó la deuda
Descripción	Información adicional
Estado	Activa, liquidada o cancelada

Cuotas individuales
Cada deuda tendrá una lista de pagos individuales.

Es importante que los pagos no tengan que ser iguales.

Por ejemplo:

Deuda: DiDi Préstamos

Monto total a pagar: $6,500.00
Cuota	Importe	Fecha
1	$750.00	01/12/2026
2	$642.00	16/12/2026
3	$120.00	01/01/2027
4	$123.00	18/01/2027

Cada cuota tendrá un control individual:
- Pagado.
- No pagado.
- Vencido.
- Cancelado.
Funcionamiento del botón de pago
Cuando el usuario marque una cuota como pagada:
1. La aplicación identificará la cuota.
2. Mostrará su importe y fecha.
3. Preguntará desde qué cuenta se realizó el pago.
4. Permitirá registrar la fecha real de pago.
5. Solicitará confirmación.
6. Registrará el gasto.
7. Descontará el importe del saldo correspondiente.
8. Actualizará el total pendiente de la deuda.
9. Actualizará el calendario.
10. Cancelará los recordatorios correspondientes.
Ejemplo:
DiDi Préstamos
Monto original

$6,500.00

Total pagado

$750.00


Saldo pendiente
$5,750.00



Ejemplo ilustrativo de progreso de pago.

La aplicación debe distinguir entre el monto original de la deuda y la suma de las cuotas pendientes. Si existen cargos, ajustes o diferencias, no debe asumir que ambas cifras coinciden.
Pagos parciales
En una futura ampliación, deberá permitir abonar una parte de una cuota.

Ejemplo:
- Cuota: $750.
- Primer abono: $300.
- Segundo abono: $450.
- Estado final: pagado.
Cada abono deberá registrarse como movimiento independiente y vinculado a la cuota.
3. Calendario financiero
Esta sección mostrará todos los ingresos y pagos programados.

Tendrá tres vistas:
- Mensual.
- Semanal.
- Agenda de próximos eventos.
Ingresos personalizados
El usuario podrá configurar ingresos recurrentes.

Ejemplo:
Día	Descripción	Importe
Sábado	Ingreso semanal	$400
Martes	Ingreso adicional	$100

El usuario podrá modificar:
- Cantidad.
- Fecha.
- Frecuencia.
- Descripción.
- Cuenta en la que recibirá el dinero.
Frecuencias disponibles:
- Diaria.
- Semanal.
- Quincenal.
- Mensual.
- Personalizada.
Cada ingreso aparecerá en el calendario como previsto.

Importante: un ingreso previsto no aumentará el saldo real.

Cuando el usuario confirme que recibió el dinero, pasará a estado recibido y se registrará en su cuenta.
Pagos de deudas
El calendario también mostrará automáticamente las cuotas registradas en la sección de deudas.

Ejemplo:
Fecha	Evento	Importe	Estado
01 dic.	DiDi Préstamos	$750	Pendiente
05 dic.	Ingreso semanal	$400	Previsto
06 dic.	Coppel audífonos	$72	Pendiente
16 dic.	DiDi Préstamos	$642	Pendiente

Los eventos tendrán colores y etiquetas diferentes para distinguir ingresos, gastos, pagos realizados y pagos pendientes.

Los pagos no deben duplicarse al mostrarlos en el calendario: el evento debe estar vinculado a la cuota original.
4. Sistema de notificaciones
La aplicación tendrá recordatorios automáticos.

Configuración inicial recomendada:
- Una semana antes.
- Dos días antes.
- Un día antes.
- El día del vencimiento.
Ejemplo:
Recordatorio de pago

Tienes un pago próximo de $750.00 MXN correspondiente a DiDi Préstamos.

Fecha límite: 1 de diciembre.

Te recomendamos realizarlo uno o dos días antes del vencimiento.

Ejemplo de notificación.

Las notificaciones deberán:
- Mostrar el nombre de la deuda.
- Mostrar el importe.
- Mostrar la fecha límite.
- Evitar notificaciones de pagos ya realizados.
- Actualizarse cuando cambie una cuota.
- Permitir configurar la anticipación.
- Evitar recordatorios duplicados.
Se utilizarán notificaciones del sistema en Android y notificaciones del navegador en web cuando estén disponibles y autorizadas.

También existirá un centro de notificaciones dentro de la aplicación.
5. Registro de movimientos
Esta sección almacenará todos los movimientos reales.

Tipos:
- Ingreso.
- Gasto.
- Pago de deuda.
- Transferencia.
- Ajuste manual.
Cada movimiento tendrá:
- Fecha.
- Importe.
- Tipo.
- Descripción.
- Cuenta.
- Categoría.
- Referencia a deuda o cuota, cuando corresponda.
Ejemplo:
Fecha	Movimiento	Cuenta	Importe
25 nov.	Saldo inicial	Físico	$500
26 nov.	Comida	Físico	-$80
28 nov.	Ingreso semanal	Físico	+$400
01 dic.	Pago DiDi	Físico	-$750

Las transferencias entre efectivo y banco no deben contabilizarse como ingresos o gastos.
6. Proyecciones financieras
Esta sección permitirá anticipar el estado financiero futuro.

Tendrá dos modalidades:

Situación real

Muestra únicamente el dinero confirmado y los movimientos realizados.

Situación proyectada

Calcula el dinero que podría tener el usuario considerando:
- Saldo actual.
- Ingresos previstos.
- Pagos pendientes.
- Gastos programados.
Ejemplo:
Fecha	Movimiento	Ingreso	Gasto	Saldo proyectado
25 nov.	Saldo inicial	—	—	$500
28 nov.	Ingreso previsto	$400	—	$900
01 dic.	DiDi	—	$750	$150
05 dic.	Ingreso previsto	$400	—	$550

Las proyecciones nunca modificarán los saldos reales.
Simulaciones
El usuario podrá crear escenarios independientes:
- Ingreso semanal de $400.
- Ingreso semanal de $500.
- Una semana sin ingresos.
- Un gasto extraordinario.
- Adelantar una cuota.
Podrá guardar y eliminar escenarios sin alterar los registros reales.
7. Reportes y exportación
La aplicación deberá permitir exportar información.

Formatos:
- Excel .xlsx.
- CSV.
- PDF, como función adicional.
Estructura del Excel
El archivo podría contener las siguientes hojas:
Hoja	Contenido
Resumen	Saldos y situación financiera
Movimientos	Historial de ingresos y gastos
Deudas	Montos originales y pendientes
Cuotas	Fechas, importes y estados
Calendario	Ingresos y pagos
Proyecciones	Escenarios futuros

El usuario podrá elegir:
- Exportar un mes.
- Exportar dos meses.
- Exportar un año.
- Exportar un periodo personalizado.
- Exportar solamente las deudas.
- Exportar todos los movimientos.
Los registros reales y previstos deberán distinguirse claramente.
8. Asistente financiero con lenguaje natural
Una de las funciones que más valor aportaría sería un asistente conversacional.

El usuario podría escribir instrucciones normales, como hacemos en este chat.

Ejemplos:
Instrucción	Acción
Tengo 500	Actualizar saldo físico
Digital tengo 150	Actualizar saldo digital
Recibí 400	Registrar ingreso recibido
Pagué los 750 de DiDi	Registrar pago de cuota
Cambió la cuota a 650	Proponer actualización
¿Cuánto debo en diciembre?	Consultar pagos
Simula diciembre con 400 semanales	Crear proyección

El asistente debe interpretar las instrucciones y utilizar funciones internas controladas.

No debe modificar datos financieros importantes sin confirmación cuando exista ambigüedad.
Reglas de interpretación
- Si el usuario dice «tengo $500», se refiere al dinero físico.
- Si menciona explícitamente el dinero digital, se actualiza esa cuenta.
- Si confirma un ingreso, se registra como recibido.
- Si menciona un ingreso futuro, permanece previsto.
- Si corrige un saldo, la cifra confirmada reemplaza el cálculo anterior.
- Si una cuota ya está pagada, no se vuelve a descontar.
- Si hay varias cuotas posibles, debe preguntar cuál corresponde.
La IA será opcional. La aplicación debe funcionar perfectamente sin ella.
9. Importación de capturas y comprobantes
Una función adicional sería permitir cargar fotografías o capturas de las aplicaciones financieras.

El sistema intentará identificar:
- Nombre de la institución.
- Importe.
- Fecha.
- Cuotas.
- Deuda pendiente.
- Próximos vencimientos.
Después comparará los datos con los registros actuales.

Ejemplo:
Concepto	Importe anterior	Importe nuevo
DiDi 1 diciembre	$796.39	$763.31
DiDi 16 diciembre	$674.47	$713.39

El sistema presentará las diferencias y esperará autorización antes de modificar el calendario.
10. Arquitectura tecnológica
Mi recomendación es utilizar una arquitectura multiplataforma.
Flutter
Será el frontend principal.

Permitirá desarrollar:
- Aplicación web.
- APK Android.
- Posible aplicación de escritorio en el futuro.
Ventajas:
- Una sola base de código.
- Diseño adaptable.
- Buen rendimiento.
- Compatibilidad con Android y navegadores.
Supabase
Será el backend.

Se utilizará para:
- Base de datos PostgreSQL.
- Autenticación.
- Sincronización.
- Almacenamiento de comprobantes.
- Seguridad mediante políticas RLS.
- Operaciones de backend.
Python
Se utilizará para servicios auxiliares cuando sea conveniente:
- Procesamiento de imágenes.
- OCR.
- Integración con modelos de IA.
- Generación de reportes.
- Procesamiento de archivos.
SQLite
Podrá utilizarse para almacenamiento local y funcionamiento sin conexión.

La aplicación sincronizará los cambios cuando vuelva a existir conexión.
11. Diseño de la base de datos
No se recomienda almacenar toda la información en una única tabla.

Se propone la siguiente estructura:
Tabla	Responsabilidad
accounts	Cuentas físicas y digitales
transactions	Ingresos, gastos y transferencias
debts	Deudas
installments	Cuotas individuales
installment_payments	Abonos a cuotas
scheduled_items	Ingresos y gastos previstos
recurrences	Reglas de ingresos recurrentes
projections	Simulaciones
projection_events	Eventos de cada simulación
notifications	Recordatorios
attachments	Comprobantes y capturas
categories	Categorías de movimientos
audit_logs	Historial de modificaciones

Reglas técnicas
- Utilizar UUID como identificadores.
- Usar claves foráneas.
- Almacenar dinero con precisión decimal o centavos enteros.
- Evitar tipos de punto flotante para cantidades monetarias.
- Utilizar transacciones de base de datos para operaciones financieras.
- Mantener un registro de auditoría.
12. Seguridad y privacidad
Como se manejará información financiera personal, la seguridad será una prioridad.

La aplicación deberá:
- Proteger las sesiones.
- Utilizar HTTPS.
- Aplicar RLS en Supabase.
- Evitar almacenar contraseñas bancarias.
- No almacenar CVV ni números completos de tarjetas.
- Proteger las claves de acceso.
- Mantener copias de seguridad.
- Permitir exportar y recuperar los datos.
- Solicitar confirmación antes de eliminar información importante.
No será necesario conectar directamente los bancos en la primera versión.
13. Reglas de negocio fundamentales
Estas reglas deben implementarse desde la primera versión.
1. El dinero físico y digital siempre estarán separados.
2. El total disponible será la suma de ambos.
3. Los ingresos previstos no aumentan el saldo real.
4. Los ingresos solo se contabilizan al confirmarse.
5. Cada cuota tiene su propio importe y vencimiento.
6. Los pagos realizados se descuentan una sola vez.
7. Las transferencias no son ingresos ni gastos.
8. Las simulaciones no modifican datos reales.
9. Los pagos realizados dejan de generar recordatorios.
10. Las correcciones de saldo deben quedar registradas.
11. El dinero que otras personas deben al usuario no se considera disponible hasta recibirlo.
12. Los movimientos importantes deben poder rastrearse.
13. La IA nunca debe ejecutar modificaciones financieras sin validaciones.
14. Las operaciones financieras deben ser atómicas para evitar registros incompletos.
14. Plan de desarrollo
Recomiendo dividir el desarrollo en versiones.
Versión 0.1
Núcleo financiero
- Flutter configurado para web y Android.
- Inicio.
- Saldo físico.
- Saldo digital.
- Total disponible.
- Registro de ingresos y gastos.
- Transferencias.
- Historial.


Versión 0.2
Deudas y cuotas
- Registro de deudas.
- Cuotas variables.
- Fechas individuales.
- Estado pagado/pendiente.
- Registro de abonos.
- Cálculo de deuda restante.


Versión 0.3
Calendario
- Ingresos previstos.
- Ingresos recurrentes.
- Calendario mensual.
- Calendario semanal.
- Integración automática de pagos.


Versión 0.4
Notificaciones y reportes
- Recordatorios.
- Alertas.
- Exportación Excel.
- Exportación CSV.
- Resúmenes mensuales.


Versión 0.5
Proyecciones
- Ingresos futuros.
- Gastos previstos.
- Escenarios.
- Comparación de simulaciones.


Versión 1.0
Asistente inteligente
- Chat financiero.
- Interpretación de instrucciones.
- Importación de capturas.
- Sincronización.
- Respaldo y restauración.


15. Pruebas que debe superar
Antes de considerar estable el programa, debe superar estas pruebas:
Prueba	Resultado esperado
Físico $200 + digital $150	Total $350
Gasto de $80 en efectivo	Físico baja $80
Transferencia de $100	Total no cambia
Ingreso previsto de $400	Saldo real no cambia
Confirmar ingreso de $400	Saldo aumenta $400
Crear cuotas variables	Conserva cada importe
Marcar cuota como pagada	Descuenta una sola vez
Cambiar fecha de cuota	Actualiza calendario
Pagar cuota	Cancela sus recordatorios
Crear simulación	No modifica datos reales
Exportar Excel	Datos completos y separados
Cerrar y abrir aplicación	Información persistente

16. Orden recomendado de implementación
Cuando comencemos a programar, propongo seguir este orden:
1. Crear el repositorio.
2. Configurar Flutter.
3. Preparar Supabase.
4. Diseñar y validar la base de datos.
5. Crear la interfaz principal.
6. Implementar las cuentas físicas y digitales.
7. Implementar los movimientos.
8. Implementar deudas y cuotas variables.
9. Implementar el registro de pagos.
10. Implementar el calendario.
11. Implementar ingresos recurrentes.
12. Implementar notificaciones.
13. Implementar exportación.
14. Implementar proyecciones.
15. Incorporar el asistente conversacional.
16. Realizar pruebas completas.
17. Generar APK y publicar la versión web.
17. Recomendaciones adicionales
Además de tus propuestas, recomiendo incorporar estas funcionalidades:
A. Historial de saldos
Poder consultar cuánto dinero tenías en una fecha determinada y cómo llegaste a ese saldo.
B. Alertas de saldo insuficiente
Si una proyección indica que no habrá suficiente dinero para cubrir un pago, mostrar una advertencia anticipada.
C. Priorización de pagos
Mostrar qué pagos vencen primero y cuánto dinero se necesita para cubrirlos.
D. Confirmación de ingresos
Los ingresos recurrentes deben poder confirmarse individualmente. Si no llegan, permanecen previstos o pueden marcarse como no recibidos.
E. Respaldo manual
Permitir descargar un respaldo de toda la información para evitar perder el historial.
F. Edición controlada
Si una cuota cambia, mostrar el importe anterior y el nuevo antes de guardar.
18. Conclusión
Drago debe ser una herramienta de administración financiera personal, no solamente una calculadora de gastos.

Su mayor valor será centralizar la información que actualmente organizamos mediante conversaciones:
- Saldos.
- Deudas.
- Cuotas.
- Ingresos.
- Calendarios.
- Recordatorios.
- Proyecciones.
- Reportes.
La prioridad debe ser construir un núcleo financiero confiable. Después se añadirán las funciones de automatización e inteligencia artificial.

La IA será un complemento que facilite el uso, pero la base de datos y el motor de cálculos serán los responsables de mantener la información correcta.

La regla más importante de todo el proyecto: nunca confundir el dinero que realmente tienes con el dinero que esperas recibir.
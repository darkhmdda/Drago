import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/app_lock.dart';

class AppLockScope extends InheritedNotifier<AppLock> {
  const AppLockScope({super.key, required AppLock lock, required super.child}) : super(notifier: lock);
  static AppLock of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppLockScope>()!.notifier!;
}

/// Cubre la app con la pantalla de bloqueo mientras esté bloqueada.
class LockGate extends StatelessWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final lock = AppLockScope.of(context);
    return Stack(children: [
      // La app sigue viva debajo (no se pierde lo que estabas haciendo),
      // pero no se ve ni recibe toques.
      ExcludeSemantics(excluding: lock.locked, child: Offstage(offstage: lock.locked, child: child)),
      // Overlay propio: la pantalla de bloqueo vive fuera del Navigator.
      if (lock.locked) Positioned.fill(child: Overlay(initialEntries: [OverlayEntry(builder: (_) => const _LockScreen())])),
    ]);
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen();
  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  final _pin = TextEditingController();
  String? _error;
  int _fails = 0;
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lock = AppLockScope.of(context);
    // Con el bloqueo del teléfono, se pide la huella automáticamente al aparecer.
    if (!_asked && lock.method == LockMethod.device) {
      _asked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => lock.unlockWithDevice());
    }
  }

  void _tryPin() {
    final lock = AppLockScope.of(context);
    if (lock.unlockWithPin(_pin.text)) return;
    setState(() {
      _fails++;
      _error = 'PIN incorrecto';
      _pin.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lock = AppLockScope.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Image.asset('assets/icon/emblema_256.png', width: 96, height: 96),
                const SizedBox(height: 16),
                Text('Drago está bloqueado', style: theme.textTheme.titleLarge),
                const SizedBox(height: 24),
                if (lock.method == LockMethod.device)
                  FilledButton.icon(
                    onPressed: lock.unlockWithDevice,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Desbloquear'),
                  )
                else ...[
                  TextField(
                    controller: _pin,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 8,
                    style: const TextStyle(fontSize: 24, letterSpacing: 8),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(labelText: 'PIN', errorText: _error, border: const OutlineInputBorder(), counterText: ''),
                    onSubmitted: (_) => _tryPin(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: FilledButton(onPressed: _tryPin, child: const Text('Desbloquear'))),
                  if (_fails >= 3) ...[
                    const SizedBox(height: 12),
                    Text(
                      '¿Olvidaste el PIN? Por seguridad no se puede recuperar. Puedes quitar el bloqueo borrando los datos de este '
                      'navegador (Configuración del sitio → Borrar datos). Si usas una cuenta, al iniciar sesión tus datos vuelven de la nube.',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:material_ui/material_ui.dart';

import '../data/supabase_remote.dart';
import '../data/sync_scope.dart';
import 'common.dart';

/// Iniciar sesión o crear cuenta para respaldar y sincronizar.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _create = false;
  var _busy = false;
  var _obscure = true;
  String? _error;
  String? _info;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_create ? 'Crear cuenta' : 'Iniciar sesión')),
      body: Form(
        key: _formKey,
        child: PageBody(children: [
          const Text('Con una cuenta, tus datos se respaldan en la nube y puedes usar Drago en la computadora y en el '
              'teléfono. Sin cuenta, la app funciona igual pero solo en este dispositivo.'),
          gap,
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Correo', border: OutlineInputBorder()),
            validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Escribe un correo válido',
          ),
          gap,
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            autofillHints: [_create ? AutofillHints.newPassword : AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Contraseña',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) => (v ?? '').length < (_create ? 8 : 1)
                ? (_create ? 'Usa al menos 8 caracteres' : 'Escribe tu contraseña')
                : null,
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_info != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_info!)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_create ? 'Crear cuenta' : 'Iniciar sesión'),
          ),
          TextButton(
            onPressed: _busy ? null : () => setState(() {
              _create = !_create;
              _error = null;
              _info = null;
            }),
            child: Text(_create ? 'Ya tengo cuenta: iniciar sesión' : 'No tengo cuenta: crear una'),
          ),
          if (!_create) TextButton(onPressed: _busy ? null : _reset, child: const Text('Olvidé mi contraseña')),
        ]),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = SyncScope.of(context).auth!;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      if (_create) {
        final ready = await auth.signUp(_email.text, _password.text);
        if (!ready) {
          setState(() {
            _create = false;
            _info = 'Cuenta creada. Te enviamos un correo: abre el enlace para confirmarla y después inicia sesión aquí.';
          });
          return;
        }
      } else {
        await auth.signIn(_email.text, _password.text);
      }
      if (mounted) Navigator.pop(context, true);
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) {
      setState(() => _error = 'Escribe tu correo arriba para enviarte el enlace.');
      return;
    }
    try {
      await SyncScope.of(context).auth!.resetPassword(_email.text);
      setState(() => _info = 'Si existe una cuenta con ese correo, te enviamos un enlace para cambiar la contraseña.');
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    }
  }
}

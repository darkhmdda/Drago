import 'package:drago/data/app_lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('PIN: se guarda como hash con sal y desbloquea solo con el correcto', () async {
    final lock = AppLock();
    await lock.load();
    expect(lock.enabled, isFalse);
    await lock.enablePin('4821');
    final p = await SharedPreferences.getInstance();
    expect(p.getString('drago.lock.hash'), isNot(contains('4821')));
    expect(p.getString('drago.lock.hash')!.length, 64);

    final reopened = AppLock();
    await reopened.load();
    expect(reopened.locked, isTrue); // al abrir, bloqueada
    expect(reopened.unlockWithPin('0000'), isFalse);
    expect(reopened.locked, isTrue);
    expect(reopened.unlockWithPin('4821'), isTrue);
    expect(reopened.locked, isFalse);
  });

  test('Desactivar borra el PIN', () async {
    final lock = AppLock();
    await lock.load();
    await lock.enablePin('1234');
    await lock.disable();
    final again = AppLock();
    await again.load();
    expect(again.enabled, isFalse);
    expect(again.locked, isFalse);
  });
}

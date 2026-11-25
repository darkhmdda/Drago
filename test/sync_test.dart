import 'dart:convert';

import 'package:drago/data/app_state.dart';
import 'package:drago/data/storage.dart';
import 'package:drago/data/sync_service.dart';
import 'package:drago/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servidor falso con el mismo contrato que push_ledger / pull_ledger.
class FakeCloud {
  int version = 0;
  String data = '{"schemaVersion":2}';
  bool online = true;
}

class FakeRemote implements SyncRemote {
  final FakeCloud cloud;
  @override
  String? userId = 'u1';
  FakeRemote(this.cloud);
  @override
  String? get userEmail => 'a@b.c';

  @override
  Future<Map<String, dynamic>> pull() async {
    if (!cloud.online) throw const SyncFailure('Sin conexión');
    return {...jsonDecode(cloud.data) as Map<String, dynamic>, 'syncVersion': cloud.version};
  }

  @override
  Future<int> remoteVersion() async {
    if (!cloud.online) throw const SyncFailure('Sin conexión');
    return cloud.version;
  }

  @override
  Future<int> push(int baseVersion, Map<String, dynamic> data) async {
    if (!cloud.online) throw const SyncFailure('Sin conexión');
    if (baseVersion != cloud.version) throw const SyncConflict();
    cloud.data = jsonEncode(data);
    return ++cloud.version;
  }
}

Future<(AppState, SyncService)> device(FakeCloud cloud, String name) async {
  final app = await AppState.open(MemoryLedgerStorage());
  final sync = SyncService(app, FakeRemote(cloud), debounce: Duration.zero, keyPrefix: name);
  await sync.init();
  return (app, sync);
}

String cashOf(AppState a) => a.ledger.accounts.firstWhere((x) => x.kind == AccountKind.physical).id;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Primer dispositivo sube sus datos; el segundo los descarga', () async {
    final cloud = FakeCloud();
    final (a, sa) = await device(cloud, 'A');
    await a.run((l) => l.setBalance(accountId: cashOf(a), newBalance: 50000));
    await sa.sync();
    expect(cloud.version, 1);
    expect(sa.status, SyncStatus.idle);

    final (b, sb) = await device(cloud, 'B');
    await sb.sync();
    expect(b.ledger.totalAvailable, 50000);
    expect(sb.status, SyncStatus.idle);
  });

  test('Cambios en ambos lados: conflicto sin perder datos', () async {
    final cloud = FakeCloud();
    final (a, sa) = await device(cloud, 'A');
    await a.run((l) => l.setBalance(accountId: cashOf(a), newBalance: 50000));
    await sa.sync();
    final (b, sb) = await device(cloud, 'B');
    await sb.sync();

    await a.run((l) => l.addExpense(accountId: cashOf(a), amount: 8000, date: DateTime.now()));
    await sa.sync(); // nube: 420
    await b.run((l) => l.addIncome(accountId: cashOf(b), amount: 40000, date: DateTime.now()));
    await sb.sync(); // B tenía cambios sin subir
    expect(sb.status, SyncStatus.conflict);
    expect(b.ledger.totalAvailable, 90000); // nada se pisó
    expect(sb.conflict!.remote.totalAvailable, 42000);

    await sb.resolveConflict(keepThisDevice: true);
    expect(sb.status, SyncStatus.idle);
    expect(jsonDecode(cloud.data)['transactions'].length, 2);

    await sa.sync(); // A no tenía cambios: descarga la copia elegida
    expect(a.ledger.totalAvailable, 90000);
  });

  test('Elegir la copia de la nube', () async {
    final cloud = FakeCloud();
    final (a, sa) = await device(cloud, 'A');
    await a.run((l) => l.setBalance(accountId: cashOf(a), newBalance: 50000));
    await sa.sync();
    final (b, sb) = await device(cloud, 'B');
    await b.run((l) => l.setBalance(accountId: cashOf(b), newBalance: 100));
    await sb.sync(); // B tenía datos propios antes de iniciar sesión
    expect(sb.status, SyncStatus.conflict);
    await sb.resolveConflict(keepThisDevice: false);
    expect(b.ledger.totalAvailable, 50000);
    expect(cloud.version, 1);
  });

  test('Sin conexión: los cambios quedan pendientes y se suben después', () async {
    final cloud = FakeCloud()..online = false;
    final (a, sa) = await device(cloud, 'A');
    await a.run((l) => l.setBalance(accountId: cashOf(a), newBalance: 50000));
    await sa.sync();
    expect(sa.status, SyncStatus.offline);
    expect(a.ledger.totalAvailable, 50000);
    cloud.online = true;
    await sa.sync();
    expect(sa.status, SyncStatus.idle);
    expect(cloud.version, 1);
  });

  test('Cambio local dispara la subida automática', () async {
    final cloud = FakeCloud();
    final (a, sa) = await device(cloud, 'A');
    await sa.sync();
    await a.run((l) => l.setBalance(accountId: cashOf(a), newBalance: 777));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(cloud.version, 1);
    expect(sa.hasPendingChanges, isFalse);
  });

  test('Revisión rápida: solo descarga si la nube cambió', () async {
    final cloud = FakeCloud();
    final (a, sa) = await device(cloud, 'A');
    await a.run((l) => l.setBalance(accountId: cashOf(a), newBalance: 50000));
    await sa.sync();
    final (b, sb) = await device(cloud, 'B');
    await sb.sync();
    final remote = sb.remote as FakeRemote;
    final before = cloud.data;
    await sb.checkRemote(); // sin cambios en la nube: no descarga
    expect(cloud.data, before);
    await a.run((l) => l.addExpense(accountId: cashOf(a), amount: 8000, date: DateTime.now()));
    await sa.sync();
    await sb.checkRemote(); // la nube cambió: descarga
    expect(b.ledger.totalAvailable, 42000);
    expect(remote.userId, 'u1');
  });

  test('Sin sesión no se sincroniza nada', () async {
    final cloud = FakeCloud();
    final (a, sa) = await device(cloud, 'A');
    (sa.remote as FakeRemote).userId = null;
    await a.run((l) => l.setBalance(accountId: cashOf(a), newBalance: 777));
    await sa.sync();
    expect(cloud.version, 0);
    expect(sa.status, SyncStatus.signedOut);
  });
}

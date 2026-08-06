import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/features/home/session_maintenance_queue.dart';

void main() {
  test('serializes work and coalesces multiple requests', () async {
    final queue = SessionMaintenanceQueue();
    final firstGate = Completer<void>();
    final secondRan = Completer<void>();
    final order = <int>[];

    queue.enqueue(() async {
      order.add(1);
      await firstGate.future;
    });
    queue.enqueue(() async => order.add(2));
    queue.enqueue(() async {
      order.add(3);
      secondRan.complete();
    });

    expect(order, [1]);
    firstGate.complete();
    await secondRan.future;
    expect(order, [1, 3]);
  });

  test('close waits for active work and drops queued work', () async {
    final queue = SessionMaintenanceQueue();
    final gate = Completer<void>();
    var ranQueued = false;

    queue.enqueue(() => gate.future);
    queue.enqueue(() async => ranQueued = true);

    final closing = queue.close();
    expect(queue.isClosed, isTrue);
    gate.complete();
    await closing;
    expect(ranQueued, isFalse);
  });

  test('reopen permits work after a completed close', () async {
    final queue = SessionMaintenanceQueue();
    await queue.close();
    var ran = false;

    queue.reopen();
    await queue.enqueue(() async => ran = true);

    expect(ran, isTrue);
    expect(queue.isClosed, isFalse);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:billing_app/core/supabase/session_manager.dart';
import 'package:billing_app/features/billing/data/services/checkout_service.dart';
import 'package:billing_app/features/billing/data/services/refund_service.dart';
import 'package:billing_app/features/billing/data/services/shift_service.dart';
import 'package:billing_app/features/billing/domain/entities/cart_item.dart';
import 'package:billing_app/features/product/domain/entities/product.dart';
import 'package:billing_app/features/sync/data/services/offline_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _business = '10000000-0000-4000-8000-000000000001';
const _branch = '10000000-0000-4000-8000-000000000002';
const _cashier = '10000000-0000-4000-8000-000000000003';
const _sale = '10000000-0000-4000-8000-000000000004';
const _saleItem = '10000000-0000-4000-8000-000000000005';
const _refund = '10000000-0000-4000-8000-000000000006';
const _shift = '10000000-0000-4000-8000-000000000007';
const _intent = '10000000-0000-4000-8000-000000000008';
const _cart = '10000000-0000-4000-8000-000000000009';
const _items = [
  CartItem(
    product: Product(
      id: '10000000-0000-4000-8000-000000000010',
      name: 'Fictional test item',
      barcode: 'fictional-001',
      price: 10,
      stock: 3,
    ),
  ),
];
const _allocations = [
  SplitPaymentInput(method: 'cash', amount: 4),
  SplitPaymentInput(method: 'momo', amount: 6),
];
const _intentRows = [
  {'intent_id': _intent, 'cart_id': _cart, 'reference': 'fictional-reference'},
];

// Only platform connectivity is substituted. All queue persistence and financial
// service methods under test are the production implementations.
class _QueueWithConnectivity extends OfflineQueueService {
  bool online = true;

  @override
  Future<bool> isOnline() async => online;
}

class _MemoryPkceStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}

class _Outcome<T> {
  final T? value;
  final Object? error;

  const _Outcome({this.value, this.error});
}

Future<_Outcome<T>> _observe<T>(Future<T> Function() action) async {
  try {
    return _Outcome(value: await action());
  } catch (error) {
    return _Outcome(error: error);
  }
}

http.Response _json(Object? body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

String _fixtureJwt() {
  String encode(Map<String, Object> data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return '${encode({'alg': 'none', 'typ': 'JWT'})}.'
      '${encode({'sub': _cashier, 'exp': 4102444800})}.fictional-signature';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late _QueueWithConnectivity queue;
  late MockClient transport;
  late Future<http.Response> Function(http.Request) respond;
  final requests = <http.Request>[];

  Map<String, dynamic> body(http.Request request) =>
      jsonDecode(request.body) as Map<String, dynamic>;

  http.Request rpc(String name) {
    final matching = requests
        .where((request) => request.url.path == '/rest/v1/rpc/$name')
        .toList();
    expect(matching, hasLength(1),
        reason: 'Service must reach the real SDK RPC');
    expect(matching.single.method, 'POST');
    return matching.single;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ledgermind-contract-');
    Hive.init(directory.path);
    await SessionManager.init();
    await SessionManager.setSession(
      businessId: _business,
      branchId: _branch,
      roleName: 'cashier',
      permissions: {'process_sales'},
    );
    queue = _QueueWithConnectivity();
    await queue.init();
    requests.clear();
    respond = (request) async =>
        throw StateError('Unexpected mocked request: ${request.url.path}');
    transport = MockClient((request) async {
      // No fallback HTTP client exists. An unrecognized request fails locally.
      expect(request.url.host, 'phase1a.invalid');
      expect(
          request.url.path,
          isIn([
            '/rest/v1/rpc/process_checkout_cash',
            '/rest/v1/rpc/create_checkout_intent',
            '/rest/v1/rpc/process_refund',
            '/rest/v1/rpc/open_shift',
            '/rest/v1/rpc/close_shift',
          ]));
      requests.add(request);
      final response = await respond(request);
      return http.Response(
        response.body,
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    });
    await Supabase.initialize(
      url: 'https://phase1a.invalid',
      publishableKey: 'sb_publishable_fictional_phase1a_only',
      httpClient: transport,
      debug: false,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryPkceStorage(),
      ),
    );
    await Supabase.instance.client.auth.setInitialSession(jsonEncode({
      'access_token': _fixtureJwt(),
      'refresh_token': 'fictional-refresh-token',
      'token_type': 'bearer',
      'user': {'id': _cashier, 'aud': 'authenticated'},
    }));
    expect(Supabase.instance.client.auth.currentUser?.id, _cashier);
    expect(SessionManager.businessId, _business);
    expect(SessionManager.branchId, _branch);
    expect(requests, isEmpty);
  });

  tearDown(() async {
    await Supabase.instance.dispose();
    transport.close();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  group('Fixture controls', () {
    test('installed SDK decodes scalar UUID without a legacy response wrapper',
        () async {
      respond = (_) async => _json(_sale);
      final decoded =
          await Supabase.instance.client.rpc('process_checkout_cash');
      rpc('process_checkout_cash');
      expect(decoded, isA<String>());
      expect(decoded, _sale);
    });

    test('installed SDK decodes RETURNS TABLE as a row list', () async {
      respond = (_) async => _json(_intentRows);
      final decoded =
          await Supabase.instance.client.rpc('create_checkout_intent');
      rpc('create_checkout_intent');
      expect(decoded, isA<List<dynamic>>());
      expect(decoded, _intentRows);
    });
  });

  group('M-01 decoded RPC contracts', () {
    test('cash checkout returns the successful server UUID', () async {
      respond = (_) async => _json(_sale);
      final outcome = await _observe(() => CheckoutService(
            offlineQueueService: queue,
          ).processCashCheckout(items: _items, discount: 0));
      expect(body(rpc('process_checkout_cash'))['p_total_amount'], 1000);
      expect(outcome.error, isNull,
          reason: 'Decoded UUID must be consumed directly: ${outcome.error}');
      expect(outcome.value?.saleId, _sale);
      expect(outcome.value?.wasQueued, isFalse);
      expect(await queue.pendingCount(), 0);
    });

    test('checkout intent consumes the single decoded TABLE row', () async {
      respond = (_) async => _json(_intentRows);
      final outcome = await _observe(() => CheckoutService(
            offlineQueueService: queue,
          ).createCheckoutIntent(items: _items, discount: 0, method: 'momo'));
      expect(body(rpc('create_checkout_intent'))['p_method'], 'momo');
      expect(outcome.error, isNull,
          reason: 'Decoded row list must be accepted: ${outcome.error}');
      expect(outcome.value?.intentId, _intent);
      expect(outcome.value?.cartId, _cart);
      expect(outcome.value?.reference, 'fictional-reference');
    });

    test('refund returns the successful decoded server UUID', () async {
      respond = (_) async => _json(_refund);
      final outcome = await _observe(() => RefundService(
            offlineQueueService: queue,
          ).processRefund(saleId: _sale, items: {_saleItem: 1}));
      expect(body(rpc('process_refund'))['p_sale_id'], _sale);
      expect(outcome.error, isNull,
          reason: 'Decoded refund UUID must be accepted: ${outcome.error}');
      expect(outcome.value, _refund);
      expect(await queue.pendingCount(), 0);
    });

    test('open shift returns the successful decoded server UUID', () async {
      respond = (_) async => _json(_shift);
      final outcome = await _observe(() => ShiftService().openShift(20));
      expect(body(rpc('open_shift'))['p_opening_float'], 20);
      expect(outcome.error, isNull,
          reason: 'Decoded shift UUID must be accepted: ${outcome.error}');
      expect(outcome.value, _shift);
    });

    test('close shift accepts a successful decoded void response', () async {
      respond = (_) async => _json(null);
      final outcome = await _observe(() => ShiftService().closeShift(
            shiftId: _shift,
            actualCash: 20,
          ));
      expect(body(rpc('close_shift'))['p_shift_id'], _shift);
      expect(outcome.error, isNull,
          reason:
              'Successful void response must be accepted: ${outcome.error}');
    });
  });

  group('M-02 ambiguous cash response', () {
    test('durable fallback retains the first transmitted idempotency key',
        () async {
      respond = (_) async => throw http.ClientException(
            'Fictional lost acknowledgement after request reached server',
          );
      final result = await CheckoutService(offlineQueueService: queue)
          .processCashCheckout(items: _items, discount: 0);
      final firstRequest = body(rpc('process_checkout_cash'));
      expect(firstRequest['p_idempotency_key'], isA<String>());
      expect(firstRequest['p_business_id'], _business);
      expect(firstRequest['p_cashier_id'], _cashier);
      expect(result.wasQueued, isTrue);
      await Hive.box<String>('offline_queue').flush();
      await Hive.box<String>('offline_queue').close();
      final reopenedQueue = _QueueWithConnectivity();
      await reopenedQueue.init();
      final pending = await reopenedQueue.getPendingSales();
      expect(pending, hasLength(1));
      expect(pending.single.id, result.queueId);
      expect(pending.single.payload['items'], firstRequest['p_items']);
      expect(pending.single.idempotencyKey, firstRequest['p_idempotency_key'],
          reason:
              'An ambiguous committed request must replay with its original '
              'identity, including after storage reopen');
    });
  });

  group('M-05 split tender contracts', () {
    test('4 cash plus 6 MoMo never invokes full-total cash finalization',
        () async {
      respond = (_) async => _json(_sale);
      final outcome = await _observe(() => CheckoutService(
            offlineQueueService: queue,
          ).processSplitCheckout(
            items: _items,
            discount: 0,
            payments: _allocations,
          ));
      expect(_allocations.fold<double>(0, (sum, p) => sum + p.amount), 10);
      expect(requests, isNotEmpty,
          reason:
              'Online split submission must reach its transaction boundary');
      final fullCash = requests.where((request) =>
          request.url.path == '/rest/v1/rpc/process_checkout_cash' &&
          body(request)['p_total_amount'] == 1000);
      expect(fullCash, isEmpty,
          reason: 'Only GHS4 was tendered in cash. Full GHS10 cash RPC has '
              'already been sent before any subsequent decode error '
              '(${outcome.error})');
    });

    test('offline split retains allocations or rejects without a cash queue',
        () async {
      queue.online = false;
      final outcome = await _observe(() => CheckoutService(
            offlineQueueService: queue,
          ).processSplitCheckout(
            items: _items,
            discount: 0,
            payments: _allocations,
          ));
      expect(requests, isEmpty);
      final pending = await queue.getPendingOperations();
      if (outcome.error != null) {
        expect(pending, isEmpty,
            reason: 'An offline rejection must not leave a full-cash retry');
        return;
      }
      expect(outcome.value?.wasQueued, isTrue);
      expect(pending, hasLength(1));
      expect(pending.single.payload['total'], 10);
      // This does not prescribe a future split schema. Any durable explicit
      // cash/MoMo attribution suffices; the current ordinary cash payload has none.
      final serialized = jsonEncode(pending.single.payload);
      expect(serialized, contains('momo'),
          reason: 'Durable split data must retain the noncash tender. A plain '
              'sale queue item will replay as a full cash sale');
      expect(serialized, contains('cash'));
      expect(outcome.value?.saleId, isNull);
    });
  });

  group('M-09 refund idempotency contracts', () {
    test('online response-loss fallback persists its first transmitted key',
        () async {
      respond = (_) async => throw http.ClientException(
            'Fictional lost refund acknowledgement',
          );
      final queueId = await RefundService(offlineQueueService: queue)
          .processRefund(saleId: _sale, items: {_saleItem: 1});
      final first = body(rpc('process_refund'));
      final pending = await queue.getPendingRefunds();
      expect(pending, hasLength(1));
      expect(pending.single.id, queueId);
      expect(first['p_items'], [
        {'sale_item_id': _saleItem, 'quantity': 1},
      ]);
      expect(first['p_idempotency_key'], pending.single.idempotencyKey,
          reason: 'The first refund attempt and durable retry must share a '
              'non-null idempotency key');
    });

    test('two replays of one persisted refund transmit the same captured key',
        () async {
      queue.online = false;
      final service = RefundService(offlineQueueService: queue);
      final queueId = await service.processRefund(
        saleId: _sale,
        items: {_saleItem: 1},
        reason: 'Fictional return',
      );
      expect(requests, isEmpty);
      final op = (await queue.getPendingRefunds()).single;
      expect(op.id, queueId);
      expect(op.idempotencyKey, isNotEmpty);
      respond = (_) async => _json(_refund);
      // Observe both calls even when M-01 fails after HTTP success. The request
      // contract exists before response decoding and remains independently testable.
      await _observe(() => service.processQueuedRefund(op));
      await _observe(() => service.processQueuedRefund(op));
      final replayRequests = requests
          .where((r) => r.url.path == '/rest/v1/rpc/process_refund')
          .map(body)
          .toList();
      expect(replayRequests, hasLength(2));
      for (final request in replayRequests) {
        expect(request['p_business_id'], _business);
        expect(request['p_branch_id'], _branch);
        expect(request['p_sale_id'], _sale);
        expect(request['p_items'], op.payload['items']);
      }
      expect(
        replayRequests.map((r) => r['p_idempotency_key']).toList(),
        [op.idempotencyKey, op.idempotencyKey],
        reason: 'The persisted refund identity must reach SQL on every retry',
      );
    });
  });
}

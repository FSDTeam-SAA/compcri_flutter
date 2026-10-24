import 'dart:convert';

import 'package:compcri_flutter/core/api.dart';
import 'package:compcri_flutter/core/api_client.dart';
import 'package:compcri_flutter/core/client_identity.dart';
import 'package:compcri_flutter/core/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String ok(Object? data) => jsonEncode({'success': true, 'data': data});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const sarah = {
    'code': 'SARAH20',
    'influencerName': 'Sarah Martinez',
    'discountType': 'PERCENTAGE',
    'discountValue': 20,
    'offeringId': 'influencer_20',
  };

  test('applies, reads back and removes an influencer code', () async {
    final seen = <String>[];
    final coupons = CouponApi(
      ApiClient(
        client: MockClient((request) async {
          seen.add('${request.method} ${request.url.path}');
          if (request.method == 'POST') {
            expect(jsonDecode(request.body), {'code': 'sarah20'});
            return http.Response(ok(sarah), 200);
          }
          if (request.method == 'GET') return http.Response(ok(null), 200);
          return http.Response(ok({'removed': true}), 200);
        }),
      ),
    );
    final applied = await coupons.apply('sarah20');
    expect(applied.code, 'SARAH20');
    expect(applied.offeringId, 'influencer_20');
    expect(applied.discountLabel, '20%');
    expect(await coupons.applied(), isNull);
    await coupons.remove();
    expect(seen, [
      'POST /api/v1/coupons/apply',
      'GET /api/v1/coupons/applied',
      'DELETE /api/v1/coupons/applied',
    ]);
  });

  test('surfaces why a code cannot be used', () async {
    final coupons = CouponApi(
      ApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'success': false,
              'error': {
                'code': 'COUPON_EXPIRED',
                'message': 'This code has expired',
                'requestId': 't',
              },
            }),
            409,
          ),
        ),
      ),
    );
    await expectLater(
      coupons.apply('OLD'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'COUPON_EXPIRED'),
      ),
    );
  });

  test('labels fixed discounts in dollars', () {
    final code = InfluencerCode.fromJson({
      ...sarah,
      'discountType': 'FIXED',
      'discountValue': 2.5,
    });
    expect(code.discountLabel, r'$2.50');
  });

  test('sends no identity off a phone', () async {
    await ClientIdentity.prepare();
    final headers = <String, String>{};
    ClientIdentity.stamp(headers);
    expect(headers, isEmpty);
    var posted = false;
    await ClientIdentity.reportLaunch(
      client: MockClient((_) async {
        posted = true;
        return http.Response(ok({}), 200);
      }),
    );
    expect(posted, isFalse);
  });
}

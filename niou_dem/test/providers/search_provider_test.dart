import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fojem_passager/core/geo/geo_location.dart';
import 'package:fojem_passager/providers/search_provider.dart';
import 'package:fojem_passager/services/current_location.dart';

const _here = GeoLocation(lat: 14.72, lng: -17.265, address: kCurrentPositionLabel);
const _rufisque = GeoLocation(lat: 14.72, lng: -17.265, address: 'Péage, Rufisque', locality: 'Rufisque');
const _thies = GeoLocation(lat: 14.791, lng: -16.926, address: 'Thiès', locality: 'Thiès');

void main() {
  test('nothing is prefilled', () {
    final search = SearchProvider();
    expect(search.origin, isNull);
    expect(search.destination, isNull);
    expect(search.hasSearch, isFalse);
  });

  test('the current position becomes the departure, then gets its address', () async {
    final search = SearchProvider();
    final address = Completer<GeoLocation?>();

    await search.locateOrigin(locate: () async => _here, describe: (_) => address.future);
    expect(search.origin, same(_here));
    expect(search.departure, 'Ma position');
    expect(search.isCurrentPosition(search.origin), isTrue);
    expect(search.isLocating, isFalse);

    address.complete(_rufisque);
    await pumpEventQueue();
    expect(search.origin, same(_rufisque));
    expect(search.departure, 'Ma position · Rufisque');
  });

  test('locating runs once and never replaces a chosen departure', () async {
    final search = SearchProvider()..setOrigin(_thies);
    var calls = 0;
    Future<GeoLocation?> locate() async {
      calls++;
      return _here;
    }

    await search.locateOrigin(locate: locate, describe: (_) async => null);
    expect(calls, 0);
    expect(search.departure, 'Thiès');

    final fresh = SearchProvider();
    await fresh.locateOrigin(locate: locate, describe: (_) async => null);
    await fresh.locateOrigin(locate: locate, describe: (_) async => null);
    expect(calls, 1);
  });

  test('a refused permission leaves the departure empty', () async {
    final search = SearchProvider();
    await search.locateOrigin(locate: () async => null, describe: (_) async => null);
    expect(search.origin, isNull);
    expect(search.isLocating, isFalse);
  });

  test('the address follows the position when departure and arrival are swapped', () async {
    final search = SearchProvider();
    final address = Completer<GeoLocation?>();
    await search.locateOrigin(locate: () async => _here, describe: (_) => address.future);
    search
      ..setDestination(_thies)
      ..swap();

    address.complete(_rufisque);
    await pumpEventQueue();
    expect(search.origin, same(_thies));
    expect(search.arrival, 'Ma position · Rufisque');
  });
}

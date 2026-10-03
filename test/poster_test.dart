import 'dart:typed_data';

import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/store.dart';
import 'package:compcri_flutter/features/events.dart';
import 'package:compcri_flutter/features/poster.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show FakeBackend, bootedStore;

/// A 1×1 transparent PNG, so no test touches the network.
final _pixel = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

void main() {
  test('the poster keeps its size from the API', () {
    final asset = MediaAsset.parse({
      '_id': 'm1',
      'secureUrl': 'https://cdn.example.com/flyer.png',
      'width': 1080,
      'height': 1350,
    })!;
    expect(asset.aspectRatio, closeTo(.8, .001));
    expect(
      MediaAsset.parse({'secureUrl': 'https://x/y.png'})!.aspectRatio,
      isNull,
    );
  });

  testWidgets('tapping the poster opens it full screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: PosterImage(image: MemoryImage(_pixel), heroTag: 'flyer'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PosterViewer), findsNothing);

    await tester.tap(find.byKey(const ValueKey('poster-image')));
    await tester.pumpAndSettle();
    expect(find.byType(PosterViewer), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(PosterViewer), findsNothing);
  });

  testWidgets('editing an event shows its image, ready to change or remove', (
    tester,
  ) async {
    final store = await bootedStore(tester, FakeBackend());
    final event = CalendarEvent.fromJson({
      '_id': '65b1f77bcf86cd7994390999',
      'calendarId': '65b1f77bcf86cd7994390100',
      'title': 'Launch party',
      'startsAt': '2030-01-05T20:00:00.000Z',
      'endsAt': '2030-01-05T22:00:00.000Z',
      'posterMediaId': {
        '_id': '65b1f77bcf86cd7994390abc',
        'secureUrl': 'https://cdn.example.com/flyer.png',
        'width': 1080,
        'height': 1350,
      },
      '__v': 0,
    });
    await tester.pumpWidget(
      StoreScope(
        notifier: store,
        child: MaterialApp(
          theme: appTheme,
          home: EventForm(event: event),
        ),
      ),
    );
    await tester.pump();

    final poster = tester.widget<PosterImage>(find.byType(PosterImage));
    expect(
      (poster.image as NetworkImage).url,
      'https://cdn.example.com/flyer.png',
    );
    expect(poster.aspectRatio, closeTo(.8, .001));
    expect(find.byKey(const ValueKey('poster-change')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('poster-remove')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('poster-remove')));
    await tester.pump();
    expect(find.byType(PosterImage), findsNothing);
    expect(find.byKey(const ValueKey('poster-add')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

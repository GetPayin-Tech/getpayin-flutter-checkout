import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_flutter_checkout/src/webview/external_link.dart';

void main() {
  group('openExternalLink', () {
    test('hands the link to the phone and says nothing when it opens',
        () async {
      final asked = <String>[];
      var failed = false;

      await openExternalLink(
        'mybank://authorise/3ds/1',
        () => failed = true,
        launcher: (url) async {
          asked.add(url);

          return true;
        },
      );

      expect(asked, <String>['mybank://authorise/3ds/1']);
      expect(failed, isFalse);
    });

    /*
     * A 3-D Secure step that sends the payer to a bank app which is not installed would
     * otherwise leave them on a checkout whose button does nothing.
     */
    test('reports a failure when nothing on the phone can open the link',
        () async {
      var failed = false;

      await openExternalLink(
        'mybank://authorise/3ds/1',
        () => failed = true,
        launcher: (_) async => false,
      );

      expect(failed, isTrue);
    });

    test('reports a failure when the launcher throws rather than answering',
        () async {
      var failed = false;

      await openExternalLink(
        'mybank://authorise/3ds/1',
        () => failed = true,
        launcher: (_) async => throw StateError('no activity found'),
      );

      expect(failed, isTrue);
    });
  });
}

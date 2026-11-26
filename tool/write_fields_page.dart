import 'dart:io';

import 'package:getpayin_checkout/src/sheet/fields_page.dart';

/// Writes the card fields page this package expects you to host.
///
/// ```sh
/// dart run tool/write_fields_page.dart https://pay.getpayin.com > paylink-fields.html
/// ```
///
/// Name every PayLink whose wallet payments the page takes, the main one first: the wallet
/// button loads the SDK only from those.
///
/// The committed copy at `doc/paylink-fields.html` is this output with the SDK URL left as
/// a placeholder, and a test fails if the two ever drift apart.
void main(List<String> arguments) {
  final hosts =
      arguments.isEmpty ? const <String>['<YOUR-PAYLINK-HOST>'] : arguments;
  final sdks = <String>[
    for (final host in hosts) '$host/sdk/paylink-fields-v1.js',
  ];

  stdout.write(
    buildFieldsPageHtml(sdkUrl: sdks.first, otherSdkUrls: sdks.sublist(1)),
  );
}

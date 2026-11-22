import 'dart:io';

import 'package:getpayin_checkout/src/sheet/fields_page.dart';

/// Writes the card fields page this package expects you to host.
///
/// ```sh
/// dart run tool/write_fields_page.dart https://pay.getpayin.com > paylink-fields.html
/// ```
///
/// The committed copy at `doc/paylink-fields.html` is this output with the SDK URL left as
/// a placeholder, and a test fails if the two ever drift apart.
void main(List<String> arguments) {
  final host = arguments.isEmpty ? '<YOUR-PAYLINK-HOST>' : arguments.first;

  stdout.write(buildFieldsPageHtml(sdkUrl: '$host/sdk/paylink-fields-v1.js'));
}

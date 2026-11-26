import 'dart:convert';
import 'dart:io';

import 'package:getpayin_checkout/src/sheet/fields_page.dart';

/// Why a test that runs the card page's own script is skipped, or null when it can run.
///
/// The script runs under Node, which the CI machine has. A machine without it skips these
/// rather than failing them.
final String? skipWithoutNode = _hasNode() ? null : 'needs Node on the PATH';

bool _hasNode() {
  try {
    return Process.runSync('node', const <String>['--version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Runs the card page's own script under Node, then [scenario], and hands back every
/// message the page posted to the host, in order.
///
/// A string check on the page proves the page says something, not that it does it. This
/// runs it, against a stand-in for PayLink's SDK and as much of a browser as the page uses.
/// [scenario] is the body of an async function with these in scope:
///
/// - `host`: the page's `window.__paylinkHost`.
/// - `sdk`: the stand-in's state. `sdk.handlers[name]` fires one of the SDK's events, and
///   `sdk.pays` holds every `pay()` call as `{parts, resolve, reject}`.
/// - `tick()`: waits for what the page queued to run.
/// - `location`: the page's address, whose `hash` the page reads and writes.
Future<List<Map<String, Object?>>> runFieldsPage(
  String scenario, {
  String hash = '',
}) async {
  final html = buildFieldsPageHtml(
    sdkUrl: 'https://pay.example.com/sdk/paylink-fields-v1.js',
  );
  final script =
      RegExp(r'<script>([\s\S]*?)</script>').firstMatch(html)!.group(1)!;
  final folder = Directory.systemTemp.createTempSync('fields_page');
  final file = File('${folder.path}/page.js')
    ..writeAsStringSync(_harness(script, scenario, hash));

  try {
    final run = await Process.run('node', <String>[file.path]);

    if (run.exitCode != 0) {
      throw StateError('The page script failed under Node: ${run.stderr}');
    }

    return const LineSplitter()
        .convert(run.stdout as String)
        .where((line) => line.isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, Object?>)
        .toList();
  } finally {
    folder.deleteSync(recursive: true);
  }
}

String _harness(String script, String scenario, String hash) => '''
var elements = {};

function element(id) {
  if (!elements[id]) {
    elements[id] = {
      id: id, hidden: true, value: '', placeholder: '', dataset: {},
      style: { setProperty: function () {} },
      addEventListener: function () {}
    };
  }

  return elements[id];
}

globalThis.window = globalThis;
globalThis.location = {
  hash: ${jsonEncode(hash)},
  href: 'https://shop.example.com/paylink-fields.html' + ${jsonEncode(hash)}
};
globalThis.document = {
  documentElement: { style: { setProperty: function () {} } },
  head: { appendChild: function (tag) { setTimeout(function () { tag.onload(); }, 0); } },
  createElement: function () { return {}; },
  getElementById: element,
  querySelectorAll: function () { return []; }
};
window[${jsonEncode(fieldsChannelName)}] = {
  postMessage: function (message) { process.stdout.write(message + '\\n'); }
};

var sdk = { handlers: {}, pays: [], options: null };

globalThis.PayLink = {
  fields: function (options) {
    sdk.options = options;

    return {
      on: function (name, handler) { sdk.handlers[name] = handler; },
      mount: function () { return Promise.resolve({ amountMinor: 9742, currency: 'USD' }); },
      pay: function (parts) {
        return new Promise(function (resolve, reject) {
          sdk.pays.push({ parts: parts, resolve: resolve, reject: reject });
        });
      },
      destroy: function () {}
    };
  }
};

function tick() {
  return new Promise(function (resolve) { setTimeout(resolve, 0); });
}

$script

var host = window.__paylinkHost;

(async function () {
$scenario
})().catch(function (error) {
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
});
''';

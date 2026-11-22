import 'package:url_launcher/url_launcher.dart';

/// Opens [url] with whatever on the phone answers to it, reporting whether anything did.
typedef ExternalLinkLauncher = Future<bool> Function(String url);

/// Hands a link the checkout cannot load itself — a bank app for 3-D Secure, `tel:`,
/// `mailto:` — to the phone.
///
/// The link is launched straight away, without asking `canLaunchUrl` first. That check
/// answers false for every scheme the host app has not declared
/// (`LSApplicationQueriesSchemes` on iOS, `<queries>` on Android 11 and later), and no app
/// can declare every bank's scheme, so a bank-app step would silently do nothing. Launching
/// needs no such declaration. What may be opened at all is decided before this, by
/// `classifyNavigation`.
///
/// [onFailure] is called when nothing on the phone can open the link, which is how the payer
/// is told why the step they were sent on did nothing. Swallowing it would leave them on a
/// checkout whose button does nothing — and with the top bar hidden, no way out of the
/// screen at all, so the `open()` future would never settle.
Future<void> openExternalLink(
  String url,
  void Function() onFailure, {
  ExternalLinkLauncher? launcher,
}) async {
  try {
    final opened = await (launcher ?? _launchExternally)(url);

    if (!opened) {
      onFailure();
    }
  } catch (_) {
    onFailure();
  }
}

/// Launches a link in whatever app owns it, rather than in a browser sheet.
Future<bool> _launchExternally(String url) {
  return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

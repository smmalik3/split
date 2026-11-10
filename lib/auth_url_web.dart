// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
// Web implementation of the OAuth-return URL cleanup (see auth_url_stub.dart).
// Removes one query param and reloads the page at the cleaned URL, keeping
// every other param (e.g. an invite ?code=) intact.
import 'dart:html' as html;

void stripAuthParam(String name) {
  final uri = Uri.parse(html.window.location.href);
  final params = Map<String, String>.from(uri.queryParameters)..remove(name);
  final query = params.entries
      .map((e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  final base =
      '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';
  html.window.location.replace(query.isEmpty ? base : '$base?$query');
}

// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
// Web implementation of the CSV download helper (see download_stub.dart).
// Triggered via the conditional import in main.dart.
import 'dart:html' as html;

void downloadFile(String filename, String content) {
  final blob = html.Blob([content], 'text/csv');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)..download = filename;
  anchor.click();
  html.Url.revokeObjectUrl(url);
}

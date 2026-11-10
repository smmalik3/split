/// Non-web fallback for the CSV download helper (see download_web.dart).
/// Triggered via the conditional import in main.dart.
void downloadFile(String filename, String content) {
  throw UnsupportedError('File download is only supported on web');
}

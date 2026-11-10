import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class SplitApi {
  static final _client = http.Client();

  static Future<Map<String, dynamic>> _decode(http.Response r) async {
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 400) {
      throw ApiException(body['error'] as String? ?? 'Something went wrong (${r.statusCode})');
    }
    return body;
  }

  static Future<Map<String, dynamic>> createGroup(String name, String nickname) async {
    final r = await _client.post(
      Uri.parse('/api/groups'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'nickname': nickname}),
    );
    return _decode(r);
  }

  static Future<Map<String, dynamic>> joinGroup(String code, String nickname) async {
    final r = await _client.post(
      Uri.parse('/api/groups/${code.toUpperCase()}/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'nickname': nickname}),
    );
    return _decode(r);
  }

  static Future<Map<String, dynamic>> getGroup(String code) async {
    final r = await _client.get(Uri.parse('/api/groups/${code.toUpperCase()}'));
    return _decode(r);
  }

  static Future<Map<String, dynamic>> getBalances(String code) async {
    final r = await _client.get(Uri.parse('/api/groups/${code.toUpperCase()}/balances'));
    return _decode(r);
  }

  static Future<Map<String, dynamic>> addExpense(
    String code, {
    required int memberId,
    required String merchant,
    required String total,
    String note = '',
    String? receipt,
    String? date,
  }) async {
    final r = await _client.post(
      Uri.parse('/api/groups/${code.toUpperCase()}/expenses'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'member_id': memberId,
        'merchant': merchant,
        'total': total,
        'note': note,
        'receipt': receipt,
        'date': date,
      }),
    );
    return _decode(r);
  }

  static Future<Map<String, dynamic>> deleteExpense(String code, int expenseId) async {
    final r = await _client.delete(Uri.parse('/api/groups/${code.toUpperCase()}/expenses/$expenseId'));
    return _decode(r);
  }

  /// Uploads a receipt photo, returns the OCR parse + stored filename.
  static Future<Map<String, dynamic>> ocrReceipt(String code, XFile file) async {
    final bytes = await file.readAsBytes();
    final req = http.MultipartRequest('POST', Uri.parse('/api/groups/${code.toUpperCase()}/ocr'));
    req.files.add(http.MultipartFile.fromBytes(
      'receipt',
      bytes,
      filename: file.name,
      contentType: MediaType('image', 'jpeg'),
    ));
    final streamed = await req.send();
    final r = await http.Response.fromStream(streamed);
    return _decode(r);
  }
}

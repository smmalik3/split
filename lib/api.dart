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

  /// Bearer token for the optional Google account. Set by AuthService;
  /// null = guest. Included on every request when present.
  static String? token;

  static Map<String, String> get _authHeaders =>
      token != null ? {'Authorization': 'Bearer $token'} : {};

  static Map<String, String> get _jsonHeaders =>
      {'Content-Type': 'application/json', ..._authHeaders};

  /// Current account (requires a token). Returns {user: {id, email, name, picture_url}}.
  static Future<Map<String, dynamic>> getMe() async {
    final r = await _client.get(Uri.parse('/api/me'), headers: _authHeaders);
    return _decode(r);
  }

  /// Groups linked to the current account.
  /// Returns {groups: [{code, name, nickname, memberId}]}.
  static Future<Map<String, dynamic>> getMyGroups() async {
    final r =
        await _client.get(Uri.parse('/api/me/groups'), headers: _authHeaders);
    return _decode(r);
  }

  /// Link a guest member row to the current account (idempotent; 409 if the
  /// member is linked to someone else).
  static Future<Map<String, dynamic>> linkMember(
      String code, int memberId) async {
    final r = await _client.post(
      Uri.parse('/api/me/link'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'code': code.toUpperCase(),
        // The auth contract names the field memberId; member_id is sent too
        // so either naming the server reads is satisfied.
        'memberId': memberId,
        'member_id': memberId,
      }),
    );
    return _decode(r);
  }

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
      headers: _jsonHeaders,
      body: jsonEncode({'name': name, 'nickname': nickname}),
    );
    return _decode(r);
  }

  static Future<Map<String, dynamic>> joinGroup(String code, String nickname) async {
    final r = await _client.post(
      Uri.parse('/api/groups/${code.toUpperCase()}/join'),
      headers: _jsonHeaders,
      body: jsonEncode({'nickname': nickname}),
    );
    return _decode(r);
  }

  static Future<Map<String, dynamic>> getGroup(String code) async {
    final r = await _client.get(Uri.parse('/api/groups/${code.toUpperCase()}'), headers: _authHeaders);
    return _decode(r);
  }

  static Future<Map<String, dynamic>> getBalances(String code) async {
    final r = await _client.get(Uri.parse('/api/groups/${code.toUpperCase()}/balances'), headers: _authHeaders);
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
    String splitMode = 'equal',
    Map<String, dynamic>? splitData,
    double tax = 0,
    double tip = 0,
  }) async {
    final r = await _client.post(
      Uri.parse('/api/groups/${code.toUpperCase()}/expenses'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'member_id': memberId,
        'merchant': merchant,
        'total': total,
        'note': note,
        'receipt': receipt,
        'date': date,
        'split_mode': splitMode,
        'split_data': splitData,
        'tax': tax,
        'tip': tip,
      }),
    );
    return _decode(r);
  }

  static Future<Map<String, dynamic>> createSettlement(
    String code, {
    required int fromMemberId,
    required int toMemberId,
    required double amount,
  }) async {
    final r = await _client.post(
      Uri.parse('/api/groups/${code.toUpperCase()}/settlements'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'from_member_id': fromMemberId,
        'to_member_id': toMemberId,
        'amount': amount,
      }),
    );
    return _decode(r);
  }

  static Future<Map<String, dynamic>> deleteSettlement(String code, int id) async {
    final r = await _client.delete(Uri.parse('/api/groups/${code.toUpperCase()}/settlements/$id'), headers: _authHeaders);
    return _decode(r);
  }

  static Future<Map<String, dynamic>> createNudge(
    String code, {
    required int fromMemberId,
    required int toMemberId,
    required double amount,
  }) async {
    final r = await _client.post(
      Uri.parse('/api/groups/${code.toUpperCase()}/nudges'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'from_member_id': fromMemberId,
        'to_member_id': toMemberId,
        'amount': amount,
      }),
    );
    return _decode(r);
  }

  static Future<Map<String, dynamic>> updateMemberHandles(
    String code,
    int memberId, {
    String? venmoHandle,
    String? cashappHandle,
  }) async {
    final body = <String, dynamic>{};
    if (venmoHandle != null) body['venmo_handle'] = venmoHandle;
    if (cashappHandle != null) body['cashapp_handle'] = cashappHandle;
    final r = await _client.patch(
      Uri.parse('/api/groups/${code.toUpperCase()}/members/$memberId'),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    return _decode(r);
  }

  static Future<Map<String, dynamic>> deleteExpense(String code, int expenseId) async {
    final r = await _client.delete(Uri.parse('/api/groups/${code.toUpperCase()}/expenses/$expenseId'), headers: _authHeaders);
    return _decode(r);
  }

  /// Uploads a receipt photo, returns the OCR parse + stored filename.
  static Future<Map<String, dynamic>> ocrReceipt(String code, XFile file) async {
    final bytes = await file.readAsBytes();
    final req = http.MultipartRequest('POST', Uri.parse('/api/groups/${code.toUpperCase()}/ocr'));
    req.headers.addAll(_authHeaders);
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

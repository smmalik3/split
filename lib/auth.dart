import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'auth_url_stub.dart' if (dart.library.html) 'auth_url_web.dart';

/// A signed-in Split account (Google).
class AuthUser {
  final int id;
  final String email;
  final String name;
  final String? pictureUrl;

  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    this.pictureUrl,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as int,
        email: json['email'] as String? ?? '',
        name: json['name'] as String? ?? '',
        pictureUrl: json['picture_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'picture_url': pictureUrl,
      };

  /// Initials for the avatar fallback (first + last name initials).
  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return email.isNotEmpty ? email[0].toUpperCase() : '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

/// Optional Google account for Split. The guest flow never touches this:
/// login is opt-in, and signing out never clears the guest session or the
/// locally saved groups.
class AuthService {
  static const _tokenKey = 'split_auth_token';
  static const _userKey = 'split_auth_user';
  static const _authErrorKey = 'split_auth_error';

  /// Current signed-in user (null = logged out). Rebuild on change with a
  /// ValueListenableBuilder.
  static final ValueNotifier<AuthUser?> currentUser =
      ValueNotifier<AuthUser?>(null);

  static String? _token;
  static String? get token => _token;
  static bool get isLoggedIn => _token != null && currentUser.value != null;

  /// Authorization header for authed calls (empty when logged out).
  static Map<String, String> get headers =>
      _token != null ? {'Authorization': 'Bearer $_token'} : {};

  /// Restore persisted login (no network). Called once in main().
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_tokenKey);
    final raw = prefs.getString(_userKey);
    if (t != null && t.isNotEmpty) {
      _token = t;
      SplitApi.token = t;
      if (raw != null && raw.isNotEmpty) {
        try {
          currentUser.value =
              AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        } catch (_) {
          // Corrupt cached user: keep the token; the user can sign in again
          // to refresh it.
        }
      }
    }
  }

  /// Start Google login: opens the server's OAuth start URL in a new tab.
  /// Google redirects back to the server, which redirects to the app root
  /// with `?token=<session token>`.
  static Future<void> login() async {
    final ok = await launchUrl(
      Uri.parse('/api/auth/google/start'),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) throw StateError('Could not open Google login.');
  }

  /// Handle an OAuth return on app start.
  /// Returns 'token' if a fresh token was consumed, 'error' if Google login
  /// failed, null otherwise. Consuming a param reloads the page at the
  /// cleaned URL (the param is stripped, any ?code= invite param is kept),
  /// so on web the outcome is also recorded in SharedPreferences for the
  /// fresh load to pick up: a failed login sets the auth-error flag, and
  /// linkCurrentSession runs on the fresh load because the token is
  /// restored by init().
  static Future<String?> handleLaunch() async {
    final params = Uri.base.queryParameters;
    final token = params['token'];
    final error = params['auth_error'];
    if (token != null && token.isNotEmpty) {
      await _storeToken(token);
      try {
        final me = await SplitApi.getMe();
        final user = AuthUser.fromJson(me['user'] as Map<String, dynamic>);
        await _storeUser(user);
      } catch (_) {
        // Token didn't yield a user (bad/expired token): drop it and treat
        // it as a failed login.
        await logout();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_authErrorKey, '1');
        stripAuthParam('token');
        return 'error';
      }
      stripAuthParam('token');
      return 'token';
    }
    if (error != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_authErrorKey, '1');
      stripAuthParam('auth_error');
      return 'error';
    }
    return null;
  }

  /// True if a failed Google login was recorded for this load (set by
  /// handleLaunch, cleared by the caller after showing it once).
  static Future<bool> takeAuthError() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_authErrorKey) != '1') return false;
    await prefs.remove(_authErrorKey);
    return true;
  }

  /// Sign out of the Google account. The guest session and My Groups are
  /// untouched.
  static Future<void> logout() async {
    _token = null;
    SplitApi.token = null;
    currentUser.value = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  /// Link the current guest session's member row to this account.
  /// Idempotent server-side; a 409 (member belongs to someone else) and any
  /// other failure are ignored silently.
  static Future<void> linkCurrentSession() async {
    if (!isLoggedIn) return;
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('split_code');
    final memberId = prefs.getInt('split_member_id');
    if (code == null || memberId == null) return;
    try {
      await SplitApi.linkMember(code, memberId);
    } catch (_) {
      // 409 or anything else: leave the member unlinked.
    }
  }

  static Future<void> _storeToken(String token) async {
    _token = token;
    SplitApi.token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<void> _storeUser(AuthUser user) async {
    currentUser.value = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }
}

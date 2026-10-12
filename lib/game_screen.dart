import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

const String kSupabaseUrl = 'https://cbfbeovcawqkhkcumpzi.supabase.co';
const String kAuthScheme = 'io.supabase.khamin';
const String kAuthRedirect = '$kAuthScheme://login-callback';

/// يعرض اللعبة (صفحة HTML داخل التطبيق).
/// - تسجيل الدخول عبر Google/Facebook يتم في متصفح النظام (Google يمنعه داخل WebView)،
///   ثم تعود الجلسة إلى اللعبة عبر رابط التطبيق.
/// - لاحقاً: شريط الصوت العائم (LiveKit) يوضع فوق هذه الشاشة.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final WebViewController _controller;
  StreamSubscription<Uri>? _linkSub;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0C0A13))
      ..addJavaScriptChannel('KhaminBridge', onMessageReceived: _onBridgeMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadFlutterAsset('assets/game/index.html');

    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
      platform.setOnPlatformPermissionRequest((request) async {
        final mic = await Permission.microphone.request();
        if (mic.isGranted) {
          await request.grant();
        } else {
          await request.deny();
        }
      });
    }

    final links = AppLinks();
    _linkSub = links.uriLinkStream.listen(_onAuthLink);
    links.getInitialLink().then((u) {
      if (u != null) _onAuthLink(u);
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  Future<void> _onBridgeMessage(JavaScriptMessage m) async {
    try {
      final msg = jsonDecode(m.message) as Map<String, dynamic>;
      if (msg['type'] == 'oauth') {
        final provider = (msg['provider'] as String?) ?? 'google';
        if (provider != 'google' && provider != 'facebook') return;
        final url = Uri.parse('$kSupabaseUrl/auth/v1/authorize').replace(
          queryParameters: {'provider': provider, 'redirect_to': kAuthRedirect},
        );
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  // عودة تسجيل الدخول: io.supabase.khamin://login-callback#access_token=...&refresh_token=...
  void _onAuthLink(Uri uri) {
    if (uri.scheme != kAuthScheme) return;
    final params = Uri.splitQueryString(uri.fragment.isNotEmpty ? uri.fragment : uri.query);
    final access = params['access_token'];
    final refresh = params['refresh_token'];
    if (access == null || refresh == null) return;
    final js = 'window.__khaminSetSession(${jsonEncode(access)}, ${jsonEncode(refresh)});';
    _controller.runJavaScript(js);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_loading) const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }
}

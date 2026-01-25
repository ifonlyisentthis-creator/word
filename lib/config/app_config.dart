class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.revenueCatApiKey,
    required this.serverSecret,
    required this.revenueCatEntitlementId,
    required this.webViewerBaseUrl,
    required this.supabaseAuthRedirectUrl,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String revenueCatApiKey;
  final String serverSecret;
  final String revenueCatEntitlementId;
  final String webViewerBaseUrl;
  final String supabaseAuthRedirectUrl;

  factory AppConfig.fromEnv() {
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    const revenueCatApiKey = String.fromEnvironment('REVENUECAT_API_KEY');
    const serverSecret = String.fromEnvironment('SERVER_SECRET');
    const revenueCatEntitlementId =
        String.fromEnvironment('REVENUECAT_ENTITLEMENT_ID');
    const webViewerBaseUrl = String.fromEnvironment('WEB_VIEWER_BASE_URL');
    const supabaseAuthRedirectUrl =
        String.fromEnvironment('SUPABASE_AUTH_REDIRECT_URL');

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'Missing Supabase configuration. Pass SUPABASE_URL and SUPABASE_ANON_KEY '
        'via --dart-define.',
      );
    }

    if (revenueCatApiKey.isEmpty) {
      throw StateError(
        'Missing RevenueCat key. Pass REVENUECAT_API_KEY via --dart-define.',
      );
    }

    if (serverSecret.isEmpty) {
      throw StateError(
        'Missing SERVER_SECRET. Pass SERVER_SECRET via --dart-define.',
      );
    }

    return const AppConfig(
      supabaseUrl: supabaseUrl,
      supabaseAnonKey: supabaseAnonKey,
      revenueCatApiKey: revenueCatApiKey,
      serverSecret: serverSecret,
      revenueCatEntitlementId: revenueCatEntitlementId.isEmpty
          ? 'AfterWord Pro'
          : revenueCatEntitlementId,
      webViewerBaseUrl: webViewerBaseUrl.isEmpty
          ? 'https://afterword-app.com'
          : webViewerBaseUrl,
      supabaseAuthRedirectUrl: supabaseAuthRedirectUrl.isEmpty
          ? 'afterword://login-callback'
          : supabaseAuthRedirectUrl,
    );
  }
}

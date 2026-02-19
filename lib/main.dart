import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';

import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'package:google_fonts/google_fonts.dart';

import 'package:provider/provider.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';

import 'screens/auth_gate.dart';

import 'services/auth_controller.dart';

import 'services/push_service.dart';

import 'services/revenuecat_controller.dart';
import 'services/theme_provider.dart';

late AppConfig _appConfig;
late RevenueCatController _revenueCatController;
late AuthController _authController;
final ThemeProvider _themeProvider = ThemeProvider();

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  GoogleFonts.config.allowRuntimeFetching = false;

  // Init everything WHILE native splash is visible (no black screen)
  await _initServices();

  runApp(const AfterwordApp());
}

Future<void> _initServices() async {
  final config = AppConfig.fromEnv();
  _appConfig = config;

  try {
    // ONLY block on Firebase + Supabase (parallel, ~500ms)
    await Future.wait([
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS))
        Firebase.initializeApp(),
      Supabase.initialize(
        url: config.supabaseUrl,
        anonKey: config.supabaseAnonKey,
        authOptions: FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
        debug: kDebugMode,
      ),
    ]);

    // Create controllers (sync constructors, instant)
    _revenueCatController = RevenueCatController(
      entitlementId: config.revenueCatEntitlementId,
    );
    _authController = AuthController(
      supabaseClient: Supabase.instance.client,
      revenueCatController: _revenueCatController,
      redirectUrl: config.supabaseAuthRedirectUrl,
      pushService: PushService(client: Supabase.instance.client),
    );

    // Load cached theme/soul fire from local storage BEFORE first frame
    // prevents the theme flicker (purple default → user's theme)
    await _themeProvider.loadCached();

    // Quick sync init: reads cached session + starts listener (<1ms)
    // AuthGate will know auth state immediately — no wrong screen flash
    _authController.quickInit();

    // Heavy network stuff (RevenueCat, push, login) deferred to after UI
  } catch (e) {
    debugPrint('Bootstrap error: $e');
  }
}

class AfterwordApp extends StatefulWidget {
  const AfterwordApp({super.key});

  @override
  State<AfterwordApp> createState() => _AfterwordAppState();
}

class _AfterwordAppState extends State<AfterwordApp> {
  static final ThemeData _cachedTheme = _buildTheme();

  @override
  void initState() {
    super.initState();
    // Remove native splash after first Flutter frame is painted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
      // Heavy network init AFTER UI is visible (RevenueCat + push + login)
      Future<void>.delayed(const Duration(milliseconds: 900), _deferredInit);
    });
  }

  Future<void> _deferredInit() async {
    try {
      // Run sequentially so expensive plugin/platform work does not contend
      // during the first interaction window.
      await _revenueCatController.configure(
        apiKey: _appConfig.revenueCatApiKey,
      );
      await _authController.deferredInit();
    } catch (e) {
      debugPrint('Deferred init error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: _appConfig),

        ChangeNotifierProvider.value(value: _revenueCatController),

        ChangeNotifierProvider.value(value: _authController),

        ChangeNotifierProvider.value(value: _themeProvider),
      ],

      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          final selected = themeProvider.themeData.toFlutterTheme();
          // Use the full selected theme — only keep GoogleFonts textTheme
          final merged = selected.copyWith(textTheme: _cachedTheme.textTheme);
          return MaterialApp(
            title: 'Afterword',
            theme: merged,
            debugShowCheckedModeBanner: false,
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

ThemeData _buildTheme() {
  const brandGold = Color(0xFFFFB85C);

  const brandMint = Color(0xFF5BC0B4);

  const background = Color(0xFF0B0B0B);

  const surface = Color(0xFF121212);

  const surfaceVariant = Color(0xFF1A1A1A);

  const errorColor = Color(0xFFE57373);

  final baseTheme = ThemeData.dark(useMaterial3: true);

  final textTheme = GoogleFonts.soraTextTheme(
    baseTheme.textTheme,
  ).apply(bodyColor: Colors.white, displayColor: Colors.white);

  final refinedTextTheme = textTheme.copyWith(
    displayLarge: textTheme.displayLarge?.copyWith(
      fontWeight: FontWeight.w600,

      letterSpacing: 0.6,
    ),

    displayMedium: textTheme.displayMedium?.copyWith(
      fontWeight: FontWeight.w600,

      letterSpacing: 0.4,
    ),

    displaySmall: textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w600,

      letterSpacing: 0.3,
    ),

    headlineLarge: textTheme.headlineLarge?.copyWith(
      fontWeight: FontWeight.w600,
    ),

    headlineMedium: textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w600,
    ),

    headlineSmall: textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
    ),

    titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),

    titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),

    labelLarge: textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,

      letterSpacing: 0.4,
    ),

    labelSmall: textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,

      letterSpacing: 1.1,
    ),

    bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.5),

    bodySmall: textTheme.bodySmall?.copyWith(height: 1.4),
  );

  const colorScheme = ColorScheme.dark(
    primary: brandGold,

    secondary: brandMint,

    surface: surface,

    surfaceContainerHighest: surfaceVariant,

    error: errorColor,

    onPrimary: Color(0xFF231404),

    onSecondary: Color(0xFF051C19),

    onSurface: Colors.white,

    onError: Colors.black,
  );

  return baseTheme.copyWith(
    colorScheme: colorScheme,

    scaffoldBackgroundColor: background,

    textTheme: refinedTextTheme,

    iconTheme: const IconThemeData(color: Colors.white70),

    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0E0E0E),

      surfaceTintColor: Colors.transparent,

      elevation: 0,

      centerTitle: false,

      foregroundColor: Colors.white,
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(color: brandGold),

    dividerColor: Colors.white12,

    snackBarTheme: SnackBarThemeData(
      backgroundColor: surfaceVariant,

      contentTextStyle: refinedTextTheme.bodyMedium?.copyWith(
        color: Colors.white,
      ),

      behavior: SnackBarBehavior.floating,

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(brandGold),

        foregroundColor: WidgetStateProperty.all(const Color(0xFF231404)),

        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),

        textStyle: WidgetStateProperty.all(
          refinedTextTheme.labelLarge?.copyWith(letterSpacing: 0.4),
        ),

        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(Colors.white70),

        side: WidgetStateProperty.all(const BorderSide(color: Colors.white24)),

        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),

        textStyle: WidgetStateProperty.all(
          refinedTextTheme.labelLarge?.copyWith(letterSpacing: 0.4),
        ),

        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(brandGold),

        textStyle: WidgetStateProperty.all(
          refinedTextTheme.labelLarge?.copyWith(letterSpacing: 0.4),
        ),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,

      fillColor: surfaceVariant,

      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),

      hintStyle: refinedTextTheme.bodySmall?.copyWith(color: Colors.white38),

      labelStyle: refinedTextTheme.bodySmall?.copyWith(color: Colors.white60),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),

        borderSide: const BorderSide(color: Colors.white12),
      ),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),

        borderSide: const BorderSide(color: Colors.white12),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),

        borderSide: const BorderSide(color: brandGold, width: 1.3),
      ),
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: brandGold,

      inactiveTrackColor: Colors.white12,

      thumbColor: brandGold,

      overlayColor: brandGold.withValues(alpha: 0.2),

      trackHeight: 3,

      valueIndicatorColor: brandGold,

      valueIndicatorTextStyle: refinedTextTheme.labelSmall?.copyWith(
        color: const Color(0xFF231404),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: surfaceVariant,

      selectedColor: brandGold,

      disabledColor: surfaceVariant,

      labelStyle: refinedTextTheme.labelSmall?.copyWith(color: Colors.white70),

      secondaryLabelStyle: refinedTextTheme.labelSmall?.copyWith(
        color: const Color(0xFF231404),
      ),

      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),

      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),

        side: const BorderSide(color: Colors.white10),
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surface,

      modalBackgroundColor: surface,

      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: surface,

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),

      titleTextStyle: refinedTextTheme.titleLarge?.copyWith(
        color: Colors.white,
      ),

      contentTextStyle: refinedTextTheme.bodySmall?.copyWith(
        color: Colors.white70,
      ),
    ),

    cardTheme: CardThemeData(
      color: surface,

      elevation: 0,

      margin: EdgeInsets.zero,

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}

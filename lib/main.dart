import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'screens/auth_gate.dart';
import 'services/auth_controller.dart';
import 'services/revenuecat_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnv();
  final redirectUri = Uri.parse(config.supabaseAuthRedirectUrl);

  await Supabase.initialize(
    url: config.supabaseUrl,
    anonKey: config.supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      authCallbackUrlHostname:
          redirectUri.host.isEmpty ? null : redirectUri.host,
    ),
    debug: kDebugMode,
  );

  final revenueCatController =
      RevenueCatController(entitlementId: config.revenueCatEntitlementId);
  await revenueCatController.configure(apiKey: config.revenueCatApiKey);
  final authController = AuthController(
    supabaseClient: Supabase.instance.client,
    revenueCatController: revenueCatController,
    redirectUrl: config.supabaseAuthRedirectUrl,
  );
  await authController.initialize();
  runApp(
    AfterwordApp(
      config: config,
      revenueCatController: revenueCatController,
      authController: authController,
    ),
  );
}

class AfterwordApp extends StatelessWidget {
  const AfterwordApp({
    super.key,
    required this.config,
    required this.revenueCatController,
    required this.authController,
  });

  final AppConfig config;
  final RevenueCatController revenueCatController;
  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    final theme = _buildTheme();
    return MultiProvider(
      providers: [
        Provider.value(value: config),
        ChangeNotifierProvider.value(value: revenueCatController),
        ChangeNotifierProvider.value(value: authController),
      ],
      child: MaterialApp(
        title: 'Afterword',
        theme: theme,
        debugShowCheckedModeBanner: false,
        home: const AuthGate(),
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
  final textTheme = GoogleFonts.soraTextTheme(baseTheme.textTheme).apply(
    bodyColor: Colors.white,
    displayColor: Colors.white,
  );
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
    titleLarge: textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w600,
    ),
    titleMedium: textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w500,
    ),
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
    background: background,
    surface: surface,
    surfaceVariant: surfaceVariant,
    error: errorColor,
    onPrimary: Color(0xFF231404),
    onSecondary: Color(0xFF051C19),
    onBackground: Colors.white,
    onSurface: Colors.white,
    onError: Colors.black,
  );

  return baseTheme.copyWith(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: background,
    textTheme: refinedTextTheme,
    iconTheme: const IconThemeData(color: Colors.white70),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: Colors.white,
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: brandGold),
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
        backgroundColor: MaterialStateProperty.all(brandGold),
        foregroundColor: MaterialStateProperty.all(const Color(0xFF231404)),
        padding: MaterialStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        textStyle: MaterialStateProperty.all(
          refinedTextTheme.labelLarge?.copyWith(letterSpacing: 0.4),
        ),
        shape: MaterialStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: MaterialStateProperty.all(Colors.white70),
        side: MaterialStateProperty.all(
          const BorderSide(color: Colors.white24),
        ),
        padding: MaterialStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        textStyle: MaterialStateProperty.all(
          refinedTextTheme.labelLarge?.copyWith(letterSpacing: 0.4),
        ),
        shape: MaterialStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: MaterialStateProperty.all(brandGold),
        textStyle: MaterialStateProperty.all(
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
      overlayColor: brandGold.withOpacity(0.2),
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
      secondaryLabelStyle:
          refinedTextTheme.labelSmall?.copyWith(color: const Color(0xFF231404)),
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
    dialogTheme: DialogTheme(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: refinedTextTheme.titleLarge?.copyWith(
        color: Colors.white,
      ),
      contentTextStyle: refinedTextTheme.bodySmall?.copyWith(
        color: Colors.white70,
      ),
    ),
    cardTheme: CardTheme(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}

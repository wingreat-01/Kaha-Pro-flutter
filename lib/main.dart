import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'state/theme_provider.dart';
import 'models/user.dart';
import 'state/cart_provider.dart';
import 'state/ingredient_provider.dart';
import 'state/product_provider.dart';
import 'state/recipe_provider.dart';
import 'state/store_provider.dart';
import 'state/transaction_provider.dart';
import 'state/user_provider.dart';
import 'state/ai_assistant_provider.dart';
import 'state/payment_method_provider.dart';
import 'state/printer_provider.dart';
import 'state/currency_provider.dart';
import 'state/receipt_options_provider.dart';
import 'state/billing_provider.dart';
import 'screens/login_screen.dart';
import 'screens/store_setup_screen.dart';
import 'screens/add_self_as_staff_screen.dart';
import 'screens/home_shell.dart';
import 'config/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Phase A of the Supabase track: just establishing the connection.cd
  // ProductProvider/CartProvider/TransactionProvider/UserProvider are
  // still in-memory below — wiring those to real Supabase tables is
  // Phases D-G, not this step.
  // authFlowType is set to implicit rather than the current default
  // (pkce). PKCE ties the emailed token_hash to a code verifier
  // stored on the device that made the request -- fine for in-app
  // deep links, but password reset here is inherently cross-device:
  // the request comes from the phone, the link is opened in a
  // browser. With PKCE, that browser can never redeem it (fails with
  // a "pkce_"-prefixed token_hash rejected by verifyOtp). Implicit
  // produces an unprefixed token_hash that reset-password.html's
  // verifyOtp() can redeem from any device.
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => IngredientProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => RecipeProvider()),
        ChangeNotifierProvider(create: (_) => StoreProvider()),
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => AiAssistantProvider()),
        ChangeNotifierProvider(create: (_) => PaymentMethodProvider()),
        // ..load() restores whatever printer was saved on this device
        // in a previous session (see PrinterProvider.load).
        ChangeNotifierProvider(create: (_) => PrinterProvider()..load()),
        // ..load() restores the saved currency (symbol/decimals shown
        // everywhere amounts appear) — see CurrencyProvider.
        ChangeNotifierProvider(create: (_) => CurrencyProvider()..load()),
        // ..load() restores the per-device receipt options (VAT breakdown on/off).
        ChangeNotifierProvider(create: (_) => ReceiptOptionsProvider()..load()),
        // ..load() restores the saved theme choice (light/dark/system).
        ChangeNotifierProvider(create: (_) => ThemeProvider()..load()),
        // Not initialized here (no ..init()) -- UpgradeScreen calls
        // init() itself on open, since querying Play Console product
        // details on every app launch (even for users who never touch
        // Settings > Plan) would be wasted work for most sessions.
        ChangeNotifierProvider(create: (_) => BillingProvider()),
      ],
      child: const KahaproApp(),
    ),
  );
}

class KahaproApp extends StatefulWidget {
  const KahaproApp({super.key});

  @override
  State<KahaproApp> createState() => _KahaproAppState();
}

class _KahaproAppState extends State<KahaproApp> with WidgetsBindingObserver {
  // PIN-level session — separate from the Supabase Auth session below.
  // This is who's currently clocked in at the register.
  AppUser? _loggedInUser;

  // Bumped to force the staff_users re-check after AddSelfAsStaffScreen
  // finishes, since a plain setState() inside a StreamBuilder's own
  // FutureBuilder wouldn't otherwise know to re-run the future.
  int _staffCheckToken = 0;

  late final Stream<AuthState> _authStream;

  @override
  void initState() {
    super.initState();
    _authStream = Supabase.instance.client.auth.onAuthStateChange;
    // Needed so "System" theme mode updates live if someone flips
    // their OS dark/light setting while the app is open, rather than
    // only picking it up on next launch.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // Only matters when the user's chosen ThemeMode.system — for
    // Light/Dark this is a no-op rebuild. Cheap enough not to bother
    // checking themeProvider.mode first.
    setState(() {});
  }

  Future<bool> _hasStaffUsers() async {
    // RLS scopes staff_users to the signed-in owner's store already
    // (same assumption verify_staff_login's current_store_id() lookup
    // relies on), so this is just "does any row come back at all."
    final rows = await Supabase.instance.client
        .from('staff_users')
        .select('id')
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    // Resolve "System" down to an actual Brightness ourselves (rather
    // than only handing ThemeMode.system to MaterialApp) because
    // AppColors.* are plain static getters read directly by dozens of
    // screens — they don't go through Theme.of(context), so nothing
    // downstream of MaterialApp knows to ask it what brightness got
    // resolved. Setting AppColors.isLight explicitly here, from the
    // same resolution MaterialApp itself will use, keeps every screen
    // in sync with what's actually on screen.
    final platformBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final resolvedBrightness = switch (themeProvider.mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platformBrightness,
    };
    AppColors.isLight = resolvedBrightness == Brightness.light;

    return MaterialApp(
      title: 'MERQ',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeProvider.mode,
      home: KeyedSubtree(
        // Flipping AppColors.isLight above doesn't repaint anything by
        // itself — widgets only re-read a static getter when they
        // actually rebuild. Keying the whole home subtree on the
        // resolved brightness forces Flutter to tear down and rebuild
        // every screen from scratch on a theme change, so AppColors.*
        // values are picked up everywhere at once instead of only in
        // whatever screen happens to be visible. Trade-off: switching
        // themes resets navigation back to the root screen — an
        // acceptable one-time reset for a Settings action.
        key: ValueKey(resolvedBrightness),
        child: _loggedInUser != null
            ? HomeShell(
                user: _loggedInUser!,
                onLogout: () {
                  // This clears the PIN-level session only. It does NOT
                  // call Supabase's signOut() — doing that would also
                  // drop the owner's store session and bounce the whole
                  // device back to StoreSetupScreen, which is wrong for
                  // "next staffer, same register." A real "sign out of
                  // this store" action (e.g. from Settings) is a
                  // separate, explicit control, not part of this flow.
                  setState(() => _loggedInUser = null);
                },
              )
            : StreamBuilder<AuthState>(
                stream: _authStream,
                builder: (context, snapshot) {
                  final session = Supabase.instance.client.auth.currentSession;

                  if (session == null) {
                    return const StoreSetupScreen();
                  }

                  return FutureBuilder<bool>(
                    key: ValueKey(_staffCheckToken),
                    future: _hasStaffUsers(),
                    builder: (context, staffSnap) {
                      if (staffSnap.connectionState != ConnectionState.done) {
                        return const _RouteLoadingScreen();
                      }
                      if (staffSnap.hasError) {
                        // Fails safe to the loading view rather than a
                        // silent blank screen — a transient network blip
                        // here shouldn't strand someone on first run.
                        return const _RouteLoadingScreen();
                      }
                      if (staffSnap.data == false) {
                        return AddSelfAsStaffScreen(
                          onDone: () => setState(() => _staffCheckToken++),
                        );
                      }
                      return LoginScreen(
                        onLogin: (user) => setState(() => _loggedInUser = user),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _RouteLoadingScreen extends StatelessWidget {
  const _RouteLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

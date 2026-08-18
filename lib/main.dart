import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'models/user.dart';
import 'state/cart_provider.dart';
import 'state/ingredient_provider.dart';
import 'state/product_provider.dart';
import 'state/recipe_provider.dart';
import 'state/store_provider.dart';
import 'state/transaction_provider.dart';
import 'state/user_provider.dart';
import 'state/ai_assistant_provider.dart';
import 'screens/login_screen.dart';
import 'screens/store_setup_screen.dart';
import 'screens/add_self_as_staff_screen.dart';
import 'screens/home_shell.dart';
import 'config/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Phase A of the Supabase track: just establishing the connection.
  // ProductProvider/CartProvider/TransactionProvider/UserProvider are
  // still in-memory below — wiring those to real Supabase tables is
  // Phases D-G, not this step.
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  // TEMP — for curl-testing the ai-assistant Edge Function's credit
  // gate. Prints the access token to the terminal on any auth state
  // change (sign-in, or a saved session restoring on app start).
  // Remove this block once done testing.
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    final session = data.session;
    if (session != null) {
      print('ACCESS TOKEN: ${session.accessToken}');
    }
  });

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

class _KahaproAppState extends State<KahaproApp> {
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
    return MaterialApp(
      title: 'Kahapro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: _loggedInUser != null
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

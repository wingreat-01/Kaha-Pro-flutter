import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'models/user.dart';
import 'state/cart_provider.dart';
import 'state/product_provider.dart';
import 'state/transaction_provider.dart';
import 'state/user_provider.dart';
import 'screens/login_screen.dart';
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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
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
  AppUser? _loggedInUser;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kahapro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: _loggedInUser == null
          ? LoginScreen(
              onLogin: (user) => setState(() => _loggedInUser = user),
            )
          : HomeShell(
              user: _loggedInUser!,
              onLogout: () => setState(() => _loggedInUser = null),
            ),
    );
  }
}

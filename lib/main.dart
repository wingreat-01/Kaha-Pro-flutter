import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'state/cart_provider.dart';
import 'state/product_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_shell.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
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
  String? _loggedInUser;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kahapro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: _loggedInUser == null
          ? LoginScreen(
              onLogin: (user, pass) => setState(() => _loggedInUser = user),
            )
          : HomeShell(
              username: _loggedInUser!,
              onLogout: () => setState(() => _loggedInUser = null),
            ),
    );
  }
}

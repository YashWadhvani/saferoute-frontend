import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'state/route_state.dart';
import 'state/tts_settings.dart';
import 'screens/home_screen.dart';
import 'screens/tts_settings_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/map_detail_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => RouteState()),
        ChangeNotifierProvider(create: (_) => TtsSettings()..load()),
      ],
      child: const SafeRouteApp(),
    ),
  );
}

class SafeRouteApp extends StatelessWidget {
  const SafeRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "SafeRoute",
      theme: ThemeData(primarySwatch: Colors.indigo),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/tts_settings': (context) => const TtsSettingsScreen(),
        '/splash': (context) => const SplashScreen(),
        '/signup': (context) => const SignupScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/map_detail': (context) => const MapDetailScreen(),
        '/contacts': (context) => const ContactsScreen(),
        '/login': (context) => const LoginScreen(),
      },
    );
  }
}

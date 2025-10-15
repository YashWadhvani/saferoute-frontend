import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final contactController = TextEditingController();
  final otpController = TextEditingController();
  bool otpSent = false;

  @override
  Widget build(BuildContext context) {
  final auth = Provider.of<AuthProvider>(context, listen: false);
    return Scaffold(
      appBar: AppBar(title: const Text("SafeRoute Login")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(controller: contactController, decoration: const InputDecoration(labelText: "Email or Phone")),
            if (otpSent) TextField(controller: otpController, decoration: const InputDecoration(labelText: "Enter OTP")),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                if (!otpSent) {
                  await auth.sendOtp(contactController.text);
                  setState(() => otpSent = true);
                } else {
                  await auth.verifyOtp(contactController.text, otpController.text);
                  if (!mounted) return;
                  if (auth.isLoggedIn) {
                    navigator.pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
                  }
                }
              },
              child: Text(otpSent ? "Verify OTP" : "Send OTP"),
            )
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    contactController.dispose();
    otpController.dispose();
    super.dispose();
  }
}

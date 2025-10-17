import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'home_screen.dart';

class OtpScreen extends StatefulWidget {
  final String identifier;
  final String? name;

  const OtpScreen({super.key, required this.identifier, this.name});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();
  bool _verifying = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    return Scaffold(
      appBar: AppBar(title: const Text('Enter OTP')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Sending OTP to: ${widget.identifier}'),
            const SizedBox(height: 12),
            TextField(controller: _otpController, decoration: const InputDecoration(labelText: 'OTP')),
            const SizedBox(height: 16),
            _verifying ? const CircularProgressIndicator() : ElevatedButton(
              onPressed: () async {
                setState(() => _verifying = true);
                final nav = Navigator.of(context);
                try {
                  await auth.verifyOtp(widget.identifier, _otpController.text.trim());
                  if (!mounted) return;
                  if (auth.isLoggedIn) {
                    nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false);
                  }
                } finally {
                  if (mounted) { setState(() => _verifying = false); }
                }
              },
              child: const Text('Verify & Continue'),
            )
          ],
        ),
      ),
    );
  }
}

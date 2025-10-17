import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'otp_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _contact = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    return Scaffold(
      appBar: AppBar(title: const Text('Sign Up')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Full name'), validator: (v) => v == null || v.isEmpty ? 'Required' : null),
              const SizedBox(height: 8),
              TextFormField(controller: _contact, decoration: const InputDecoration(labelText: 'Email or phone'), validator: (v) => v == null || v.isEmpty ? 'Required' : null),
              const SizedBox(height: 16),
              _sending ? const CircularProgressIndicator() : ElevatedButton(
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;
                  setState(() => _sending = true);
                  final nav = Navigator.of(context);
                  try {
                    await auth.sendOtp(_contact.text.trim());
                    if (!mounted) return;
                    nav.push(MaterialPageRoute(builder: (_) => OtpScreen(identifier: _contact.text.trim(), name: _name.text.trim())));
                  } finally {
                    if (mounted) { setState(() => _sending = false); }
                  }
                },
                child: const Text('Create Account & Send OTP'),
              )
            ],
          ),
        ),
      ),
    );
  }
}


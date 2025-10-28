import 'package:flutter/material.dart';
import '../services/profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  late final ProfileService _service;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _service = ProfileService();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final p = await _service.fetchProfile();
    if (p != null) {
      _nameCtrl.text = p.name;
      _emailCtrl.text = p.email ?? '';
      _phoneCtrl.text = p.phone ?? '';
    }
    setState(() => _loading = false);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final ok = await _service.updateProfile({
      'name': _nameCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      if (_passwordCtrl.text.trim().isNotEmpty) 'password': _passwordCtrl.text.trim(),
    });
    setState(() => _loading = false);
    if (ok) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Update failed')));
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name'), validator: (v) => (v ?? '').trim().isEmpty ? 'Enter name' : null),
                    const SizedBox(height: 8),
                    TextFormField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
                    const SizedBox(height: 8),
                    TextFormField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
                    const SizedBox(height: 8),
                    TextFormField(controller: _passwordCtrl, decoration: const InputDecoration(labelText: 'New password (optional)'), obscureText: true),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _submit, child: const Text('Save'))
                  ],
                ),
              ),
            ),
    );
  }
}


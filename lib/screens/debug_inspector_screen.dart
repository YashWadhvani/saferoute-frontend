import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DebugInspectorScreen extends StatefulWidget {
  const DebugInspectorScreen({super.key});

  @override
  State<DebugInspectorScreen> createState() => _DebugInspectorScreenState();
}

class _DebugInspectorScreenState extends State<DebugInspectorScreen> {
  final _storage = const FlutterSecureStorage();
  String? _token;
  String? _payloadContactsJson;
  String? _payloadWrappedJson;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final t = await _storage.read(key: 'token');
    if (!mounted) return;
    setState(() => _token = t);
  }

  String _normalizePhone(String raw) {
    final trimmed = raw.trim();
    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'[^0-9+]'), '');
    if (hasPlus) return digits;
    return digits.replaceFirst(RegExp(r'^0+'), '');
  }

  Future<void> _pickContactAndBuildPayload() async {
    setState(() {
      _loading = true;
      _payloadContactsJson = null;
      _payloadWrappedJson = null;
    });
    try {
      try {
        await FlutterContacts.requestPermission();
      } catch (_) {}
      final status = await FlutterContacts.requestPermission();
      if (!status) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contacts permission denied')));
        return;
      }

      Contact? picked;
      try {
        picked = await FlutterContacts.openExternalPick();
      } catch (_) {
        final all = await FlutterContacts.getContacts(withProperties: true);
        if (all.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No contacts found')));
          return;
        }
        if (!mounted) return;
        picked = await showModalBottomSheet<Contact>(
          context: context,
          builder: (ctx) {
            return Column(
              children: [
                const SizedBox(height: 8),
                Container(height: 4, width: 48, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 8),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text('Select contact', style: TextStyle(fontWeight: FontWeight.w600))),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: all.length,
                    itemBuilder: (c, i) {
                      final cont = all[i];
                      final title = cont.displayName.isNotEmpty ? cont.displayName : (cont.phones.isNotEmpty ? cont.phones.first.number : '<no name>');
                      final subtitle = cont.phones.isNotEmpty ? cont.phones.first.number : '';
                      return ListTile(
                        title: Text(title),
                        subtitle: Text(subtitle),
                        onTap: () => Navigator.of(ctx).pop(cont),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      }

      if (picked == null) return;
      final name = picked.displayName.isNotEmpty ? picked.displayName : (picked.phones.isNotEmpty ? picked.phones.first.number : '');
      final phoneRaw = picked.phones.isNotEmpty ? picked.phones.first.number : '';
      if (phoneRaw.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selected contact has no phone')));
        return;
      }

      final normalized = _normalizePhone(phoneRaw);
      final item = {'name': name, 'phone': normalized};
      final contactsArray = [item];
      final wrapped = {'contacts': contactsArray};
      setState(() {
        _payloadContactsJson = const JsonEncoder.withIndent('  ').convert(contactsArray);
        _payloadWrappedJson = const JsonEncoder.withIndent('  ').convert(wrapped);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to build payload: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _copyToClipboard(String s, String label) async {
    await Clipboard.setData(ClipboardData(text: s));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug Inspector')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Stored token', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SelectableText(_token ?? '<no token stored>'),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy token',
                  onPressed: _token == null ? null : () => _copyToClipboard(_token!, 'Token'),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Reload token',
                  onPressed: _loadToken,
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text('Build payload from a device contact', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.import_contacts),
              label: const Text('Pick a contact and build payload'),
              onPressed: _loading ? null : _pickContactAndBuildPayload,
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_payloadWrappedJson != null) ...[
              const Text('Payload (wrapped with {contacts: [...]})', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
                  child: SingleChildScrollView(child: SelectableText(_payloadWrappedJson!)),
                ),
              ),
              Row(
                children: [
                  ElevatedButton.icon(onPressed: () => _copyToClipboard(_payloadWrappedJson!, 'Wrapped payload'), icon: const Icon(Icons.copy), label: const Text('Copy wrapped')),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(onPressed: () => _copyToClipboard(_payloadContactsJson ?? '', 'Contacts array'), icon: const Icon(Icons.copy), label: const Text('Copy array')),
                ],
              ),
            ] else if (_payloadContactsJson != null) ...[
              const Text('Payload (contacts array)', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
                  child: SingleChildScrollView(child: SelectableText(_payloadContactsJson!)),
                ),
              ),
              ElevatedButton.icon(onPressed: () => _copyToClipboard(_payloadContactsJson ?? '', 'Contacts array'), icon: const Icon(Icons.copy), label: const Text('Copy array')),
            ] else ...[
              const Spacer(),
              const Text('No payload built yet. Use the button above to pick a contact.'),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

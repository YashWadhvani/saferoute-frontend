import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../services/contacts_service.dart';
import '../models/contact.dart';

class TrustedContactsScreen extends StatefulWidget {
  const TrustedContactsScreen({super.key});

  @override
  State<TrustedContactsScreen> createState() => _TrustedContactsScreenState();
}

class _TrustedContactsScreenState extends State<TrustedContactsScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final List<ContactModel> _contacts = [];
  final List<ContactModel> _stagedContacts = [];
  bool _submittingStaged = false;
  // Common country codes shown in the picker dialog
  static const List<Map<String, String>> _kCommonCountryCodes = [
    {'label': 'India (+91)', 'code': '+91'},
    {'label': 'United States (+1)', 'code': '+1'},
    {'label': 'United Kingdom (+44)', 'code': '+44'},
    {'label': 'Australia (+61)', 'code': '+61'},
  ];
  late final ContactsService _service;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
  _service = ContactsService();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _service.fetchTrustedContacts();
    setState(() {
      _contacts.clear();
      _contacts.addAll(list);
      _loading = false;
    });
  }

  Future<void> _add() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty || phone.isEmpty) return;
    // Ensure we have a country code; prompt if missing
    final ensured = await _ensureCountryCode(phone);
    if (ensured == null) return; // user cancelled
    final c = ContactModel(name: name, phone: ensured);
    // Use addTrustedContact to post only the new contact (backend expects single object per POST)
    final updated = await _service.addTrustedContact(c);
    if (updated != null) {
      if (mounted) {
        setState(() {
          _contacts.clear();
          _contacts.addAll(updated);
          _nameCtrl.clear();
          _phoneCtrl.clear();
        });
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to add contact')));
    }
  }

  Future<void> _removeAt(int idx) async {
    final contact = _contacts[idx];
    // If contact has backend id, call DELETE /api/users/me/contacts/{contactId}
    if (contact.id != null && contact.id!.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove contact'),
          content: const Text('Remove this contact from your emergency contacts?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Remove')),
          ],
        ),
      );
      if (confirm != true) return;
      final updated = await _service.deleteTrustedContact(contact.id!);
      if (updated != null) {
        if (mounted) {
          setState(() => _contacts
            .clear());
        }
        if (mounted) setState(() => _contacts.addAll(updated));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to remove contact')));
      }
      return;
    }

    // Fallback: send updated list if contact has no id (sync state)
    // If contact has no backend id, try to find its id on the server by phone
    // and delete by id. This avoids the previous behaviour where we re-posted
    // the remaining list which caused duplicates.
    final phoneToFind = contact.phone;
    try {
      final serverList = await _service.fetchTrustedContacts();
      final match = serverList.firstWhere(
        (s) => s.phone == phoneToFind,
        orElse: () => ContactModel(name: '', phone: ''),
      );
      if (match.id != null && match.id!.isNotEmpty) {
        final updated = await _service.deleteTrustedContact(match.id!);
        if (updated != null) {
          if (mounted) {
            setState(() {
            _contacts.clear();
            _contacts.addAll(updated);
          });
          }
          return;
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to remove contact on server')));
          return;
        }
      }
    } catch (_) {
      // fallthrough to local-only removal below
    }

    // If we couldn't find a matching server-side contact, perform local-only removal
    // and advise the user to refresh to sync with server state.
    setState(() => _contacts.removeAt(idx));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed locally. Refresh to sync with server.')));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _importFromDevice() async {
    // Use flutter_contacts to request permission and fetch contacts.
    // Keep a fallback to permission_handler as a safety fallback, but prefer
    // the package's own request so underlying platforms are handled correctly.
    try {
      // Ask the package first (it may show its own dialog on some platforms)
      await FlutterContacts.requestPermission();
    } catch (_) {
      // Fallback to permission_handler if the package call throws
      await Permission.contacts.request();
    }

    // Double-check actual permission state and guide user to settings when needed
    final status = await Permission.contacts.status;
    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        // Inform user and offer to open app settings
        if (!mounted) return;
        final open = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Contacts permission required'),
            content: const Text('Please grant contacts access in app settings to import contacts.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Open Settings')),
            ],
          ),
        );
        if (open == true) await openAppSettings();
        return;
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contacts permission denied')));
      return;
    }

    // Fetch contacts (with phone numbers/properties)
    List<Contact> devContacts;
    try {
      devContacts = await FlutterContacts.getContacts(withProperties: true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to read device contacts')));
      return;
    }

    final phoneContacts = devContacts.where((c) => c.phones.isNotEmpty).toList();
    if (phoneContacts.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No contacts with phone numbers found')));
      return;
    }

    if (!mounted) return;
    // Show a picker bottom sheet
    final Contact? selected = await showModalBottomSheet<Contact>(
      context: context,
      builder: (ctx) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(height: 4, width: 48, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.0),
              child: Text('Select a contact', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: phoneContacts.length,
                itemBuilder: (c, i) {
                  final cont = phoneContacts[i];
                  final display = cont.displayName.isNotEmpty ? cont.displayName : (cont.phones.isNotEmpty ? cont.phones.first.number : '<no name>');
                  final subtitle = cont.phones.isNotEmpty ? cont.phones.first.number : '';
                  return ListTile(
                    title: Text(display),
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

    if (selected == null) return; // user cancelled

    final name = selected.displayName.isNotEmpty ? selected.displayName : (selected.phones.isNotEmpty ? selected.phones.first.number : '');
    final phone = selected.phones.isNotEmpty ? selected.phones.first.number : '';
    if (phone.isEmpty) return;

    final c = ContactModel(name: name, phone: phone);
    // ask for country code if absent
    final ensured = await _ensureCountryCode(c.phone);
    if (ensured == null) return;
    if (_stagedContacts.any((e) => e.phone == ensured)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact already staged')));
      return;
    }
    final staged = ContactModel(name: c.name, phone: ensured);
    if (mounted) setState(() => _stagedContacts.add(staged));
  }

  Future<void> _pickFromPhoneContacts() async {
    // Try to open native contact picker (external). If not available, fall back
    // to in-app picker using getContacts.
    // Capture context to avoid using BuildContext across async gaps.
    final localContext = context;
    try {
      // Ensure we have contacts permission before invoking the external picker.
      try {
        await FlutterContacts.requestPermission();
      } catch (_) {
        await Permission.contacts.request();
      }

      final status = await Permission.contacts.status;
      if (!status.isGranted) {
        if (status.isPermanentlyDenied) {
          final open = await showDialog<bool>(
            context: localContext,
            builder: (ctx) => AlertDialog(
              title: const Text('Contacts permission required'),
              content: const Text('Please grant contacts access in app settings to pick a contact.'),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Open Settings')),
              ],
            ),
          );
          if (open == true) await openAppSettings();
        } else {
          if (mounted) ScaffoldMessenger.of(localContext).showSnackBar(const SnackBar(content: Text('Contacts permission denied')));
        }
        return;
      }

      // At this point permission is granted; proceed to open the picker.

      
      
      Contact? picked;
      try {
        // flutter_contacts provides a platform picker in some versions
        picked = await FlutterContacts.openExternalPick();
      } catch (_) {
        // fallback: show in-app contacts list for selection
        final devContacts = await FlutterContacts.getContacts(withProperties: true);
        final phoneContacts = devContacts.where((c) => c.phones.isNotEmpty).toList();
        if (phoneContacts.isEmpty) {
          if (mounted) ScaffoldMessenger.of(localContext).showSnackBar(const SnackBar(content: Text('No contacts with phone numbers found')));
          return;
        }
        if (!mounted) return;
        picked = await showModalBottomSheet<Contact>(
          context: localContext,
          builder: (ctx) {
            return Column(
              children: [
                const SizedBox(height: 8),
                Container(height: 4, width: 48, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 8),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text('Select a contact', style: TextStyle(fontWeight: FontWeight.w600))),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: phoneContacts.length,
                    itemBuilder: (c, i) {
                      final cont = phoneContacts[i];
                      final display = cont.displayName.isNotEmpty ? cont.displayName : (cont.phones.isNotEmpty ? cont.phones.first.number : '<no name>');
                      final subtitle = cont.phones.isNotEmpty ? cont.phones.first.number : '';
                      return ListTile(
                        title: Text(display),
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
      final phone = picked.phones.isNotEmpty ? picked.phones.first.number : '';
      if (phone.isEmpty) return;
      final c = ContactModel(name: name, phone: phone);
      final ensured = await _ensureCountryCode(c.phone);
      if (ensured == null) return;
      if (_stagedContacts.any((e) => e.phone == ensured)) {
        if (mounted) ScaffoldMessenger.of(localContext).showSnackBar(const SnackBar(content: Text('Contact already staged')));
        return;
      }
      if (mounted) setState(() => _stagedContacts.add(ContactModel(name: c.name, phone: ensured)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(localContext).showSnackBar(const SnackBar(content: Text('Unable to pick contact')));
    }
  }

  Future<void> _submitStaged() async {
    if (_stagedContacts.isEmpty) return;
    setState(() => _submittingStaged = true);
    try {
      final failed = <ContactModel>[];
      for (final c in List<ContactModel>.from(_stagedContacts)) {
        final updated = await _service.addTrustedContact(c);
        if (updated != null) {
          // Server returned updated list: resync local contacts and remove staged items that are now present
          if (mounted) {
            setState(() {
            _contacts.clear();
            _contacts.addAll(updated);
            _stagedContacts.removeWhere((s) => _contacts.any((mc) => mc.phone == s.phone));
          });
          }
        } else {
          failed.add(c);
        }
      }
      if (failed.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contacts added')));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add ${failed.length} contacts')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add contacts: $e')));
    } finally {
      if (mounted) setState(() => _submittingStaged = false);
    }
  }

  String _normalizePhone(String raw) {
    // Keep leading '+' if present, remove all other non-digit characters
    final hasPlus = raw.trim().startsWith('+');
    final digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (hasPlus) return digits;
    // remove any leading zeros (optional) and return digits
    return digits.replaceFirst(RegExp(r'^0+'), '');
  }

  Future<String?> _ensureCountryCode(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('+')) return _normalizePhone(trimmed);

    String selected = _kCommonCountryCodes.first['code']!;
    String manual = '';

    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setStateSB) {
            return AlertDialog(
              title: const Text('Country code required'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selected,
                    items: _kCommonCountryCodes
                        .map((m) => DropdownMenuItem(
                              value: m['code']!,
                              child: Text(m['label']!),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setStateSB(() => selected = v);
                    },
                    decoration: const InputDecoration(labelText: 'Select country code'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: selected,
                    decoration: const InputDecoration(labelText: 'Or enter code (+91)'),
                    onChanged: (v) => setStateSB(() => manual = v),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx2).pop(null), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    final code = manual.trim().isNotEmpty ? manual.trim() : selected;
                    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
                    final composed = '$code$digits';
                    Navigator.of(ctx2).pop(_normalizePhone(composed));
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trusted Contacts')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name'))),
                          const SizedBox(width: 8),
                          Expanded(child: TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone'))),
                          IconButton(icon: const Icon(Icons.add), onPressed: _add),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton.icon(onPressed: _pickFromPhoneContacts, icon: const Icon(Icons.import_contacts), label: const Text('Pick from Phone')),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(onPressed: _importFromDevice, icon: const Icon(Icons.list), label: const Text('In-app list')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_stagedContacts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Wrap(
                        spacing: 8,
                        children: _stagedContacts.map((c) => Chip(
                          label: Text('${c.name} (${c.phone})'),
                          onDeleted: () {
                            setState(() => _stagedContacts.removeWhere((e) => e.phone == c.phone));
                          },
                        )).toList(),
                      ),
                    ),
                  if (_stagedContacts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submittingStaged ? null : _submitStaged,
                          child: _submittingStaged
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Submitting...'),
                                  ],
                                )
                              : const Text('Submit Selected'),
                        ),
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _contacts.length,
                      itemBuilder: (c, i) {
                        final t = _contacts[i];
                        return ListTile(
                          title: Text(t.name),
                          subtitle: Text(t.phone),
                          trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () => _removeAt(i)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// Note: importing from device contacts via a package was removed. If you want
// to restore automatic contact import, add a supported package and implement
// the picker here.

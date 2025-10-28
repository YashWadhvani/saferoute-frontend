// Deprecated: ContactsScreen replaced by TrustedContactsScreen.
// File retained as a placeholder for backward compatibility but should not be used.
import 'package:flutter/material.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts (Deprecated)')),
      body: const Center(
        child: Text('This screen is deprecated. Use Trusted Contacts from the menu.'),
      ),
    );
  }
}

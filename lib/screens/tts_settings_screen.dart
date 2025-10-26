// screens/tts_settings_screen.dart
// Simple UI to change TTS language and speech rate.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/tts_settings.dart';

class TtsSettingsScreen extends StatelessWidget {
  const TtsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<TtsSettings>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('TTS Settings')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            TextFormField(
              initialValue: settings.language,
              decoration: const InputDecoration(labelText: 'Language (e.g. en-US)'),
              onFieldSubmitted: (v) => settings.setLanguage(v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Speech rate'),
                Expanded(
                  child: Slider(
                    value: settings.rate,
                    min: 0.2,
                    max: 1.0,
                    divisions: 8,
                    label: settings.rate.toStringAsFixed(2),
                    onChanged: (v) => settings.setRate(v),
                  ),
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}

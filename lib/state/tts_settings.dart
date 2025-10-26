// state/tts_settings.dart
// ChangeNotifier that holds TTS language and speech rate and persists them.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TtsSettings extends ChangeNotifier {
  String language;
  double rate;

  TtsSettings({this.language = 'en-US', this.rate = 0.45});

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    language = p.getString('tts.language') ?? language;
    rate = p.getDouble('tts.rate') ?? rate;
    notifyListeners();
  }

  Future<void> setLanguage(String lang) async {
    language = lang;
    final p = await SharedPreferences.getInstance();
    await p.setString('tts.language', lang);
    notifyListeners();
  }

  Future<void> setRate(double r) async {
    rate = r;
    final p = await SharedPreferences.getInstance();
    await p.setDouble('tts.rate', r);
    notifyListeners();
  }
}

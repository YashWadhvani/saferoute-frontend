import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/api_client.dart';
import 'contacts_service.dart';


class SosService {
  final Dio _dio = ApiClient.dio;

  SosService();

  /// Send SOS with current location and notify the user's emergency/trusted contacts.
  /// The backend expects POST /api/sos/trigger with body:
  /// {
  ///   "location": { "lat": 0, "lng": 0 },
  ///   "contactsNotified": ["string"]
  /// }
  Future<bool> sendSos({required double lat, required double lng, String? message}) async {
    try {
      // Fetch user's trusted contacts (used as emergency contacts)
      final contactsService = ContactsService();
      final trusted = await contactsService.fetchTrustedContacts();
      final phones = trusted.map((c) => c.phone).where((p) => p.trim().isNotEmpty).toList();

      final body = {
        'location': {'lat': lat, 'lng': lng},
        'contactsNotified': phones,
        if (message != null) 'message': message,
      };

      if (kDebugMode) debugPrint('sendSos: posting to /api/sos/trigger body=$body');
      final r = await _dio.post('/api/sos/trigger', data: body);
      if (kDebugMode) debugPrint('sendSos: status=${r.statusCode} data=${r.data}');
      return r.statusCode != null && r.statusCode! >= 200 && r.statusCode! < 300;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('sendSos failed: $e');
        debugPrint('$st');
      }
      return false;
    }
  }
}

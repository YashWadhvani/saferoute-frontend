import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/api_client.dart';
import '../models/contact.dart';

class ContactsService {
  final Dio _dio = ApiClient.dio;

  ContactsService();

  Future<bool> updateTrustedContacts(List<ContactModel> contacts) async {
    final payloadList = contacts.map((c) => c.toMap()).toList();

    // The backend expects a single contact object like:
    // { "name": "string", "phone": "string" }
    // So send each contact as an individual POST to the endpoint.
    final failures = <dynamic>[];
    for (final item in payloadList) {
      try {
        final resp = await _dio.post('/api/users/me/contacts', data: item);
        if (kDebugMode) debugPrint('updateTrustedContacts: posted contact ${item['phone']} status=${resp.statusCode} data=${resp.data}');
      } catch (e) {
        if (kDebugMode) debugPrint('updateTrustedContacts: failed to post contact ${item['phone']}: $e');
        failures.add({'item': item, 'error': e});
      }
    }

    if (failures.isEmpty) return true;
    if (kDebugMode) debugPrint('updateTrustedContacts: ${failures.length} failures');
    return false;
  }

  /// Add a single trusted contact. Returns true when backend accepts it.
  /// Add a single trusted contact. The server returns the updated contacts
  /// array; parse and return it. Returns null on failure.
  Future<List<ContactModel>?> addTrustedContact(ContactModel contact) async {
    try {
      // Fetch current contacts and avoid posting duplicates by phone.
      try {
        final existing = await fetchTrustedContacts();
        final exists = existing.any((c) => c.phone == contact.phone);
        if (exists) {
          if (kDebugMode) debugPrint('addTrustedContact: contact with phone ${contact.phone} already exists on server; skipping POST');
          return existing;
        }
      } catch (e) {
        // If fetch fails, proceed to post (best-effort).
        if (kDebugMode) debugPrint('addTrustedContact: failed to fetch existing contacts before add: $e');
      }
      final body = contact.toMap();
      final r = await _dio.post('/api/users/me/contacts', data: body);
      if (kDebugMode) debugPrint('addTrustedContact: status=${r.statusCode} data=${r.data}');
      final data = r.data;
      List items = [];
      if (data is List) {
        items = data;
      } else if (data is Map && data['contacts'] is List) {
        items = data['contacts'];
      } else if (data is Map && data['data'] is List) {
        items = data['data'];
      }
      return items.map<ContactModel>((m) => ContactModel.fromMap(Map<String, dynamic>.from(m))).toList();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('addTrustedContact failed: $e');
        debugPrint('$st');
      }
      return null;
    }
  }

  /// Delete a trusted contact by its backend id (subdocument _id).
  /// On success the server returns the updated contacts array; parse and
  /// return it. Returns null on failure.
  Future<List<ContactModel>?> deleteTrustedContact(String contactId) async {
    try {
      final r = await _dio.delete('/api/users/me/contacts/$contactId');
      if (kDebugMode) debugPrint('deleteTrustedContact: status=${r.statusCode} data=${r.data}');
      final data = r.data;
      List items = [];
      if (data is List) {
        items = data;
      } else if (data is Map && data['contacts'] is List) {
        items = data['contacts'];
      } else if (data is Map && data['data'] is List) {
        items = data['data'];
      }
      return items.map<ContactModel>((m) => ContactModel.fromMap(Map<String, dynamic>.from(m))).toList();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('deleteTrustedContact failed: $e');
        debugPrint('$st');
      }
      return null;
    }
  }

  Future<List<ContactModel>> fetchTrustedContacts() async {
    try {
  final r = await _dio.get('/api/users/me/contacts');
      final data = r.data;
      List items = [];
      if (data is List) {
        items = data;
      } else if (data is Map && data['contacts'] is List) {
        items = data['contacts'];
      } else if (data is Map && data['data'] is List) {
        items = data['data'];
      }
      return items.map<ContactModel>((m) => ContactModel.fromMap(Map<String, dynamic>.from(m))).toList();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('fetchTrustedContacts failed: $e');
        debugPrint('$st');
      }
      return [];
    }
  }
}

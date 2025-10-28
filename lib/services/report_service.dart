import 'dart:io';
import 'package:dio/dio.dart';
import '../core/api_client.dart';

class ReportService {
  final Dio _dio = ApiClient.dio;

  ReportService();

  /// Report incident with optional photo files. The payload can contain type, description, location, etc.
  Future<bool> reportIncident(Map<String, dynamic> payload, {List<File>? photos}) async {
    try {
      if (photos == null || photos.isEmpty) {
    await _dio.post('/api/incidents', data: payload);
        return true;
      }
      final form = FormData();
      payload.forEach((k, v) {
        form.fields.add(MapEntry(k, v.toString()));
      });
      for (final f in photos) {
        final name = f.path.split(Platform.pathSeparator).last;
        form.files.add(MapEntry('photos', await MultipartFile.fromFile(f.path, filename: name)));
      }
  await _dio.post('/api/incidents', data: form, options: Options(contentType: 'multipart/form-data'));
      return true;
    } catch (_) {
      return false;
    }
  }
}

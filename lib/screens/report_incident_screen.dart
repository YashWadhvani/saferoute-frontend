import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/report_service.dart';

class ReportIncidentScreen extends StatefulWidget {
  const ReportIncidentScreen({super.key});

  @override
  State<ReportIncidentScreen> createState() => _ReportIncidentScreenState();
}

class _ReportIncidentScreenState extends State<ReportIncidentScreen> {
  final _descCtrl = TextEditingController();
  String _type = 'Other';
  bool _sending = false;
  late final ReportService _service;
  final ImagePicker _picker = ImagePicker();
  final List<File> _photos = [];

  @override
  void initState() {
    super.initState();
    _service = ReportService();
  }

  Future<void> _submit() async {
    if (_descCtrl.text.trim().isEmpty) return;
    setState(() => _sending = true);
    final ok = await _service.reportIncident({'type': _type, 'description': _descCtrl.text.trim()}, photos: _photos);
    setState(() => _sending = false);
    if (ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reported')));
        Navigator.of(context).pop();
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final result = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (result != null) {
        setState(() => _photos.add(File(result.path)));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report Incident')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              items: const [
                DropdownMenuItem(value: 'Accident', child: Text('Accident')),
                DropdownMenuItem(value: 'Hazard', child: Text('Hazard')),
                DropdownMenuItem(value: 'Crime', child: Text('Crime')),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'Other'),
              decoration: const InputDecoration(labelText: 'Type'),
            ),
            const SizedBox(height: 12),
            TextField(controller: _descCtrl, maxLines: 6, decoration: const InputDecoration(labelText: 'Description')),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(onPressed: _pickPhoto, icon: const Icon(Icons.camera_alt), label: const Text('Take Photo')),
                for (final p in _photos) SizedBox(width: 72, height: 72, child: Image.file(p, fit: BoxFit.cover)),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _sending ? null : _submit, child: _sending ? const CircularProgressIndicator() : const Text('Submit'))
          ],
        ),
      ),
    );
  }
}

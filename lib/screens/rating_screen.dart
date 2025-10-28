import 'package:flutter/material.dart';
import '../services/rating_service.dart';

class RatingScreen extends StatefulWidget {
  final String routeId;
  const RatingScreen({super.key, required this.routeId});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  final Map<String, int> _scores = {
    'safety': 3,
    'lighting': 3,
    'traffic': 3,
    'sidewalks': 3,
    'signage': 3,
  };
  final _comments = TextEditingController();
  bool _sending = false;
  late final RatingService _service;

  @override
  void initState() {
    super.initState();
    _service = RatingService();
  }

  Future<void> _submit() async {
    setState(() => _sending = true);
    final ok = await _service.submitRouteFeedback({
      'routeId': widget.routeId,
      'ratings': _scores,
      'comments': _comments.text.trim(),
    });
    setState(() => _sending = false);
    if (ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks for your feedback')));
        Navigator.of(context).pop();
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
    }
  }

  Widget _row(String label) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Row(children: List.generate(5, (i) {
          final v = i + 1;
          return IconButton(
            icon: Icon(v <= _scores[label.toLowerCase()]! ? Icons.star : Icons.star_border, color: Colors.amber),
            onPressed: () => setState(() => _scores[label.toLowerCase()] = v),
          );
        })),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rate this route')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            _row('Safety'),
            _row('Lighting'),
            _row('Traffic'),
            _row('Sidewalks'),
            _row('Signage'),
            TextField(controller: _comments, decoration: const InputDecoration(labelText: 'Comments (optional)')),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _sending ? null : _submit, child: _sending ? const CircularProgressIndicator() : const Text('Submit'))
          ],
        ),
      ),
    );
  }
}

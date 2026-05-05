import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:client_app/widgets/section_card.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final TextEditingController _locationController =
      TextEditingController(text: 'Quezon City (GPS placeholder)');
  final TextEditingController _descriptionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  String _wasteType = 'Mixed';
  String? _pickedLabel;

  @override
  void dispose() {
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (!mounted) return;
    setState(() {
      _pickedLabel = image?.name;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 6, 4, 12),
            child: Text(
              'Report Dumpsite',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          SectionCard(
            title: 'Photo Evidence',
            subtitle: 'UI ready. Upload logic follows on Day 2.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('Pick Photo'),
                ),
                const SizedBox(height: 8),
                Text(
                  _pickedLabel == null ? 'No photo selected' : 'Selected: $_pickedLabel',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Location',
            subtitle: 'Static placeholder for Day 1 shell',
            child: TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Auto-detected location',
              ),
            ),
          ),
          SectionCard(
            title: 'Waste Type',
            child: DropdownButtonFormField<String>(
              initialValue: _wasteType,
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'Biodegradable', child: Text('Biodegradable')),
                DropdownMenuItem<String>(value: 'Recyclable', child: Text('Recyclable')),
                DropdownMenuItem<String>(value: 'Special/Hazardous', child: Text('Special/Hazardous')),
                DropdownMenuItem<String>(value: 'Mixed', child: Text('Mixed')),
                DropdownMenuItem<String>(value: 'Unknown', child: Text('Unknown')),
              ],
              onChanged: (String? value) {
                if (value == null) return;
                setState(() {
                  _wasteType = value;
                });
              },
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          SectionCard(
            title: 'Description (Optional)',
            child: TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Add street details, nearest landmark, or urgency notes',
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Day 1 shell only: submit wiring starts on Day 2.'),
                  ),
                );
              },
              icon: const Icon(Icons.send),
              label: const Text('Submit Report (Static)'),
            ),
          ),
        ],
      ),
    );
  }
}

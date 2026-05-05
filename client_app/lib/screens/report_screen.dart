import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:client_app/widgets/section_card.dart';
import 'package:client_app/services/supabase_service.dart';
import 'package:latlong2/latlong.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({
    super.key,
    this.selectedPoint,
    this.onRequestPinTab,
  });

  final LatLng? selectedPoint;
  final VoidCallback? onRequestPinTab;

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
  bool _isSubmitting = false;

  String _normalizedWasteType() {
    switch (_wasteType) {
      case 'Biodegradable':
        return 'biodegradable';
      case 'Recyclable':
        return 'recyclable';
      case 'Special/Hazardous':
        return 'special_hazardous';
      case 'Mixed':
        return 'mixed';
      case 'Unknown':
      default:
        return 'unknown';
    }
  }

  Future<void> _submitReport() async {
    final LatLng? point = widget.selectedPoint;
    if (point == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No map pin yet. Set pin in Map tab first.')),
      );
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add short description before submit.')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final String? reporterId = SupabaseService.client.auth.currentUser?.id;
      await SupabaseService.client.from('reports').insert(<String, dynamic>{
        'reporter_id': reporterId,
        'lat': point.latitude,
        'lng': point.longitude,
        'report_type': 'dumpsite',
        'waste_type': _normalizedWasteType(),
        'description': _descriptionController.text.trim(),
      });

      if (!mounted) return;
      _descriptionController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report submitted. LGU feed will update in realtime phase.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submit failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

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
    final LatLng? selectedPoint = widget.selectedPoint;
    _locationController.text = selectedPoint == null
        ? 'No map pin selected yet'
        : '${selectedPoint.latitude.toStringAsFixed(6)}, ${selectedPoint.longitude.toStringAsFixed(6)}';

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
            subtitle: 'Photo picker ready. Upload storage next phase.',
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
            subtitle: 'Pin from Map tab used as report coordinates',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: _locationController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Tap map to set coordinates',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: widget.onRequestPinTab,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Go to Map tab to drop pin'),
                ),
              ],
            ),
          ),
          if (selectedPoint != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 10),
              child: Text(
                'Pin ready: ${selectedPoint.latitude.toStringAsFixed(6)}, ${selectedPoint.longitude.toStringAsFixed(6)}',
                style: const TextStyle(
                  color: Color(0xFF166534),
                  fontWeight: FontWeight.w600,
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
              onPressed: _isSubmitting ? null : _submitReport,
              icon: const Icon(Icons.send),
              label: Text(_isSubmitting ? 'Submitting...' : 'Submit Report'),
            ),
          ),
        ],
      ),
    );
  }
}

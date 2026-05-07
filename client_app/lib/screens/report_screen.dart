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
      TextEditingController(text: 'No map pin selected yet');
  final TextEditingController _descriptionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  String _wasteType = 'Mixed';
  String? _pickedLabel;
  bool _isSubmitting = false;

  String _normalizedWasteType() {
    switch (_wasteType) {
      case 'Biodegradable': return 'biodegradable';
      case 'Recyclable': return 'recyclable';
      case 'Special/Hazardous': return 'special_hazardous';
      case 'Mixed': return 'mixed';
      default: return 'unknown';
    }
  }

  Future<void> _submitReport() async {
    final LatLng? point = widget.selectedPoint;
    if (point == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a location on the map first')),
      );
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a short description')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

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
        const SnackBar(content: Text('Report successfully submitted')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submission error: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (!mounted) return;
    setState(() => _pickedLabel = image?.name);
  }

  @override
  Widget build(BuildContext context) {
    final LatLng? selectedPoint = widget.selectedPoint;
    _locationController.text = selectedPoint == null
        ? 'No map pin selected yet'
        : '${selectedPoint.latitude.toStringAsFixed(6)}, ${selectedPoint.longitude.toStringAsFixed(6)}';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 100, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionCard(
            title: 'Location Point',
            subtitle: 'Pick coordinates from the map',
            icon: Icons.location_searching_rounded,
            child: Column(
              children: [
                TextField(
                  controller: _locationController,
                  readOnly: true,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1B4332)),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.gps_fixed_rounded, size: 20, color: Color(0xFF40916C)),
                    fillColor: const Color(0xFFF1F5F9).withOpacity(0.5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onRequestPinTab,
                    icon: const Icon(Icons.map_rounded, size: 18),
                    label: const Text('OPEN MAP TO PICK'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          SectionCard(
            title: 'Waste Type',
            subtitle: 'Select category of waste',
            icon: Icons.auto_awesome_motion_rounded,
            child: DropdownButtonFormField<String>(
              value: _wasteType,
              items: const <String>['Biodegradable', 'Recyclable', 'Special/Hazardous', 'Mixed'].map((String val) {
                return DropdownMenuItem<String>(
                  value: val,
                  child: Text(val, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                );
              }).toList(),
              onChanged: (String? value) => value != null ? setState(() => _wasteType = value) : null,
              decoration: InputDecoration(
                fillColor: const Color(0xFFF1F5F9).withOpacity(0.5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),

          SectionCard(
            title: 'Visual Proof',
            subtitle: 'Upload area photo',
            icon: Icons.camera_rounded,
            child: GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9).withOpacity(0.4),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5, style: BorderStyle.solid),
                ),
                child: Column(
                  children: [
                    Icon(
                      _pickedLabel == null ? Icons.add_photo_alternate_outlined : Icons.check_circle_rounded,
                      size: 44,
                      color: _pickedLabel == null ? const Color(0xFF94A3B8) : const Color(0xFF40916C),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _pickedLabel ?? 'TAP TO ATTACH PHOTO',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _pickedLabel == null ? const Color(0xFF64748B) : const Color(0xFF1B4332),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          SectionCard(
            title: 'Notes',
            subtitle: 'Additional landmarks',
            icon: Icons.edit_note_rounded,
            child: TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Street name, gate color, etc...',
                fillColor: const Color(0xFFF1F5F9).withOpacity(0.5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),

          const SizedBox(height: 20),
          
          Container(
            width: double.infinity,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: const LinearGradient(colors: [Color(0xFF1B4332), Color(0xFF40916C)]),
              boxShadow: [
                BoxShadow(color: const Color(0xFF1B4332).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10)),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitReport,
              icon: _isSubmitting 
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.send_rounded, color: Colors.white),
              label: Text(
                _isSubmitting ? 'SUBMITTING...' : 'SUBMIT REPORT',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

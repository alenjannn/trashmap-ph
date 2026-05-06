import 'dart:typed_data';

import 'package:client_app/services/supabase_service.dart';
import 'package:client_app/widgets/section_card.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _notesController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  String? _error;
  int _myPoints = 0;
  String _myBarangay = 'Unassigned';
  List<LeaderboardItem> _leaderboard = <LeaderboardItem>[];
  List<ReportOption> _recentReports = <ReportOption>[];

  String? _selectedReportId;
  XFile? _beforeImage;
  XFile? _afterImage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final String? userId = SupabaseService.client.auth.currentUser?.id;
      final dynamic pointsResponse = await SupabaseService.client
          .from('gamification_points')
          .select('points, barangay')
          .eq('user_id', userId ?? '')
          .maybeSingle();
      final int myPoints = (pointsResponse?['points'] as num?)?.toInt() ?? 0;
      final String myBarangay = (pointsResponse?['barangay'] as String?) ?? 'Unassigned';

      final dynamic leaderboardResponse = await SupabaseService.client
          .from('gamification_points')
          .select('user_id, points, barangay')
          .order('points', ascending: false)
          .limit(50);
      final List<dynamic> leaderboardRows = leaderboardResponse as List<dynamic>;
      final Map<String, int> pointsByBarangay = <String, int>{};
      for (final dynamic row in leaderboardRows) {
        final String barangay = (row['barangay'] as String?)?.trim().isNotEmpty == true
            ? (row['barangay'] as String)
            : 'Unassigned';
        final int points = (row['points'] as num?)?.toInt() ?? 0;
        pointsByBarangay[barangay] = (pointsByBarangay[barangay] ?? 0) + points;
      }
      final List<LeaderboardItem> leaderboard = pointsByBarangay.entries
          .map((MapEntry<String, int> entry) => LeaderboardItem(barangay: entry.key, points: entry.value))
          .toList()
        ..sort((LeaderboardItem a, LeaderboardItem b) => b.points.compareTo(a.points));

      final dynamic reportResponse = await SupabaseService.client
          .from('reports')
          .select('id, description, created_at')
          .order('created_at', ascending: false)
          .limit(30);
      final List<dynamic> reportRows = reportResponse as List<dynamic>;
      final List<ReportOption> reportOptions = reportRows.map((dynamic row) {
        final String id = row['id'] as String;
        final String desc = ((row['description'] as String?) ?? 'Citizen report').trim();
        final String created = (row['created_at'] as String?) ?? '';
        return ReportOption(id: id, label: '$desc • ${created.replaceFirst('T', ' ').split('.').first}');
      }).toList();

      if (!mounted) return;
      setState(() {
        _myPoints = myPoints;
        _myBarangay = myBarangay;
        _leaderboard = leaderboard.take(10).toList();
        _recentReports = reportOptions;
        _selectedReportId = reportOptions.isEmpty ? null : reportOptions.first.id;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load rewards data: $error';
        _loading = false;
      });
    }
  }

  Future<void> _pickBeforeImage() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (!mounted) return;
    setState(() {
      _beforeImage = file;
    });
  }

  Future<void> _pickAfterImage() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (!mounted) return;
    setState(() {
      _afterImage = file;
    });
  }

  Future<String> _uploadVerificationImage({
    required String reportId,
    required XFile file,
    required String tag,
  }) async {
    final Uint8List bytes = await file.readAsBytes();
    final String filename = '${DateTime.now().millisecondsSinceEpoch}-$tag.jpg';
    final String path = 'verifications/$reportId/$filename';
    await SupabaseService.client.storage.from('report-photos').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: 'image/jpeg', upsert: true),
    );
    return SupabaseService.client.storage.from('report-photos').getPublicUrl(path);
  }

  Future<void> _submitVerification() async {
    if (_selectedReportId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select report first.')));
      return;
    }
    if (_beforeImage == null || _afterImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick both before and after images.')));
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final String beforeUrl = await _uploadVerificationImage(
        reportId: _selectedReportId!,
        file: _beforeImage!,
        tag: 'before',
      );
      final String afterUrl = await _uploadVerificationImage(
        reportId: _selectedReportId!,
        file: _afterImage!,
        tag: 'after',
      );
      await SupabaseService.client.from('report_verifications').insert(<String, dynamic>{
        'report_id': _selectedReportId,
        'before_photo_url': beforeUrl,
        'after_photo_url': afterUrl,
        'verified_by': SupabaseService.client.auth.currentUser?.id,
        'notes': _notesController.text.trim(),
      });

      if (!mounted) return;
      setState(() {
        _beforeImage = null;
        _afterImage = null;
        _notesController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Before/After verification submitted. Points will update shortly.')),
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Verification submit failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 6, 4, 12),
          child: Text(
            'Rewards & Verification',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        SectionCard(
          title: 'My Points',
          subtitle: 'Barangay: $_myBarangay',
          child: Text(
            '$_myPoints points',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF166534)),
          ),
        ),
        SectionCard(
          title: 'Barangay Leaderboard',
          subtitle: 'Top 10 by total points',
          child: _leaderboard.isEmpty
              ? const Text('No leaderboard data yet.')
              : Column(
                  children: _leaderboard.asMap().entries.map((MapEntry<int, LeaderboardItem> entry) {
                    final int rank = entry.key + 1;
                    final LeaderboardItem item = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: <Widget>[
                          Text('#$rank', style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(item.barangay)),
                          Text('${item.points} pts', style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        SectionCard(
          title: 'Before/After Verification',
          subtitle: 'Submit visual proof for cleanup',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DropdownButtonFormField<String>(
                initialValue: _selectedReportId,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Select report',
                ),
                items: _recentReports
                    .map((ReportOption item) => DropdownMenuItem<String>(value: item.id, child: Text(item.label)))
                    .toList(),
                onChanged: (String? value) {
                  setState(() {
                    _selectedReportId = value;
                  });
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickBeforeImage,
                      icon: const Icon(Icons.photo_camera_back_outlined),
                      label: Text(_beforeImage == null ? 'Pick Before' : 'Before picked'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickAfterImage,
                      icon: const Icon(Icons.photo_camera_front_outlined),
                      label: Text(_afterImage == null ? 'Pick After' : 'After picked'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Notes (optional)',
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submitVerification,
                  icon: const Icon(Icons.verified),
                  label: Text(_submitting ? 'Submitting...' : 'Submit Verification'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class LeaderboardItem {
  LeaderboardItem({required this.barangay, required this.points});

  final String barangay;
  final int points;
}

class ReportOption {
  ReportOption({required this.id, required this.label});

  final String id;
  final String label;
}

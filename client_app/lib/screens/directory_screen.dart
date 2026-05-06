import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:client_app/services/supabase_service.dart';
import 'package:client_app/widgets/section_card.dart';

class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  bool _loading = true;
  String? _error;
  int _selectedTab = 0;
  List<RecyclerItem> _recyclers = <RecyclerItem>[];
  RealtimeChannel? _recyclerChannel;

  @override
  void initState() {
    super.initState();
    _loadRecyclers();
    _recyclerChannel = SupabaseService.client
        .channel('mobile-directory-recyclers-live-v1')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'recyclers',
          callback: (_) => _loadRecyclers(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    final RealtimeChannel? channel = _recyclerChannel;
    if (channel != null) {
      SupabaseService.client.removeChannel(channel);
    }
    super.dispose();
  }

  Future<void> _loadRecyclers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dynamic response = await SupabaseService.client
          .from('recyclers')
          .select(
            'id, name, lat, lng, address, contact_number, accepted_materials, operating_hours, approval_status',
          )
          .eq('approval_status', 'approved')
          .order('created_at', ascending: false)
          .limit(200);
      final List<dynamic> rows = response as List<dynamic>;
      final List<RecyclerItem> items = rows.map((dynamic row) {
        final List<String> materials = List<String>.from((row['accepted_materials'] as List<dynamic>? ?? <dynamic>[]));
        return RecyclerItem(
          id: row['id'] as String,
          name: (row['name'] as String?) ?? 'Recycler',
          lat: (row['lat'] as num?)?.toDouble() ?? 0,
          lng: (row['lng'] as num?)?.toDouble() ?? 0,
          address: (row['address'] as String?) ?? 'No address provided',
          contactNumber: (row['contact_number'] as String?) ?? 'No contact number',
          operatingHours: (row['operating_hours'] as String?) ?? 'No operating hours',
          acceptedMaterials: materials,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _recyclers = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load recycler directory: $error';
        _loading = false;
      });
    }
  }

  void _showRecyclerDetails(RecyclerItem item) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(item.address),
                const SizedBox(height: 8),
                Text('Accepted: ${item.acceptedMaterials.isEmpty ? 'Not listed' : item.acceptedMaterials.join(', ')}'),
                const SizedBox(height: 6),
                Text('Hours: ${item.operatingHours}'),
                const SizedBox(height: 6),
                Text('Contact: ${item.contactNumber}'),
                const SizedBox(height: 6),
                Text('Location: ${item.lat.toStringAsFixed(6)}, ${item.lng.toStringAsFixed(6)}'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildListView() {
    if (_recyclers.isEmpty) {
      return const SectionCard(
        title: 'No recyclers available',
        child: Text('LGU has not published approved recyclers yet.'),
      );
    }

    return Column(
      children: _recyclers.map((RecyclerItem item) {
        return SectionCard(
          title: item.name,
          subtitle: item.address,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Accepted: ${item.acceptedMaterials.isEmpty ? 'Not listed' : item.acceptedMaterials.join(', ')}'),
              const SizedBox(height: 6),
              Text('Hours: ${item.operatingHours}'),
              const SizedBox(height: 6),
              Text('Contact: ${item.contactNumber}'),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => _showRecyclerDetails(item),
                  child: const Text('View details'),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMapView() {
    const LatLng fallbackCenter = LatLng(14.6887, 121.1069);
    final LatLng center = _recyclers.isEmpty ? fallbackCenter : LatLng(_recyclers.first.lat, _recyclers.first.lng);

    return SizedBox(
      height: 460,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: 14,
          ),
          children: <Widget>[
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.trashmapph.client_app',
            ),
            MarkerLayer(
              markers: _recyclers
                  .map(
                    (RecyclerItem item) => Marker(
                      point: LatLng(item.lat, item.lng),
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: () => _showRecyclerDetails(item),
                        child: const Icon(Icons.storefront, color: Color(0xFF0F766E), size: 30),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
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
            'Recycler & Junk Shop Directory',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        if (_error != null)
          SectionCard(
            title: 'Directory load error',
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFB91C1C)),
            ),
          ),
        if (_error != null) const SizedBox(height: 10),
        SegmentedButton<int>(
          segments: const <ButtonSegment<int>>[
            ButtonSegment<int>(value: 0, label: Text('List'), icon: Icon(Icons.list)),
            ButtonSegment<int>(value: 1, label: Text('Map'), icon: Icon(Icons.map)),
          ],
          selected: <int>{_selectedTab},
          onSelectionChanged: (Set<int> value) {
            setState(() {
              _selectedTab = value.first;
            });
          },
        ),
        const SizedBox(height: 12),
        if (_selectedTab == 0) _buildListView() else _buildMapView(),
      ],
    );
  }
}

class RecyclerItem {
  RecyclerItem({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.address,
    required this.contactNumber,
    required this.operatingHours,
    required this.acceptedMaterials,
  });

  final String id;
  final String name;
  final double lat;
  final double lng;
  final String address;
  final String contactNumber;
  final String operatingHours;
  final List<String> acceptedMaterials;
}

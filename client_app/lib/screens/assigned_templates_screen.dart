import 'package:client_app/models/assigned_template.dart';
import 'package:client_app/screens/template_preview_screen.dart';
import 'package:client_app/services/api_client.dart';
import 'package:client_app/utils/route_gate.dart';
import 'package:flutter/material.dart';

class AssignedTemplatesScreen extends StatefulWidget {
  const AssignedTemplatesScreen({super.key, required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  State<AssignedTemplatesScreen> createState() => _AssignedTemplatesScreenState();
}

class _AssignedTemplatesScreenState extends State<AssignedTemplatesScreen> {
  final ApiClient _api = ApiClient();
  List<AssignedTemplate> _templates = <AssignedTemplate>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<AssignedTemplate> rows = await _api.getMyAssignedTemplates();
      if (!mounted) return;
      setState(() {
        _templates = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _dayShort(String recurrenceDay) {
    return recurrenceDay.isEmpty ? '?' : recurrenceDay[0].toUpperCase() + recurrenceDay.substring(1);
  }

  String _windowLabel(AssignedTemplate t) {
    final String a = t.startHour.toString().padLeft(2, '0');
    final String b = t.endHour.toString().padLeft(2, '0');
    return '${_dayShort(t.recurrenceDay)} $a:00–$b:00';
  }

  Widget _gateBadge(RouteGate gate) {
    final Color bg;
    final Color fg;
    final String label;
    switch (gate) {
      case RouteGate.onTime:
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF166534);
        label = 'On time';
        break;
      case RouteGate.early:
        bg = const Color(0xFFFEF9C3);
        fg = const Color(0xFF854D0E);
        label = 'Early';
        break;
      case RouteGate.late:
        bg = const Color(0xFFFFEDD5);
        fg = const Color(0xFFC2410C);
        label = 'Late';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My weekly routes'),
        actions: <Widget>[
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, style: const TextStyle(color: Colors.red)),
                        ),
                      ],
                    )
                  : _templates.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const <Widget>[
                            SizedBox(height: 120),
                            Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'No weekly routes assigned yet.\nAsk your admin to assign you in the dashboard.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _templates.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (BuildContext context, int index) {
                            final AssignedTemplate t = _templates[index];
                            final RouteGate gate = computeRouteGate(
                              recurrenceDay: t.recurrenceDay,
                              startHour: t.startHour,
                              endHour: t.endHour,
                            );
                            return Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              elevation: 1,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (BuildContext ctx) => TemplatePreviewScreen(
                                        api: _api,
                                        template: t,
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              t.name,
                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _windowLabel(t),
                                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                                            ),
                                          ],
                                        ),
                                      ),
                                      _gateBadge(gate),
                                      const Icon(Icons.chevron_right, color: Colors.black38),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
    );
  }
}

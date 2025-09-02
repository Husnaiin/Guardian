import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/socket_service.dart';

class AdminPushSettingsCard extends StatefulWidget {
  final SocketService socketService;
  const AdminPushSettingsCard({super.key, required this.socketService});

  @override
  State<AdminPushSettingsCard> createState() => _AdminPushSettingsCardState();
}

class _AdminPushSettingsCardState extends State<AdminPushSettingsCard> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _clientIdController = TextEditingController();
  bool _isSaving = false;
  Map<String, dynamic>? _lastPushed;

  @override
  void dispose() {
    _clientIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.cloud_upload, color: Colors.indigo[700]),
                  const SizedBox(width: 8),
                  Text('Push Settings to Client', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Enter client email. These settings will be saved for the client: Raspberry Pi IP/Port and map info. You can push partial updates.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _clientIdController,
                decoration: const InputDecoration(
                  labelText: 'Client Email',
                  prefixIcon: Icon(Icons.email),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter client email';
                  final email = v.trim().toLowerCase();
                  final emailOk = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
                  if (!emailOk) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _handlePushFlow,
                  icon: _isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Saving...' : 'Save to Client'),
                ),
              ),
              if (_lastPushed != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green[700]),
                          const SizedBox(width: 8),
                          Text('Last push summary', style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(_summaryText(_lastPushed!)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _summaryText(Map<String, dynamic> data) {
    final email = data['clientEmail'] ?? '';
    final name = data['clientName'] ?? '-';
    final ip = data['piIp']?.toString() ?? '-';
    final port = data['port']?.toString() ?? '-';
    final mapId = data['mapId']?.toString() ?? '-';
    return 'Client: $name ($email)\nPi IP: $ip\nPort: $port\nMap ID: $mapId';
  }

  Future<void> _handlePushFlow() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final email = _clientIdController.text.trim().toLowerCase();

    try {
      // Soft validation: try Firestore users/{email}. If missing, allow override on confirm.
      String clientName = '';
      bool profileExists = false;
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(email).get();
        if (userDoc.exists) {
          profileExists = true;
          clientName = (userDoc.data() ?? const {})['name'] ?? '';
        }
      } catch (_) {}

      // Build settings to push
      final payload = <String, dynamic>{
        'clientEmail': email,
        'clientName': clientName,
        'piIp': widget.socketService.piHost,
        'port': widget.socketService.piPort,
        'mapId': 'default',
        'mapMeta': <String, dynamic>{},
      };

      // Confirm with a dialog showing summary
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Push'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(profileExists
                  ? 'You are about to save the following settings:'
                  : 'Client profile not found. You can still push settings. The client must later log in with this email to pull them.'),
              const SizedBox(height: 8),
              _summaryList(payload),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirm')),
          ],
        ),
      );
      if (confirmed != true) return;

      await FirebaseFirestore.instance.collection('clients').doc(email).set({
        'piIp': payload['piIp'],
        'port': payload['port'],
        'mapId': payload['mapId'],
        'mapMeta': payload['mapMeta'],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() => _lastPushed = payload);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved to client'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save settings: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _summaryList(Map<String, dynamic> data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv('Client', '${data['clientName'] ?? '-'} (${data['clientEmail'] ?? '-'})'),
        _kv('Pi IP', data['piIp']?.toString() ?? '-'),
        _kv('Port', data['port']?.toString() ?? '-'),
        _kv('Map ID', data['mapId']?.toString() ?? '-'),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text('$k:', style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}

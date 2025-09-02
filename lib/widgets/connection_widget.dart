import 'package:flutter/material.dart';
import '../services/socket_service.dart';

class ConnectionWidget extends StatefulWidget {
  final SocketService socketService;

  const ConnectionWidget({
    super.key,
    required this.socketService,
  });

  @override
  State<ConnectionWidget> createState() => _ConnectionWidgetState();
}

class _ConnectionWidgetState extends State<ConnectionWidget> {
  final _hostController = TextEditingController();
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _hostController.text = widget.socketService.piHost;
  }

  @override
  void dispose() {
    _hostController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  widget.socketService.isConnected ? Icons.wifi : Icons.wifi_off,
                  color: widget.socketService.isConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  'Raspberry Pi Connection',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.socketService.isConnected ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.socketService.connectionStatus,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _hostController,
                    decoration: const InputDecoration(
                      labelText: 'Raspberry Pi IP Address',
                      hintText: '192.168.0.103',
                      prefixIcon: Icon(Icons.computer),
                      isDense: true,
                    ),
                    enabled: !widget.socketService.isConnected,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: ElevatedButton(
                    onPressed: _isConnecting 
                        ? null 
                        : widget.socketService.isConnected
                            ? _disconnect
                            : _connect,
                    child: _isConnecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.socketService.isConnected ? 'Disconnect' : 'Connect'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _connect() async {
    final host = _hostController.text.trim();
    
    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter Raspberry Pi IP address'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    // Use hardcoded port 8765
    widget.socketService.updateConnectionDetails(host, 8765);
    final success = await widget.socketService.connect();

    setState(() {
      _isConnecting = false;
    });

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connected to Raspberry Pi'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to connect to Raspberry Pi'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _disconnect() {
    widget.socketService.disconnect();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disconnected from Raspberry Pi'),
          backgroundColor: Colors.grey,
        ),
      );
    }
  }
} 
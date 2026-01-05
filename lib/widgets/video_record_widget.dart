import 'package:flutter/material.dart';
import '../services/socket_service.dart';
import '../models/command.dart';

class VideoRecordWidget extends StatefulWidget {
  final SocketService socketService;
  const VideoRecordWidget({super.key, required this.socketService});

  @override
  State<VideoRecordWidget> createState() => _VideoRecordWidgetState();
}

class _VideoRecordWidgetState extends State<VideoRecordWidget> {
  bool _recording = false;
  bool _busy = false;

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
                Icon(Icons.videocam, color: Colors.deepPurple[700]),
                const SizedBox(width: 8),
                Text(
                  'Video Recorder',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                _statusPill(),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(48),
                onTap: _busy ? null : _toggleRecord,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _recording ? Colors.red[600] : Colors.grey[300],
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                          )
                        : Icon(
                            _recording ? Icons.stop : Icons.videocam,
                            color: _recording ? Colors.white : Colors.black54,
                            size: 28,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill() {
    final color = _recording ? Colors.red[600]! : Colors.grey[600]!;
    final text = _recording ? 'RECORDING' : 'IDLE';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }

  Future<void> _toggleRecord() async {
    setState(() => _busy = true);
    try {
      final ok = await widget.socketService.sendCommand(_recording ? Command.stopRecord() : Command.startRecord());
      if (ok && mounted) {
        setState(() => _recording = !_recording);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_recording ? 'Recording started' : 'Recording stopped'),
          backgroundColor: _recording ? Colors.red : Colors.grey,
        ));
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Failed to send record command'),
            backgroundColor: Colors.red,
          ));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error sending record command'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}



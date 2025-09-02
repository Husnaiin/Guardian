import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/command.dart';

class SocketService extends ChangeNotifier {
  Socket? _socket;
  bool _isConnected = false;
  String _connectionStatus = 'Disconnected';
  final List<String> _logs = [];
  
  // Default Pi connection details
  String _piHost = '192.168.0.103';
  int _piPort = 8765;

  // Getters
  bool get isConnected => _isConnected;
  String get connectionStatus => _connectionStatus;
  List<String> get logs => List.unmodifiable(_logs);
  String get piHost => _piHost;
  int get piPort => _piPort;

  
  // Stream controller for receiving messages
  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  void updateConnectionDetails(String host, int port) {
    _piHost = host;
    _piPort = port;
    notifyListeners();
  }

  Future<bool> connect() async {
    if (_isConnected) {
      return true;
    }

    try {
      _updateConnectionStatus('Connecting...');
      _addLog('Attempting to connect to $_piHost:$_piPort');
      
      _socket = await Socket.connect(_piHost, _piPort, timeout: const Duration(seconds: 10));
      
      _isConnected = true;
      _updateConnectionStatus('Connected');
      _addLog('Connected to Raspberry Pi');
      
      // Listen for incoming messages
      _socket!.listen(
        _onDataReceived,
        onError: _onError,
        onDone: _onConnectionClosed,
      );
      
      return true;
    } catch (e) {
      _isConnected = false;
      _updateConnectionStatus('Connection Failed');
      _addLog('Connection failed: $e');
      return false;
    }
  }

  void _onDataReceived(List<int> data) {
    try {
      final message = utf8.decode(data);
      _addLog('Received: $message');
      
      final jsonData = jsonDecode(message) as Map<String, dynamic>;
      _messageController.add(jsonData);
    } catch (e) {
      _addLog('Error parsing received data: $e');
    }
  }

  void _onError(dynamic error) {
    _addLog('Socket error: $error');
    _isConnected = false;
    _updateConnectionStatus('Error');
    disconnect();
  }

  void _onConnectionClosed() {
    _addLog('Connection closed by server');
    _isConnected = false;
    _updateConnectionStatus('Disconnected');
    notifyListeners();
  }

  Future<bool> sendCommand(Command command) async {
    if (!_isConnected || _socket == null) {
      _addLog('Cannot send command: Not connected');
      return false;
    }

    try {
      final jsonString = jsonEncode(command.toJson());
      _socket!.write(jsonString);
      await _socket!.flush();
      
      _addLog('Sent command: ${command.command}');
      return true;
    } catch (e) {
      _addLog('Error sending command: $e');
      return false;
    }
  }

  void disconnect() {
    if (_socket != null) {
      _socket!.close();
      _socket = null;
    }
    _isConnected = false;
    _updateConnectionStatus('Disconnected');
    _addLog('Disconnected from Raspberry Pi');
  }

  void _updateConnectionStatus(String status) {
    _connectionStatus = status;
    notifyListeners();
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    _logs.add('[$timestamp] $message');
    
    // Keep only last 100 log entries
    if (_logs.length > 100) {
      _logs.removeAt(0);
    }
    
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _messageController.close();
    super.dispose();
  }
} 
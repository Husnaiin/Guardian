import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/socket_service.dart';
import 'services/drone_service.dart';
import 'services/notification_service.dart';
import 'services/sensor_map_service.dart';
import 'foreground_service.dart';
import 'screens/login_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  await NotificationService().initialize();
  await startForegroundService();

  // Start socket in background as regular client before UI
  final socketService = SocketService();
  await socketService.connect();

  runApp(GuardianApp(socketService: socketService));
}

class GuardianApp extends StatelessWidget {
  final SocketService socketService;
  const GuardianApp({super.key, required this.socketService});

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<SocketService>.value(value: socketService),
          ChangeNotifierProvider<SensorMapService>(create: (_) => SensorMapService()),
          ChangeNotifierProxyProvider<SocketService, DroneService>(
            create: (_) => DroneService(),
            update: (_, socket, drone) {
              final d = drone ?? DroneService();
              d.initialize(socket);
              return d;
            },
          ),
        ],
        child: MaterialApp(
          title: 'Guardian Drone Controller',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.red,
            primaryColor: Colors.red[700],
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.red[700],
              foregroundColor: Colors.white,
              elevation: 2,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.red[700]!),
              ),
            ),
          ),
          home: const LoginScreen(),
        ),
      ),
    );
  }
}
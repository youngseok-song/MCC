// main.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/location_data.dart';
import 'screens/map_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive 초기화
  await Hive.initFlutter();

  // LocationData 타입 어댑터 등록 (build_runner 실행 후 생성된 어댑터)
  Hive.registerAdapter(LocationDataAdapter());

  // locationBox 오픈 (타입 명시: LocationData)
  await Hive.openBox<LocationData>('locationBox');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Real-time GPS on OSM',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const MapScreen(), // 개선된 MapScreen
    );
  }
}

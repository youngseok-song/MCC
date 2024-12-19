// screens/map_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:hive/hive.dart';

// 모델 및 서비스 임포트
import '../models/location_data.dart';
import '../services/location_service.dart';
import '../services/barometer_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // flutter_map 컨트롤러
  final MapController _mapController = MapController();

  // 위치 및 경로 정보
  Position? _currentPosition; // 현재 위치
  final List<LatLng> _polylinePoints = []; // 이동 경로 저장 리스트

  // 운동 상태 변수
  bool _isWorkoutStarted = false; // 운동 시작 여부
  bool _isPaused = false; // 운동 일시중지 상태

  // 시간 측정용 스톱워치
  final Stopwatch _stopwatch = Stopwatch();
  String _elapsedTime = "00:00:00";

  // 고도 관련 변수
  double _cumulativeElevation = 0.0; // 누적 상승 고도
  double? _baseAltitude; // 기준 고도

  late LocationService _locationService; // 위치 서비스
  late BarometerService _barometerService; // 바로미터 서비스

  @override
  void initState() {
    super.initState();
    // Hive에서 locationBox 가져오기
    final locationBox = Hive.box<LocationData>('locationBox');
    _locationService = LocationService(locationBox);
    _barometerService = BarometerService();

    _requestLocationPermission(); // 위치 권한 요청
  }

  // 위치 권한 요청 메서드
  Future<void> _requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("위치 서비스를 활성화해주세요."))
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // 권한 요청
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("위치 권한이 거부되었습니다."))
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // 영구적으로 거부된 경우 안내
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("위치 권한이 영구적으로 거부되었습니다."))
      );
      return;
    }
    // 여기까지 오면 위치 권한 OK
  }

  // 운동 시작 메서드
  void _startWorkout() async {
    setState(() {
      _isWorkoutStarted = true;
      _stopwatch.start(); // 스톱워치 시작
    });

    // 현재 위치 받아와 지도 중심 이동
    final position = await _locationService.getCurrentPosition();
    setState(() {
      _currentPosition = position;
    });
    _mapController.move(LatLng(position.latitude, position.longitude), 15.0);

    // 실시간 위치 추적 시작: 위치 변경 시마다 callback 호출하여 UI 업데이트
    _locationService.trackLocation((pos) {
      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        _polylinePoints.add(LatLng(pos.latitude, pos.longitude));
        _updateCumulativeElevation(pos);
      });
    });

    _updateElapsedTime(); // 경과 시간 업데이트
  }

  // 운동 일시중지 메서드
  void _pauseWorkout() {
    setState(() {
      _stopwatch.stop();
      _isPaused = true;
    });
  }

  // 운동 종료 메서드
  void _stopWorkout() {
    setState(() {
      _isWorkoutStarted = false;
      _stopwatch.stop();
      _stopwatch.reset();
      _elapsedTime = "00:00:00";
      _polylinePoints.clear();
      _cumulativeElevation = 0.0;
      _baseAltitude = null;
      _isPaused = false;
    });
  }

  // 경과 시간 업데이트(1초마다 재귀적으로 호출)
  void _updateElapsedTime() {
    Future.delayed(const Duration(seconds: 1), () {
      if (_stopwatch.isRunning) {
        setState(() {
          _elapsedTime = _formatTime(_stopwatch.elapsed);
        });
        _updateElapsedTime(); // 재귀 호출로 매초 업데이트
      }
    });
  }

  // 시간 포맷 (HH:MM:SS)
  String _formatTime(Duration duration) {
    String hours = duration.inHours.toString().padLeft(2, '0');
    String minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    String seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return "$hours:$minutes:$seconds";
  }

  // 거리 계산 (km)
  double _calculateDistance() {
    double totalDistance = 0.0;
    for (int i = 1; i < _polylinePoints.length; i++) {
      totalDistance += Geolocator.distanceBetween(
        _polylinePoints[i - 1].latitude,
        _polylinePoints[i - 1].longitude,
        _polylinePoints[i].latitude,
        _polylinePoints[i].longitude,
      );
    }
    return totalDistance / 1000; // meter -> km
  }

  // 평균 속도 계산 (km/h)
  double _calculateAverageSpeed() {
    if (_stopwatch.elapsed.inSeconds == 0) return 0.0;
    double distanceInKm = _calculateDistance();
    double timeInHours = _stopwatch.elapsed.inSeconds / 3600.0;
    return distanceInKm / timeInHours;
  }

  // 고도 업데이트: 현재 고도 계산 후 누적 상승 고도 반영
  void _updateCumulativeElevation(Position position) {
    double currentAltitude = _calculateCurrentAltitude(position);

    // 기준 고도가 없으면 현재 고도를 기준 고도로 설정
    if (_baseAltitude == null) {
      _baseAltitude = currentAltitude;
    } else {
      double elevationDifference = currentAltitude - _baseAltitude!;

      // 3m 이상의 상승일 경우 누적 상승고도 업데이트 후 기준 갱신
      if (elevationDifference > 3.0) {
        _cumulativeElevation += elevationDifference;
        _baseAltitude = currentAltitude;
      } else if (elevationDifference < 0) {
        // 고도가 떨어졌다면 현재 고도를 다시 기준으로 설정
        _baseAltitude = currentAltitude;
      }
    }
  }

  // 현재 고도 계산: 바로미터와 GPS 결합
  double _calculateCurrentAltitude(Position position) {
    // 바로미터 사용 가능 && currentPressure 있음
    if (_barometerService.isBarometerAvailable && _barometerService.currentPressure != null) {
      const double seaLevelPressure = 1013.25; // 표준해수면 기압
      double altitudeFromBarometer = 44330 *
          (1.0 - pow((_barometerService.currentPressure! / seaLevelPressure), 0.1903) as double);

      // GPS 고도와 바로미터 고도를 평균내어 반환
      return (position.altitude + altitudeFromBarometer) / 2;
    } else {
      // 바로미터 불가 시 GPS 고도만 사용
      return position.altitude;
    }
  }

  // 정보 표시용 위젯
  Widget _buildInfoTile(String title, String value) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14, color: Colors.grey),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
        ),
      ],
    );
  }

  // 일시중지/재시작/종료 버튼 처리용 위젯
  Widget _buildPauseResumeButtons() {
    if (!_isPaused) {
      // 운동 중인 상태 -> 중지 버튼 표시
      return SizedBox(
        width: MediaQuery.of(context).size.width * 0.4,
        height: 40,
        child: ElevatedButton(
          onPressed: () {
            setState(() {
              _pauseWorkout();
              _isPaused = true;
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orangeAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text("중지 ⏸️", style: TextStyle(color: Colors.white, fontSize: 15)),
        ),
      );
    } else {
      // 일시정지 상태 -> 재시작/종료 버튼 표시
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 재시작 버튼
          ElevatedButton(
            onPressed: () {
              setState(() {
                _stopwatch.start();
                _isPaused = false;
              });
              _updateElapsedTime();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(120, 48),
            ),
            child: const Text("재시작 ▶", style: TextStyle(color: Colors.white, fontSize: 15)),
          ),
          // 종료 버튼
          ElevatedButton(
            onPressed: _stopWorkout,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(120, 48),
            ),
            child: const Text("종료 ■", style: TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("운동 기록")),
      body: Stack(
        children: [
          // 지도 표시: flutter_map 사용
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(37.5665, 126.9780), // 초기 서울시청 근처 좌표
              initialZoom: 15.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag, // 회전 금지
              ),
            ),
            children: [
              // OSM 타일 레이어
              TileLayer(
                urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
              ),
              // 현재 위치 정확도 원 표시
              if (_currentPosition != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                      radius: _currentPosition!.accuracy, // 정확도 반경(m)
                      useRadiusInMeter: true,
                      color: Colors.blue.withOpacity(0.1), // 반경 색상 및 투명도
                      borderStrokeWidth: 2.0,
                      borderColor: Colors.blue,
                    ),
                  ],
                ),
              // 현재 위치 마커
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                      width: 12.0,
                      height: 12.0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.0),
                        ),
                      ),
                    ),
                  ],
                ),
              // 이동 경로 Polyline
              if (_polylinePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _polylinePoints,
                      strokeWidth: 4.0,
                      color: Colors.blue,
                    ),
                  ],
                ),
            ],
          ),

          // 운동 시작 전: "운동 시작" 버튼
          if (!_isWorkoutStarted)
            Positioned(
              bottom: 20.0,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.8,
                  height: 50.0,
                  child: ElevatedButton(
                    onPressed: _startWorkout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      shadowColor: Colors.black.withAlpha(51),
                      elevation: 5.0,
                    ),
                    child: const Text(
                      "운동 시작",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),

          // 운동 중: 하단 패널에 시간, 거리, 속도, 고도 정보 표시
          if (_isWorkoutStarted)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey,
                      blurRadius: 10,
                      spreadRadius: 2,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("운동시간", style: TextStyle(fontSize: 16, color: Colors.grey)),
                    Text(_elapsedTime, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black)),
                    const SizedBox(height: 16),

                    // 2x2 그리드로 거리, 속도, 현재고도, 누적상승고도 정보 표시
                    GridView.count(
                      shrinkWrap: true,
                      crossAxisCount: 2,
                      mainAxisSpacing: 18.5,
                      crossAxisSpacing: 12,
                      childAspectRatio: 3.5,
                      children: [
                        _buildInfoTile("📍 거리", "${_calculateDistance().toStringAsFixed(1)} km"),
                        _buildInfoTile("⚡ 속도", "${_calculateAverageSpeed().toStringAsFixed(2)} km/h"),
                        _buildInfoTile("🏠 현재고도", "${_currentPosition?.altitude.toInt() ?? 0} m"),
                        _buildInfoTile("📈 누적상승고도", "${_cumulativeElevation.toStringAsFixed(1)} m"),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 중지/재시작/종료 버튼
                    _buildPauseResumeButtons(),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

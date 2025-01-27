import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class UserProfile {
  String name;
  String email;
  int age;
  double weight;
  double height;
  String gender;

  UserProfile({
    required this.name,
    required this.email,
    required this.age,
    required this.weight,
    required this.height,
    required this.gender,
  });
}

class WorkoutGoal {
  final int targetSteps;
  final int targetCalories;
  final double targetDistance;

  WorkoutGoal({
    required this.targetSteps,
    required this.targetCalories,
    required this.targetDistance,
  });
}

class WorkoutStats {
  int steps;
  int calories;
  double distance;
  DateTime date;

  WorkoutStats({
    required this.steps,
    required this.calories,
    required this.distance,
    required this.date,
  });
}

void main() => runApp(const MyApp());


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Advanced Fitness Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const double _minAccuracyThreshold = 20.0;
  static const double _minMovementThreshold = 3.0;
  Position? _lastValidPosition;
  GoogleMapController? mapController;
  Timer? timer;

  bool isTracking = false;
  Position? lastPosition;
  List<LatLng> routePoints = [];

  double distance = 0.0;
  int steps = 0;
  int calories = 0;

  int previousSteps = 0;
  int previousCalories = 0;
  double previousDistance = 0.0;

  WorkoutGoal? currentGoal;
  List<WorkoutStats> workoutHistory = [];
  UserProfile? userProfile;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadStats();
    _loadGoals();
    _loadWorkoutHistory();
    _loadUserProfile();
  }

  Future<void> _requestPermissions() async {
    await Permission.location.request();
    await Permission.activityRecognition.request();
  }

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      previousSteps = prefs.getInt('steps') ?? 0;
      previousCalories = prefs.getInt('calories') ?? 0;
      previousDistance = prefs.getDouble('distance') ?? 0.0;
    });
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userProfile = UserProfile(
        name: prefs.getString('userName') ?? 'User',
        email: prefs.getString('userEmail') ?? 'user@example.com',
        age: prefs.getInt('userAge') ?? 30,
        weight: prefs.getDouble('userWeight') ?? 70.0,
        height: prefs.getDouble('userHeight') ?? 170.0,
        gender: prefs.getString('userGender') ?? 'Not specified',
      );
    });
  }

  Future<void> _loadGoals() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      currentGoal = WorkoutGoal(
        targetSteps: prefs.getInt('goalSteps') ?? 10000,
        targetCalories: prefs.getInt('goalCalories') ?? 500,
        targetDistance: prefs.getDouble('goalDistance') ?? 5000,
      );
    });
  }

  Future<void> _loadWorkoutHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyList = prefs.getStringList('workoutHistory') ?? [];
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Location services are disabled. Please enable them.')));
      }
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permissions are denied')));
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Location permissions are permanently denied')));
      }
      return false;
    }
    return true;
  }

  void _startTracking() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    setState(() {
      isTracking = true;
      routePoints.clear();
      distance = 0.0;
      steps = 0;
      calories = 0;
      _lastValidPosition = null;
    });

    Position initialPosition = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );

    if (initialPosition.accuracy <= _minAccuracyThreshold) {
      setState(() {
        _lastValidPosition = initialPosition;
        routePoints.add(LatLng(initialPosition.latitude, initialPosition.longitude));
      });
    }

    timer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!isTracking) return;

      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
        );

        if (position.accuracy <= _minAccuracyThreshold &&
            position.speed > 0.5 && // Check if actually moving
            _lastValidPosition != null) {

          double newDistance = Geolocator.distanceBetween(
            _lastValidPosition!.latitude,
            _lastValidPosition!.longitude,
            position.latitude,
            position.longitude,
          );

          if (newDistance >= _minMovementThreshold && position.speed > 0.5) {
            setState(() {
              routePoints.add(LatLng(position.latitude, position.longitude));
              distance += newDistance;
              int newSteps = (newDistance / 0.8).round();
              steps += newSteps;
              calories += (newSteps * 0.04).round();
              _lastValidPosition = position;
            });
          }
        }
      } catch (e) {
        print('Error getting location: $e');
      }
    });
  }

  void _stopTracking() {
    setState(() {
      isTracking = false;
      timer?.cancel();
      lastPosition = null;
    });
    _saveWorkoutSession();
  }

  Future<void> _saveWorkoutSession() async {
    if (steps > 0 || distance > 0 || calories > 0) {
      final workout = WorkoutStats(
        steps: steps,
        calories: calories,
        distance: distance,
        date: DateTime.now(),
      );
      workoutHistory.add(workout);
      await _saveWorkoutHistory();
    }
  }

  Future<void> _saveWorkoutHistory() async {
    final prefs = await SharedPreferences.getInstance();
  }

  Future<void> _resetAllStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('steps', 0);
    await prefs.setInt('calories', 0);
    await prefs.setDouble('distance', 0.0);
    await prefs.setStringList('workoutHistory', []);

    setState(() {
      previousSteps = 0;
      previousCalories = 0;
      previousDistance = 0.0;
      steps = 0;
      calories = 0;
      distance = 0.0;
      routePoints.clear();
      workoutHistory.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All stats have been reset'))
      );
    }
  }

  Future<void> _updateProfile() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        String name = userProfile?.name ?? '';
        String email = userProfile?.email ?? '';
        String age = (userProfile?.age ?? '').toString();
        String weight = (userProfile?.weight ?? '').toString();
        String height = (userProfile?.height ?? '').toString();
        String gender = userProfile?.gender ?? '';

        return AlertDialog(
          title: const Text('Edit Profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (value) => name = value,
                  controller: TextEditingController(text: name),
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'Email'),
                  onChanged: (value) => email = value,
                  controller: TextEditingController(text: email),
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'Age'),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => age = value,
                  controller: TextEditingController(text: age),
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'Weight (kg)'),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => weight = value,
                  controller: TextEditingController(text: weight),
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'Height (cm)'),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => height = value,
                  controller: TextEditingController(text: height),
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'Gender'),
                  onChanged: (value) => gender = value,
                  controller: TextEditingController(text: gender),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('userName', name);
                await prefs.setString('userEmail', email);
                await prefs.setInt('userAge', int.tryParse(age) ?? 30);
                await prefs.setDouble('userWeight', double.tryParse(weight) ?? 70.0);
                await prefs.setDouble('userHeight', double.tryParse(height) ?? 170.0);
                await prefs.setString('userGender', gender);

                setState(() {
                  userProfile = UserProfile(
                    name: name,
                    email: email,
                    age: int.tryParse(age) ?? 30,
                    weight: double.tryParse(weight) ?? 70.0,
                    height: double.tryParse(height) ?? 170.0,
                    gender: gender,
                  );
                });
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _setNewGoal() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        int newSteps = currentGoal?.targetSteps ?? 10000;
        int newCalories = currentGoal?.targetCalories ?? 500;
        double newDistance = currentGoal?.targetDistance ?? 5000;

        return AlertDialog(
          title: const Text('Set New Goals'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(labelText: 'Daily Steps Target'),
                keyboardType: TextInputType.number,
                onChanged: (value) => newSteps = int.tryParse(value) ?? newSteps,
              ),
              TextField(
                decoration: const InputDecoration(labelText: 'Daily Calories Target'),
                keyboardType: TextInputType.number,
                onChanged: (value) => newCalories = int.tryParse(value) ?? newCalories,
              ),
              TextField(
                decoration: const InputDecoration(labelText: 'Daily Distance Target (m)'),
                keyboardType: TextInputType.number,
                onChanged: (value) => newDistance = double.tryParse(value) ?? newDistance,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                setState(() {
                  currentGoal = WorkoutGoal(
                    targetSteps: newSteps,
                    targetCalories: newCalories,
                    targetDistance: newDistance,
                  );
                });
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('goalSteps', newSteps);
                await prefs.setInt('goalCalories', newCalories);
                await prefs.setDouble('goalDistance', newDistance);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProfileHeader() {
    return UserAccountsDrawerHeader(
      accountName: Text(userProfile?.name ?? 'User'),
      accountEmail: Text(userProfile?.email ?? 'user@example.com'),
      currentAccountPicture: CircleAvatar(
        backgroundColor: Colors.white,
        child: Text(
          (userProfile?.name.isNotEmpty ?? false) ? userProfile!.name[0] : 'U',
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }

  Widget _buildTrackingView() {
    return Column(
      children: [
        Expanded(
          child: GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(0, 0),
              zoom: 15,
            ),
            onMapCreated: (controller) => mapController = controller,
            myLocationEnabled: true,
            polylines: {
              Polyline(
                polylineId: const PolylineId('route'),
                points: routePoints,
                color: Colors.blue,
                width: 5,
              ),
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat('Distance', '${distance.toStringAsFixed(2)} m'),
                  _buildStat('Steps', steps.toString()),
                  _buildStat('Calories', calories.toString()),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: isTracking ? _stopTracking : _startTracking,
                icon: Icon(isTracking ? Icons.stop : Icons.play_arrow),
                label: Text(isTracking ? 'Stop Tracking' : 'Start Tracking'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Text(value, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  Widget _buildProgressIndicator(String label, double value, double max) {
    return Column(
      children: [
        Text(label),
        LinearProgressIndicator(
          value: value / max,
          backgroundColor: Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(
            value >= max ? Colors.green : Colors.blue,
          ),
        ),
        Text('${value.toStringAsFixed(1)} / ${max.toStringAsFixed(1)}'),
      ],
    );
  }

  Widget _buildGoalsView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daily Goals Progress',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildProgressIndicator(
                    'Steps',
                    (previousSteps + steps).toDouble(),
                    currentGoal?.targetSteps.toDouble() ?? 10000,
                  ),
                  const SizedBox(height: 16),
                  _buildProgressIndicator(
                    'Calories',
                    (previousCalories + calories).toDouble(),
                    currentGoal?.targetCalories.toDouble() ?? 500,
                  ),
                  const SizedBox(height: 16),
                  _buildProgressIndicator(
                    'Distance (m)',
                    previousDistance + distance,
                    currentGoal?.targetDistance ?? 5000,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryView() {
    return ListView.builder(
      itemCount: workoutHistory.length,
      itemBuilder: (context, index) {
        final workout = workoutHistory[workoutHistory.length - 1 - index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Text('Workout ${index + 1}'),
            subtitle: Text(
              'Steps: ${workout.steps} | '
                  'Distance: ${workout.distance.toStringAsFixed(2)}m | '
                  'Calories: ${workout.calories}',
            ),
            trailing: Text(
              '${workout.date.day}/${workout.date.month}/${workout.date.year}',
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fitness Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isTracking ? null : _resetAllStats,
            tooltip: 'Reset All Stats',
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildProfileHeader(),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Profile'),
              onTap: () {
                Navigator.pop(context);
                _updateProfile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.track_changes),
              title: const Text('Goals'),
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => DraggableScrollableSheet(
                    initialChildSize: 0.7,
                    minChildSize: 0.5,
                    maxChildSize: 0.9,
                    builder: (_, controller) => SingleChildScrollView(
                      controller: controller,
                      child: _buildGoalsView(),
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('History'),
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => DraggableScrollableSheet(
                    initialChildSize: 0.7,
                    minChildSize: 0.5,
                    maxChildSize: 0.9,
                    builder: (_, controller) => _buildHistoryView(),
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('About'),
              onTap: () {
                Navigator.pop(context);
                showAboutDialog(
                  context: context,
                  applicationName: 'Fitness Tracker',
                  applicationVersion: '1.0.0',
                );
              },
            ),
          ],
        ),
      ),
      body: _buildTrackingView(),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    mapController?.dispose();
    super.dispose();
  }
}
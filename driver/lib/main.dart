import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth.dart';
import 'history.dart';

const String rideGoFirestoreDatabaseId = 'firestore-db-2';

FirebaseFirestore get rideGoFirestore => FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: rideGoFirestoreDatabaseId,
    );

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const RideGoDriver());
}

class RideGoDriver extends StatelessWidget {
  const RideGoDriver({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'RideGo Driver',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF1565C0),
        ),
        home: const DriverAuthGate(home: DriverHome()),
      );
}

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  GoogleMapController? map;
  LatLng location = const LatLng(17.3850, 78.4867);
  bool locationReady = false;
  bool online = false;
  String status = 'Offline';
  String? driverUid;
  String? rideId;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? rideSubscription;
  Map<String, dynamic>? pendingRide;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ensureSignedIn();
      await locate();
    });
  }

  @override
  void dispose() {
    rideSubscription?.cancel();
    super.dispose();
  }

  Future<void> ensureSignedIn() async {
    if (FirebaseAuth.instance.currentUser == null) {
      final credential = await FirebaseAuth.instance.signInAnonymously();
      driverUid = credential.user!.uid;
    } else {
      driverUid = FirebaseAuth.instance.currentUser!.uid;
    }
  }

  void watchRideRequests() {
    rideSubscription?.cancel();
    rideSubscription = rideGoFirestore
        .collection('rideRequests')
        .where('status', isEqualTo: 'requested')
        .limit(20)
        .snapshots()
        .listen((snapshot) {
      if (!mounted || !online) return;
      if (snapshot.docs.isEmpty) {
        // After accepting a ride, it is no longer returned by the
        // "requested" query. Keep the active ride so the driver can
        // advance it through ARRIVED -> STARTED -> COMPLETED.
        if (rideId != null && status != 'Online — waiting for rides') {
          return;
        }
        setState(() {
          pendingRide = null;
          rideId = null;
          status = 'Online — waiting for rides';
        });
        return;
      }
      final doc = snapshot.docs.first;
      setState(() {
        rideId = doc.id;
        pendingRide = doc.data();
        status = 'New ride request';
      });
    });
  }

  Future<void> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => status = 'Turn on Location to continue');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => status = 'Location permission is required');
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final current = LatLng(position.latitude, position.longitude);

      if (!mounted) return;
      setState(() {
        location = current;
        locationReady = true;
        if (!online) status = 'Offline';
      });
      map?.animateCamera(CameraUpdate.newLatLngZoom(current, 15));
    } catch (_) {
      if (mounted) setState(() => status = 'Unable to get current location');
    }
  }

  Future<void> toggle() async {
    if (!online) {
      await ensureSignedIn();
      setState(() {
        online = true;
        status = 'Online — waiting for rides';
        pendingRide = null;
        rideId = null;
      });
      watchRideRequests();
    } else {
      await rideSubscription?.cancel();
      rideSubscription = null;
      setState(() {
        online = false;
        pendingRide = null;
        rideId = null;
        status = 'Offline';
      });
    }
  }

  Future<void> accept() async {
    final id = rideId;
    if (id == null || driverUid == null) return;
    try {
      await rideGoFirestore.collection('rideRequests').doc(id).update({
        'status': 'accepted',
        'driverId': driverUid,
        'acceptedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() => status = 'DRIVER_ACCEPTED');
    } catch (_) {
      if (mounted) setState(() => status = 'Unable to accept ride');
    }
  }

  Future<void> next() async {
    final id = rideId;
    if (id == null) return;
    final nextStatus = switch (status) {
      'DRIVER_ACCEPTED' => 'arrived',
      'DRIVER_ARRIVED' => 'started',
      'TRIP_STARTED' => 'completed',
      _ => null,
    };
    if (nextStatus == null) return;
    try {
      await rideGoFirestore.collection('rideRequests').doc(id).update({
        'status': nextStatus,
        if (nextStatus == 'arrived') 'arrivedAt': FieldValue.serverTimestamp(),
        if (nextStatus == 'started') 'startedAt': FieldValue.serverTimestamp(),
        if (nextStatus == 'completed') 'completedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() {
        status = switch (nextStatus) {
          'arrived' => 'DRIVER_ARRIVED',
          'started' => 'TRIP_STARTED',
          'completed' => 'COMPLETED',
          _ => status,
        };
        if (nextStatus == 'completed') pendingRide = null;
      });
    } catch (_) {
      if (mounted) setState(() => status = 'Unable to update ride');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition:
                  CameraPosition(target: location, zoom: 14),
              myLocationEnabled: locationReady,
              myLocationButtonEnabled: false,
              onMapCreated: (controller) => map = controller,
              markers: {
                Marker(
                  markerId: const MarkerId('driver'),
                  position: location,
                  infoWindow: const InfoWindow(title: 'Driver location'),
                ),
              },
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Trip history',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DriverHistoryScreen()),
                      ),
                      icon: const Icon(Icons.person),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'RideGo Driver',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: locate,
                      icon: const Icon(Icons.my_location),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Driver status',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Chip(
                          label: Text(online ? 'ONLINE' : 'OFFLINE'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(status),
                    const SizedBox(height: 12),
                    if (online && pendingRide != null && rideId != null)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.notifications_active),
                          title: Text(
                            (pendingRide!['vehicle'] ?? 'Ride').toString() + ' request',
                          ),
                          subtitle: Text(
                            'Pickup nearby • ₹' +
                                (pendingRide!['fare'] ?? 0).toString() +
                                ' • ' +
                                (pendingRide!['distanceKm'] ?? 0).toString() +
                                ' km',
                          ),
                          trailing: FilledButton(
                            onPressed: accept,
                            child: const Text('ACCEPT'),
                          ),
                        ),
                      ),
                    if (rideId != null && status != 'COMPLETED')
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: next,
                          child: Text(
                            status == 'DRIVER_ACCEPTED'
                                ? 'DRIVER ARRIVED'
                                : status == 'DRIVER_ARRIVED'
                                    ? 'START TRIP'
                                    : 'COMPLETE TRIP',
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton(
                        onPressed: toggle,
                        child: Text(online ? 'GO OFFLINE' : 'GO ONLINE'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

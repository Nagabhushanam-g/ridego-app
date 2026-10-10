import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth.dart';
import 'history.dart';
import 'notification_service.dart';

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
        title: 'RideGo Partner',
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
  List<LatLng> navigationRoute = [];
  LatLng? navigationTarget;
  int navigationGeneration = 0;
  String? navigationRideId;
  String? navigationPhase;
  bool online = false;
  String status = 'Offline';
  String? driverUid;
  String? rideId;
  StreamSubscription? rideSubscription;
  Map<String, dynamic>? pendingRide;
  bool noInternet = false;
  StreamSubscription<List<ConnectivityResult>>? connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _monitorConnectivity();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ensureSignedIn();
      await RideGoNotificationService.initialize(context, role: 'driver');
      await restoreActiveRide();
      await _restoreOnlinePreference();
      await locate();
    });
  }

  @override
  void dispose() {
    navigationGeneration++;
    connectivitySubscription?.cancel();
    rideSubscription?.cancel();
    super.dispose();
  }

  Future<void> _monitorConnectivity() async {
    final connectivity = Connectivity();

    void apply(List<ConnectivityResult> results) {
      final disconnected =
          results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      if (!mounted || disconnected == noInternet) return;

      final wasOffline = noInternet;
      setState(() => noInternet = disconnected);

      if (wasOffline && !disconnected) {
        // Re-sync the assignment before returning to the waiting state.
        restoreActiveRide().then((_) {
          if (mounted && online && !hasAssignedRide) {
            watchRideRequests();
          }
        });
      }
    }

    apply(await connectivity.checkConnectivity());
    connectivitySubscription = connectivity.onConnectivityChanged.listen(apply);
  }

  Future<void> ensureSignedIn() async {
    if (FirebaseAuth.instance.currentUser == null) {
      final credential = await FirebaseAuth.instance.signInAnonymously();
      driverUid = credential.user!.uid;
    } else {
      driverUid = FirebaseAuth.instance.currentUser!.uid;
    }
  }

  String driverUiStatus(String firestoreStatus) => switch (firestoreStatus) {
        'accepted' => 'DRIVER_ACCEPTED',
        'arrived' => 'DRIVER_ARRIVED',
        'started' => 'TRIP_STARTED',
        'completed' => 'COMPLETED',
        _ => 'Online — waiting for rides',
      };

  Future<void> restoreActiveRide() async {
    final uid = driverUid;
    if (uid == null) return;
    try {
      final snapshot = await rideGoFirestore
          .collection('rideRequests')
          .where('driverId', isEqualTo: uid)
          .get();

      QueryDocumentSnapshot<Map<String, dynamic>>? active;
      for (final doc in snapshot.docs) {
        final rideStatus = (doc.data()['status'] ?? '').toString();
        if (rideStatus == 'accepted' ||
            rideStatus == 'arrived' ||
            rideStatus == 'started') {
          active = doc;
          break;
        }
      }

      if (active == null || !mounted) return;
      setState(() {
        online = true;
        rideId = active!.id;
        pendingRide = active.data();
        status = driverUiStatus((active.data()['status'] ?? '').toString());
      });
      watchAssignedRide(active.id);
      _refreshNavigation();
    } catch (_) {
      // Startup recovery is best-effort; driver can still go online manually.
    }
  }

  // Remember an explicit online choice across Android process termination.
  // This restores the UI and request listener, not background availability.
  Future<void> _restoreOnlinePreference() async {
    if (!mounted || hasAssignedRide) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('driver_online_preference') != true || !mounted) return;
      await _recordAvailability(true);
      if (!mounted || hasAssignedRide) return;
      setState(() {
        online = true;
        status = 'Online — waiting for rides';
      });
      watchRideRequests();
    } catch (error) {
      debugPrint('Unable to restore driver online status: $error');
    }
  }

  LatLng? _ridePoint(String key) {
    final value = pendingRide?[key];
    if (value is! Map) return null;
    final lat = value['latitude'];
    final lng = value['longitude'];
    if (lat is! num || lng is! num) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  List<LatLng> _decodeNavigationPolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      final values = <int>[];
      for (var coordinate = 0; coordinate < 2; coordinate++) {
        var shift = 0, result = 0, byte = 0;
        do {
          if (index >= encoded.length) throw const FormatException('Invalid polyline');
          byte = encoded.codeUnitAt(index++) - 63;
          result |= (byte & 0x1f) << shift;
          shift += 5;
        } while (byte >= 0x20);
        values.add((result & 1) != 0 ? ~(result >> 1) : result >> 1);
      }
      lat += values[0];
      lng += values[1];
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  Future<void> _frameNavigation(List<LatLng> points) async {
    final controller = map;
    if (controller == null || points.isEmpty || !mounted) return;
    if (points.length == 1) {
      await controller.animateCamera(CameraUpdate.newLatLngZoom(points.first, 14));
      return;
    }
    var minLat = points.first.latitude, maxLat = minLat;
    var minLng = points.first.longitude, maxLng = minLng;
    for (final point in points.skip(1)) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    try {
      await controller.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - 0.002, minLng - 0.002),
          northeast: LatLng(maxLat + 0.002, maxLng + 0.002),
        ),
        70,
      ));
    } catch (_) {
      // Map may not have completed its first layout.
    }
  }

  void _refreshNavigation() {
    if (!hasAssignedRide || !locationReady) return;
    final phase = status == 'TRIP_STARTED' ? 'destination' : 'pickup';
    final target = _ridePoint(phase);
    final id = rideId;
    if (target == null || id == null) return;
    if (navigationRideId == id && navigationPhase == phase) return;
    navigationRideId = id;
    navigationPhase = phase;
    final generation = ++navigationGeneration;
    setState(() {
      navigationTarget = target;
      navigationRoute = [];
    });
    FirebaseFunctions.instance.httpsCallable('computeRideRoute').call({
      'origin': {'latitude': location.latitude, 'longitude': location.longitude},
      'destination': {'latitude': target.latitude, 'longitude': target.longitude},
    }).then((result) async {
      if (!mounted || generation != navigationGeneration) return;
      final data = Map<String, dynamic>.from(result.data as Map);
      final encoded = data['encodedPolyline'];
      if (encoded is! String) return;
      final points = _decodeNavigationPolyline(encoded);
      if (points.length < 2) return;
      setState(() => navigationRoute = points);
      await _frameNavigation(points);
    }).catchError((Object _) {
      // Keep pickup/destination markers visible if routing is unavailable.
    });
  }

  void _clearNavigation() {
    navigationGeneration++;
    navigationRideId = null;
    navigationPhase = null;
    navigationTarget = null;
    navigationRoute = [];
  }

  void watchAssignedRide(String id) {
    rideSubscription?.cancel();
    rideSubscription = rideGoFirestore
        .collection('rideRequests')
        .doc(id)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final data = snapshot.data();
      if (data == null) return;
      final rideStatus = (data['status'] ?? '').toString();
      if (rideStatus == 'completed' || rideStatus == 'cancelled') {
        _clearNavigation();
        setState(() {
          pendingRide = null;
          rideId = null;
          status = online ? 'Online — waiting for rides' : 'Offline';
        });
        if (online) watchRideRequests();
        return;
      }
      setState(() {
        pendingRide = data;
        status = driverUiStatus(rideStatus);
      });
      _refreshNavigation();
    });
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
      // A Firestore status of "requested" alone does not mean a ride is
      // new. Old requests can survive an app update or a missed expiry job.
      // Never surface cached, undated, assigned, or expired requests.
      final now = DateTime.now();
      final eligible = snapshot.docs.where((doc) {
        final data = doc.data();
        final createdAt = data['createdAt'];
        if (createdAt is! Timestamp || data['driverId'] != null) {
          return false;
        }
        final age = now.difference(createdAt.toDate());
        return age >= const Duration(seconds: -30) &&
            age < const Duration(minutes: 5);
      }).toList()
        ..sort((a, b) {
          final aTime = (a.data()['createdAt'] as Timestamp).toDate();
          final bTime = (b.data()['createdAt'] as Timestamp).toDate();
          return bTime.compareTo(aTime);
        });
      if (eligible.isEmpty) {
        if (hasAssignedRide) return;
        setState(() {
          pendingRide = null;
          rideId = null;
          status = 'Online — waiting for rides';
        });
        return;
      }
      final doc = eligible.first;
      if (hasAssignedRide) return;
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
      if (hasAssignedRide) {
        _refreshNavigation();
      } else {
        map?.animateCamera(CameraUpdate.newLatLngZoom(current, 15));
      }
    } catch (_) {
      if (mounted) setState(() => status = 'Unable to get current location');
    }
  }

  bool get hasAssignedRide =>
      rideId != null &&
      (status == 'DRIVER_ACCEPTED' ||
          status == 'DRIVER_ARRIVED' ||
          status == 'TRIP_STARTED');

  // Records explicit availability choices. This is not a crash-safe
  // presence detector; server-side presence/heartbeat expiry is still needed.
  Future<void> _recordAvailability(bool value) async {
    final uid = driverUid;
    if (uid == null) throw StateError('Driver not signed in');
    await rideGoFirestore.collection('users').doc(uid).set({
      'uid': uid,
      'isOnline': value,
      'availabilityUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> toggle() async {
    if (noInternet) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No internet connection')),
        );
      }
      return;
    }
    if (online && hasAssignedRide) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complete the active ride before going offline.'),
          ),
        );
      }
      return;
    }

    if (!online) {
      await ensureSignedIn();

      // Always restore an existing assignment before listening for new work.
      await restoreActiveRide();
      if (!mounted) return;
      if (hasAssignedRide) return;

      try {
        await _recordAvailability(true);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to go online. Check your connection.')),
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        online = true;
        status = 'Online — waiting for rides';
        pendingRide = null;
        rideId = null;
      });
      await (await SharedPreferences.getInstance()).setBool('driver_online_preference', true);
      watchRideRequests();
    } else {
      try {
        await _recordAvailability(false);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to save offline status. Please retry.')),
          );
        }
        return;
      }
      if (!mounted) return;
      await (await SharedPreferences.getInstance()).setBool('driver_online_preference', false);
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
    if (noInternet) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No internet connection')),
        );
      }
      return;
    }
    final id = rideId;
    if (id == null || driverUid == null) return;
    try {
      await rideGoFirestore.runTransaction((transaction) async {
        final ref = rideGoFirestore.collection('rideRequests').doc(id);
        final snapshot = await transaction.get(ref);
        final data = snapshot.data();
        if (!snapshot.exists ||
            data == null ||
            data['status'] != 'requested' ||
            data['driverId'] != null ||
            data['createdAt'] is! Timestamp ||
            DateTime.now().difference(
              (data['createdAt'] as Timestamp).toDate(),
            ) >= const Duration(minutes: 5) ||
            DateTime.now().difference(
              (data['createdAt'] as Timestamp).toDate(),
            ) < const Duration(seconds: -30)) {
          throw StateError('Ride is no longer available');
        }
        transaction.update(ref, {
          'status': 'accepted',
          'driverId': driverUid,
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      });
      if (mounted) {
        setState(() => status = 'DRIVER_ACCEPTED');
        watchAssignedRide(id);
        _refreshNavigation();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        pendingRide = null;
        rideId = null;
        status = online ? 'Online — waiting for rides' : 'Offline';
      });
      if (online) watchRideRequests();
    }
  }

  Future<void> verifyStartPin() async {
    final id = rideId;
    if (id == null || status != 'DRIVER_ARRIVED' || noInternet) return;
    String enteredPin = '';
    final pin = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Verify rider PIN'),
        content: TextField(
          keyboardType: TextInputType.number,
          maxLength: 4,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) => enteredPin = value,
          decoration: const InputDecoration(labelText: '4-digit PIN from rider'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, enteredPin), child: const Text('VERIFY')),
        ],
      ),
    );
    if (pin == null || pin.length != 4 || !mounted) return;
    try {
      await rideGoFirestore.collection('rideRequests').doc(id).collection('pinVerification').doc('verified').set({
        'pin': pin,
        'driverId': driverUid,
        'verifiedAt': FieldValue.serverTimestamp(),
      });
      if (mounted && rideId == id) await next();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect PIN or verification failed. Ask the rider to confirm the PIN.')),
      );
    }
  }

  Future<void> next() async {
    if (noInternet) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No internet connection')),
        );
      }
      return;
    }
    final id = rideId;
    if (id == null) return;
    if (status == 'DRIVER_ARRIVED') {
      try {
        final proof = await rideGoFirestore.collection('rideRequests').doc(id).collection('pinVerification').doc('verified').get();
        if (!proof.exists) return;
      } catch (_) { return; }
    }
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
        if (nextStatus == 'completed') {
          pendingRide = null;
          rideId = null;
        }
      });

      if (nextStatus == 'started') _refreshNavigation();
      if (nextStatus == 'completed') _clearNavigation();
      if (nextStatus == 'completed') {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted && online && rideId == null) {
          setState(() => status = 'Online — waiting for rides');
        }
      }
    } catch (_) {
      if (mounted) setState(() => status = 'Unable to update ride');
    }
  }

  String get friendlyDriverStatus => switch (status) {
    'DRIVER_ACCEPTED' => 'Ride accepted — head to pickup',
    'DRIVER_ARRIVED' => 'Arrived at pickup',
    'TRIP_STARTED' => 'Trip in progress — head to destination',
    'COMPLETED' => 'Trip completed',
    _ => status,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (rideId != null &&
                (status == 'DRIVER_ACCEPTED' ||
                    status == 'DRIVER_ARRIVED' ||
                    status == 'TRIP_STARTED'))
              GoogleMap(
              initialCameraPosition:
                  CameraPosition(target: location, zoom: 14),
              myLocationEnabled: locationReady,
              myLocationButtonEnabled: false,
              onMapCreated: (controller) {
                map = controller;
                if (navigationRoute.isNotEmpty) {
                  _frameNavigation(navigationRoute);
                } else if (navigationTarget != null) {
                  _frameNavigation([location, navigationTarget!]);
                }
              },
              polylines: navigationRoute.length > 1 ? {
                Polyline(
                  polylineId: const PolylineId('driver_navigation'),
                  points: navigationRoute,
                  color: const Color(0xFF1565C0),
                  width: 6,
                ),
              } : {},
              markers: {
                if (navigationTarget != null)
                  Marker(
                    markerId: const MarkerId('navigation_target'),
                    position: navigationTarget!,
                    infoWindow: InfoWindow(title: status == 'TRIP_STARTED' ? 'Destination' : 'Pickup'),
                  ),
                Marker(
                  markerId: const MarkerId('driver'),
                  position: location,
                  infoWindow: const InfoWindow(title: 'Driver location'),
                ),
              },
            ),
            if (rideId == null ||
                !['DRIVER_ACCEPTED', 'DRIVER_ARRIVED', 'TRIP_STARTED'].contains(status))
              Positioned.fill(
                child: ColoredBox(
                  color: const Color(0xFFF1F4F8),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 92, 20, 240),
                      child: Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset(
                            'assets/images/ridego_promo.jpg',
                            fit: BoxFit.contain,
                            width: double.infinity,
                            errorBuilder: (_, __, ___) => const Card(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'RideGo • Bike  |  Auto  |  Cab',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
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
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            fontStyle: FontStyle.italic,
                          ),
                          children: [
                            TextSpan(
                              text: 'Ride',
                              style: TextStyle(color: Color(0xFF102B57)),
                            ),
                            TextSpan(
                              text: 'Go',
                              style: TextStyle(color: Color(0xFF00A85A)),
                            ),
                            TextSpan(
                              text: ' Partner',
                              style: TextStyle(color: Color(0xFF00833E)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (rideId != null &&
                        ['DRIVER_ACCEPTED', 'DRIVER_ARRIVED', 'TRIP_STARTED'].contains(status))
                      IconButton.filledTonal(
                        onPressed: locate,
                        icon: const Icon(Icons.my_location),
                      ),
                  ],
                  ),
                ),
              ),
            ),
            if (noInternet)
              Positioned(
                top: MediaQuery.of(context).padding.top + 76,
                left: 16,
                right: 16,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.wifi_off),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No internet connection — reconnecting…',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
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
                          'Partner status',
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
                    Text(friendlyDriverStatus),
                    if (rideId != null &&
                        pendingRide != null &&
                        (status == 'DRIVER_ACCEPTED' ||
                            status == 'DRIVER_ARRIVED' ||
                            status == 'TRIP_STARTED')) ...[
                      const SizedBox(height: 8),
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.flag_outlined),
                        title: const Text('Destination'),
                        subtitle: Text(
                          (pendingRide!['destinationAddress'] ?? 'Destination unavailable').toString(),
                          maxLines: 3,
                        ),
                        trailing: Text(
                          '₹${pendingRide!['fare'] ?? 0}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (online &&
                        pendingRide != null &&
                        rideId != null &&
                        status == 'New ride request')
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.notifications_active),
                          title: Text(
                            (pendingRide!['vehicle'] ?? 'Ride').toString() + ' request',
                          ),
                          subtitle: Text(
                            'Fare ₹' +
                                (pendingRide!['fare'] ?? 0).toString() +
                                ' • Trip distance ' +
                                (pendingRide!['distanceKm'] ?? 0).toString() +
                                ' km',
                          ),
                          trailing: FilledButton(
                            onPressed: noInternet ? null : accept,
                            child: const Text('ACCEPT'),
                          ),
                        ),
                      ),
                    if (rideId != null &&
                        (status == 'DRIVER_ACCEPTED' ||
                            status == 'DRIVER_ARRIVED' ||
                            status == 'TRIP_STARTED'))
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: noInternet ? null : (status == 'DRIVER_ARRIVED' ? verifyStartPin : next),
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
                        onPressed: noInternet ? null : toggle,
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

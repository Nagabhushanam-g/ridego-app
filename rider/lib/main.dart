import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'auth.dart';
import 'history.dart';
import 'notification_service.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

const String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
const String androidCertSha1 = String.fromEnvironment('GOOGLE_MAPS_ANDROID_CERT');
const String rideGoFirestoreDatabaseId = 'firestore-db-2';
const MethodChannel riderLocationChannel = MethodChannel('com.ridego.rider/location');

FirebaseFirestore get rideGoFirestore => FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: rideGoFirestoreDatabaseId,
    );

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const RideGoRider());
}

class RideGoRider extends StatelessWidget {
  const RideGoRider({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'RideGo Rider',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF1565C0),
        ),
        home: const RiderAuthGate(home: RiderHome()),
      );
}

class RiderHome extends StatefulWidget {
  const RiderHome({super.key});

  @override
  State<RiderHome> createState() => _RiderHomeState();
}

class _RiderHomeState extends State<RiderHome> {
  GoogleMapController? map;
  LatLng pickup = const LatLng(17.3850, 78.4867);
  LatLng? destination;
  String destinationAddress = '';
  String pickupAddress = '';
  String vehicle = 'Bike';
  String status = 'Choose your destination';
  int fare = 0;
  double distanceKm = 0;
  List<LatLng> roadRoute = [];
  int? drivingMinutes;
  int routeGeneration = 0;
  bool routeLoading = false;
  String? routeError;
  bool locationReady = false;
  bool searching = false;
  bool selectingPlace = false;
  bool get rideActive => rideId != null;
  String? searchError;
  bool noInternet = false;
  bool locationServiceEnabled = true;
  bool selectingPickup = false;
  StreamSubscription<List<ConnectivityResult>>? connectivitySubscription;
  StreamSubscription<ServiceStatus>? locationServiceSubscription;
  Timer? destinationSearchDebounce;
  Timer? rideExpiryCheck;
  int destinationSearchGeneration = 0;

  final TextEditingController destinationSearchController =
      TextEditingController();

  List<_PlaceSuggestion> suggestions = [];
  String? riderUid;
  String? rideId;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? rideSubscription;

  @override
  void initState() {
    super.initState();
    _monitorConnectivity();
    _monitorLocationService();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await RideGoNotificationService.initialize(context, role: 'rider');
      await restoreActiveRide();
      await locate();
    });
  }

  @override
  void dispose() {
    connectivitySubscription?.cancel();
    locationServiceSubscription?.cancel();
    rideSubscription?.cancel();
    destinationSearchDebounce?.cancel();
    rideExpiryCheck?.cancel();
    destinationSearchController.dispose();
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
        // Firestore is authoritative after a reconnect. Rehydrate instead of
        // trusting UI state that may have been displayed while disconnected.
        restoreActiveRide();
      }
    }

    apply(await connectivity.checkConnectivity());
    connectivitySubscription = connectivity.onConnectivityChanged.listen(apply);
  }

  Future<void> _monitorLocationService() async {
    locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    locationServiceSubscription =
        Geolocator.getServiceStatusStream().listen((serviceStatus) {
      final enabled = serviceStatus == ServiceStatus.enabled;
      if (!mounted) return;
      setState(() {
        locationServiceEnabled = enabled;
        if (!enabled && !rideActive) {
          locationReady = false;
          status = 'Location is turned off';
        }
      });
      if (enabled && !rideActive) {
        locate();
      }
    });
  }

  Future<void> _resolvePickupAddress(LatLng point) async {
    // Prefer Android's native Geocoder. It does not depend on the Maps API
    // key's web-service restrictions and keeps a working map configuration
    // independent from pickup-address lookup.
    try {
      final address = await riderLocationChannel.invokeMethod<String>(
        'reverseGeocode',
        {
          'latitude': point.latitude,
          'longitude': point.longitude,
        },
      );
      if (mounted && address != null && address.trim().isNotEmpty) {
        setState(() => pickupAddress = address.trim());
        return;
      }
    } on PlatformException {
      // Fall through to the Google Geocoding API when native lookup is
      // unavailable on a particular Android device.
    } on MissingPluginException {
      // Fall through for safety on unsupported builds.
    }

    if (googleMapsApiKey.isEmpty || noInternet) return;
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '${point.latitude},${point.longitude}',
        'key': googleMapsApiKey,
        'language': 'en',
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? const [];
      if (!mounted || results.isEmpty) return;
      final address =
          (results.first as Map<String, dynamic>)['formatted_address'] as String?;
      if (address != null && address.trim().isNotEmpty) {
        setState(() => pickupAddress = address.trim());
      }
    } catch (_) {
      // Coordinates remain usable even when reverse geocoding is unavailable.
    }
  }

  void _beginPickupSelection() {
    if (rideActive) return;
    setState(() {
      selectingPickup = true;
      status = 'Tap the map to choose pickup';
    });
  }

  void _selectPickup(LatLng point) {
    setState(() {
      pickup = point;
      selectingPickup = false;
      locationReady = false;
      status = 'Pickup selected';
    });
    _resolvePickupAddress(point);
    recalculateFare();
    map?.animateCamera(CameraUpdate.newLatLngZoom(point, 15));
  }

  Future<void> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted && !rideActive) {
          setState(() {
            locationServiceEnabled = false;
            locationReady = false;
            status = 'Location is turned off';
          });
        }
        return;
      }
      if (mounted) setState(() => locationServiceEnabled = true);

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted && !rideActive) {
          setState(() => status = 'Location permission is required');
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final current = LatLng(position.latitude, position.longitude);

      if (!mounted) return;
      setState(() {
        // Location refresh must not overwrite a restored active-ride state
        // such as DRIVER_ACCEPTED, DRIVER_ARRIVED, or TRIP_STARTED.
        if (!rideActive) {
          pickup = current;
          status = 'Choose your destination';
        }
        locationReady = true;
      });

      _resolvePickupAddress(current);
      map?.animateCamera(CameraUpdate.newLatLngZoom(current, 15));
    } catch (_) {
      if (mounted && !rideActive) {
        setState(() => status = 'Unable to get current location');
      }
    }
  }

  void _onDestinationChanged(String value) {
    destinationSearchDebounce?.cancel();
    final query = value.trim();

    if (query.length < 2) {
      destinationSearchGeneration++;
      if (mounted) {
        setState(() {
          suggestions = [];
          searchError = null;
          searching = false;
        });
      }
      return;
    }

    destinationSearchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => searchDestinations(query),
    );
  }

  Future<void> searchDestinations(String value) async {
    final generation = ++destinationSearchGeneration;
    if (noInternet) {
      if (mounted) setState(() => searchError = 'No internet connection');
      return;
    }
    final query = value.trim();
    if (query.length < 2) return;
    setState(() {
      searching = true;
      searchError = null;
    });
    try {
      final raw = await riderLocationChannel.invokeMethod<List<dynamic>>(
        'searchPlaces',
        {'query': query},
      );
      if (!mounted || generation != destinationSearchGeneration) return;
      final parsed = (raw ?? const <dynamic>[]).map((item) {
        final value = Map<String, dynamic>.from(item as Map);
        final id = value['placeId']?.toString();
        final label = value['label']?.toString();
        if (id == null || label == null || label.isEmpty) return null;
        return _PlaceSuggestion(placeId: id, label: label);
      }).whereType<_PlaceSuggestion>().toList();
      setState(() {
        suggestions = parsed;
        searching = false;
        searchError = parsed.isEmpty ? 'No destinations found' : null;
      });
    } on PlatformException catch (error) {
      if (!mounted || generation != destinationSearchGeneration) return;
      final code = error.code.trim();
      final message = (error.message ?? '').replaceAll(RegExp(r'\\s+'), ' ').trim();
      var detail = code.isEmpty ? 'Native Places error' : code;
      if (message.isNotEmpty) detail = '$detail: $message';
      if (detail.length > 220) detail = '${detail.substring(0, 217)}...';
      setState(() {
        searching = false;
        suggestions = [];
        searchError = 'Destination search error: $detail';
      });
    } catch (error) {
      if (!mounted || generation != destinationSearchGeneration) return;
      setState(() {
        searching = false;
        suggestions = [];
        searchError = 'Destination search error: ${error.runtimeType}';
      });
    }
  }

  Future<void> selectPlace(_PlaceSuggestion suggestion) async {
    if (noInternet) {
      if (mounted) setState(() => searchError = 'No internet connection');
      return;
    }
    setState(() {
      selectingPlace = true;
      searchError = null;
      suggestions = [];
    });
    try {
      final raw = await riderLocationChannel.invokeMethod<Map<dynamic, dynamic>>(
        'placeDetails',
        {'placeId': suggestion.placeId},
      );
      final data = raw == null ? null : Map<String, dynamic>.from(raw);
      final lat = (data?['latitude'] as num?)?.toDouble();
      final lng = (data?['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) throw const FormatException();
      final address = data?['address']?.toString().trim();
      destinationSearchController.text = suggestion.label;
      selectDestination(
        LatLng(lat, lng),
        address: address != null && address.isNotEmpty ? address : suggestion.label,
        moveCamera: true,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          selectingPlace = false;
          searchError = 'Unable to load this destination';
        });
      }
    }
  }

  List<LatLng> _decodeRoute(String encoded) {
    final points = <LatLng>[];
    var index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      final values = <int>[];
      for (var axis = 0; axis < 2; axis++) {
        var result = 0, shift = 0, chunk = 0;
        do {
          if (index >= encoded.length) throw const FormatException('Invalid route');
          chunk = encoded.codeUnitAt(index++) - 63;
          result |= (chunk & 0x1f) << shift;
          shift += 5;
        } while (chunk >= 0x20);
        values.add((result & 1) != 0 ? ~(result >> 1) : result >> 1);
      }
      lat += values[0];
      lng += values[1];
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  Future<void> _loadRoadRoute(LatLng origin, LatLng target) async {
    final generation = ++routeGeneration;
    setState(() {
      routeLoading = true;
      roadRoute = [];
      drivingMinutes = null;
      routeError = null;
    });
    try {
      final result = await FirebaseFunctions.instance.httpsCallable(
        'computeRideRoute',
      ).call({
        'origin': {'latitude': origin.latitude, 'longitude': origin.longitude},
        'destination': {'latitude': target.latitude, 'longitude': target.longitude},
      });
      if (!mounted || generation != routeGeneration || rideActive) return;
      final data = Map<String, dynamic>.from(result.data as Map);
      final meters = (data['distanceMeters'] as num).toDouble();
      final seconds = (data['durationSeconds'] as num).toDouble();
      final points = _decodeRoute(data['encodedPolyline'] as String);
      if (points.length < 2 || meters <= 0) throw const FormatException('Empty route');
      final km = meters / 1000;
      final base = switch (vehicle) { 'Auto' => 40, 'Cab' => 70, _ => 30 };
      final rate = switch (vehicle) { 'Auto' => 16, 'Cab' => 22, _ => 12 };
      final minimum = switch (vehicle) { 'Auto' => 60, 'Cab' => 100, _ => 40 };
      setState(() {
        distanceKm = km;
        fare = math.max(minimum, (base + km * rate).ceil()).toInt();
        drivingMinutes = (seconds / 60).ceil();
        roadRoute = points;
        routeLoading = false;
      });
      await _fitRouteOnMap(points);
    } catch (_) {
      if (!mounted || generation != routeGeneration || rideActive) return;
      setState(() {
        routeLoading = false;
        routeError = 'Road route unavailable; fare is an estimate';
      });
    }
  }

  Future<void> _fitRouteOnMap(List<LatLng> points) async {
    final controller = map;
    if (controller == null || points.length < 2 || !mounted) return;
    var south = points.first.latitude;
    var north = south;
    var west = points.first.longitude;
    var east = west;
    for (final point in points.skip(1)) {
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
    }
    // Avoid zero-size bounds for very short journeys.
    const margin = 0.001;
    try {
      await controller.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south - margin, west - margin),
          northeast: LatLng(north + margin, east + margin),
        ),
        72,
      ));
    } catch (_) {
      // Camera fitting is visual-only; never block destination selection.
    }
  }

  void selectDestination(
    LatLng point, {
    String? address,
    bool moveCamera = false,
  }) {
    final meters = Geolocator.distanceBetween(
      pickup.latitude,
      pickup.longitude,
      point.latitude,
      point.longitude,
    );
    final km = meters / 1000.0;

    final baseFare = switch (vehicle) {
      'Bike' => 30,
      'Auto' => 40,
      'Cab' => 70,
      _ => 30,
    };
    final perKm = switch (vehicle) {
      'Bike' => 12,
      'Auto' => 16,
      'Cab' => 22,
      _ => 12,
    };

    final minimumFare = switch (vehicle) {
      'Bike' => 40,
      'Auto' => 60,
      'Cab' => 100,
      _ => 40,
    };

    final calculatedFare = math.max(
      minimumFare,
      (baseFare + (km * perKm)).ceil(),
    ).toInt();

    setState(() {
      destination = point;
      destinationAddress = address ?? '';
      distanceKm = km;
      fare = calculatedFare;
      status = 'Destination selected';
      selectingPlace = false;
      suggestions = [];
      searchError = null;
    });

    _loadRoadRoute(pickup, point);

    if (moveCamera) {
      _fitRouteOnMap([pickup, point]);
    }
  }

  int _fareFor(String type, double km) {
    final base = switch (type) { 'Auto' => 40, 'Cab' => 70, _ => 30 };
    final rate = switch (type) { 'Auto' => 16, 'Cab' => 22, _ => 12 };
    final minimum = switch (type) { 'Auto' => 60, 'Cab' => 100, _ => 40 };
    return math.max(minimum, (base + km * rate).ceil()).toInt();
  }

  void recalculateFare() {
    if (destination != null) {
      selectDestination(
        destination!,
        address: destinationAddress.isEmpty ? null : destinationAddress,
      );
    }
  }

  Future<void> ensureSignedIn() async {
    if (FirebaseAuth.instance.currentUser != null) {
      riderUid = FirebaseAuth.instance.currentUser!.uid;
      return;
    }
    final credential = await FirebaseAuth.instance.signInAnonymously();
    riderUid = credential.user!.uid;
  }

  String riderUiStatus(String firestoreStatus) => switch (firestoreStatus) {
        'accepted' => 'DRIVER_ACCEPTED',
        'arrived' => 'DRIVER_ARRIVED',
        'started' => 'TRIP_STARTED',
        'completed' => 'COMPLETED',
        'cancelled' => 'CANCELLED',
        'expired' => 'NO_DRIVERS_AVAILABLE',
        _ => 'SEARCHING_DRIVER',
      };

  void applyRideData(String id, Map<String, dynamic> data) {
    final pickupData = data['pickup'] as Map<String, dynamic>?;
    final destinationData = data['destination'] as Map<String, dynamic>?;
    final pickupLat = (pickupData?['latitude'] as num?)?.toDouble();
    final pickupLng = (pickupData?['longitude'] as num?)?.toDouble();
    final destinationLat =
        (destinationData?['latitude'] as num?)?.toDouble();
    final destinationLng =
        (destinationData?['longitude'] as num?)?.toDouble();

    setState(() {
      rideId = id;
      status = riderUiStatus((data['status'] ?? 'requested').toString());
      vehicle = (data['vehicle'] ?? vehicle).toString();
      fare = (data['fare'] as num?)?.toInt() ?? fare;
      distanceKm = (data['distanceKm'] as num?)?.toDouble() ?? distanceKm;
      destinationAddress =
          (data['destinationAddress'] ?? destinationAddress).toString();
      if (pickupLat != null && pickupLng != null) {
        pickup = LatLng(pickupLat, pickupLng);
      }
      if (destinationLat != null && destinationLng != null) {
        destination = LatLng(destinationLat, destinationLng);
      }
    });
  }

  Future<void> restoreActiveRide() async {
    try {
      await ensureSignedIn();
      final uid = riderUid;
      if (uid == null) return;

      final snapshot = await rideGoFirestore
          .collection('rideRequests')
          .where('riderId', isEqualTo: uid)
          .get();

      QueryDocumentSnapshot<Map<String, dynamic>>? active;
      for (final doc in snapshot.docs) {
        final rideStatus = (doc.data()['status'] ?? '').toString();
        if (rideStatus == 'requested' ||
            rideStatus == 'accepted' ||
            rideStatus == 'arrived' ||
            rideStatus == 'started') {
          active = doc;
          break;
        }
      }

      if (active == null || !mounted) return;
      applyRideData(active.id, active.data());
      watchRide(active.id);
    } catch (_) {
      // Startup recovery is best-effort; normal booking remains available.
    }
  }

  void scheduleRideExpiryCheck(String id) {
    rideExpiryCheck?.cancel();
    rideExpiryCheck = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted || rideId != id) {
        rideExpiryCheck?.cancel();
        return;
      }
      try {
        final ref = rideGoFirestore.collection('rideRequests').doc(id);
        final snapshot = await ref.get(const GetOptions(source: Source.server));
        final data = snapshot.data();
        if (data == null || data['status'] != 'requested') {
          rideExpiryCheck?.cancel();
          return;
        }
        final created = data['createdAt'];
        if (created is! Timestamp ||
            DateTime.now().difference(created.toDate()) < const Duration(minutes: 5)) {
          return;
        }
        await rideGoFirestore.runTransaction((transaction) async {
          final fresh = await transaction.get(ref);
          final ride = fresh.data();
          final timestamp = ride?['createdAt'];
          if (ride?['status'] != 'requested' || timestamp is! Timestamp ||
              DateTime.now().difference(timestamp.toDate()) < const Duration(minutes: 5)) {
            return;
          }
          transaction.update(ref, {
            'status': 'expired',
            'expiredAt': FieldValue.serverTimestamp(),
          });
        });
      } catch (_) {
        // Backend scheduler remains authoritative if client is offline or denied.
      }
    });
  }

  void watchRide(String id) {
    rideSubscription?.cancel();
    scheduleRideExpiryCheck(id);
    rideSubscription = rideGoFirestore
        .collection('rideRequests')
        .doc(id)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (data == null || !mounted) return;
      final nextStatus = (data['status'] ?? 'requested').toString();
      applyRideData(id, data);

      if (nextStatus == 'completed' || nextStatus == 'cancelled' || nextStatus == 'expired') {
        rideExpiryCheck?.cancel();
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted || rideId != id) return;
          rideSubscription?.cancel();
          rideSubscription = null;
          destinationSearchController.clear();
          final wasExpired = nextStatus == 'expired';
          setState(() {
            rideId = null;
            destination = null;
            destinationAddress = '';
            fare = 0;
            distanceKm = 0;
            drivingMinutes = null;
            roadRoute = [];
            routeLoading = false;
            routeError = null;
            routeGeneration++;
            status = wasExpired ? 'No drivers available. Please try again.' : 'Choose your destination';
            suggestions = [];
            searchError = null;
          });
          map?.animateCamera(CameraUpdate.newLatLngZoom(pickup, 15));
        });
      }
    });
  }

  Future<void> cancelRide() async {
    if (noInternet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No internet connection')),
      );
      return;
    }
    final id = rideId;
    if (id == null || status != 'SEARCHING_DRIVER') return;

    const reasons = [
      'Changed my plans',
      'Booked by mistake',
      'Waiting too long',
      'No longer need the ride',
      'Other reason',
    ];
    String? selectedReason;
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, updateSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Why are you cancelling?', style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 8),
                for (final option in reasons)
                  RadioListTile<String>(
                    title: Text(option),
                    value: option,
                    groupValue: selectedReason,
                    onChanged: (value) => updateSheet(() => selectedReason = value),
                  ),
                FilledButton(
                  onPressed: selectedReason == null ? null : () => Navigator.pop(sheetContext, selectedReason),
                  child: const Text('CONFIRM CANCELLATION'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('KEEP SEARCHING'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || reason == null || rideId != id || status != 'SEARCHING_DRIVER') return;
    try {
      await rideGoFirestore.collection('rideRequests').doc(id).update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancellationReason': reason,
        'cancelledBy': 'rider',
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to cancel ride. A driver may have accepted it.')),
        );
      }
    }
  }

  Future<void> book() async {
    if (noInternet) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No internet connection')),
        );
      }
      return;
    }
    if (destination == null || fare <= 0) return;

    try {
      setState(() => status = 'REQUESTING_RIDE');
      await ensureSignedIn();
      await rideSubscription?.cancel();
      rideExpiryCheck?.cancel();

      final ride = await rideGoFirestore.collection('rideRequests').add({
        'riderId': riderUid,
        'status': 'requested',
        'vehicle': vehicle,
        'fare': fare,
        'distanceKm': double.parse(distanceKm.toStringAsFixed(2)),
        'pickup': {
          'latitude': pickup.latitude,
          'longitude': pickup.longitude,
        },
        'destination': {
          'latitude': destination!.latitude,
          'longitude': destination!.longitude,
        },
        'destinationAddress': destinationAddress,
        'createdAt': FieldValue.serverTimestamp(),
        'driverId': null,
      });

      if (!mounted) return;
      setState(() {
        rideId = ride.id;
        status = 'SEARCHING_DRIVER';
      });

      watchRide(ride.id);
    } catch (_) {
      if (mounted) setState(() => status = 'Unable to request ride');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: pickup, zoom: 14),
              myLocationEnabled: locationReady,
              myLocationButtonEnabled: false,
              onMapCreated: (controller) => map = controller,
              onTap: rideActive
                  ? null
                  : (point) => selectingPickup
                      ? _selectPickup(point)
                      : selectDestination(point),
              markers: {
                Marker(markerId: const MarkerId('pickup'), position: pickup),
                if (destination != null)
                  Marker(
                    markerId: const MarkerId('destination'),
                    position: destination!,
                    infoWindow: InfoWindow(
                      title: 'Destination',
                      snippet: destinationAddress,
                    ),
                  ),
              },
              polylines: {
                if (destination != null)
                  Polyline(
                    polylineId: const PolylineId('ride_preview'),
                    points: roadRoute.isNotEmpty ? roadRoute : [pickup, destination!],
                    color: const Color(0xFF2563EB),
                    width: 4,
                  ),
              },
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Ride history',
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const RiderHistoryScreen()),
                          ),
                          icon: const Icon(Icons.person),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'RideGo',
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
                    const SizedBox(height: 10),
                    if (!rideActive) ...[
                      Material(
                        elevation: 3,
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.my_location, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Pickup: ${pickupAddress.isEmpty ? (locationReady ? 'Current location' : 'Choose pickup location') : pickupAddress}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: selectingPickup ? null : _beginPickupSelection,
                                child: Text(selectingPickup ? 'SELECTING' : 'CHANGE'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (!rideActive)
                    Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white,
                      child: TextField(
                        controller: destinationSearchController,
                        textInputAction: TextInputAction.search,
                        enabled: !rideActive,
                        onSubmitted: (value) {
                          destinationSearchDebounce?.cancel();
                          searchDestinations(value);
                        },
                        onChanged: _onDestinationChanged,
                        decoration: InputDecoration(
                          hintText: 'Search destination',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: searching || selectingPlace
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  tooltip: 'Search',
                                  icon: const Icon(Icons.arrow_forward),
                                  onPressed: () => searchDestinations(
                                    destinationSearchController.text,
                                  ),
                                ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    if (suggestions.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        constraints: const BoxConstraints(maxHeight: 260),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [
                            BoxShadow(
                              blurRadius: 12,
                              color: Colors.black26,
                            ),
                          ],
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: suggestions.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = suggestions[index];
                            return ListTile(
                              leading: const Icon(Icons.location_on_outlined),
                              title: Text(item.label),
                              onTap: () => selectPlace(item),
                            );
                          },
                        ),
                      ),
                    if (searchError != null)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          searchError!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (!locationServiceEnabled && !rideActive)
              Positioned(
                top: MediaQuery.of(context).padding.top + 132,
                left: 16,
                right: 16,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.location_off),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('Location is turned off')),
                        TextButton(
                          onPressed: Geolocator.openLocationSettings,
                          child: const Text('TURN ON'),
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
                            'No internet connection',
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
            if (destination != null || rideActive)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (destination != null && !rideActive) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Choose your ride', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 8),
                      for (final option in const ['Bike', 'Auto', 'Cab'])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Material(
                            color: vehicle == option ? Theme.of(context).colorScheme.primaryContainer : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                setState(() => vehicle = option);
                                recalculateFare();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    Icon(option == 'Bike' ? Icons.two_wheeler : option == 'Auto' ? Icons.electric_rickshaw : Icons.local_taxi),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(option, style: const TextStyle(fontWeight: FontWeight.w600))),
                                    Text('₹${_fareFor(option, distanceKm)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 8),
                                    Icon(vehicle == option ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(status == 'SEARCHING_DRIVER' ? 'Searching for a driver…' : status),
                              if (destinationAddress.isNotEmpty)
                                Text(
                                  destinationAddress,
                                  maxLines: 2,
                                  softWrap: true,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (destination != null && routeLoading)
                                const Text('Calculating driving route…'),
                              if (destination != null && routeError != null)
                                Text(routeError!),
                              if (destination != null && drivingMinutes != null)
                                Text('Approx. $drivingMinutes min driving time'),
                              if (destination != null && distanceKm > 0)
                                Text(
                                  '${distanceKm.toStringAsFixed(1)} km estimated distance',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        Text(
                          fare == 0 ? 'Select destination' : '₹$fare',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: destination == null || rideActive || noInternet || routeLoading || roadRoute.isEmpty || routeError != null ? null : book,
                        child: Text(rideActive ? 'RIDE IN PROGRESS' : routeLoading ? 'CALCULATING ROUTE…' : routeError != null ? 'ROUTE UNAVAILABLE' : 'BOOK RIDE'),
                      ),
                    ),
                    if (status == 'SEARCHING_DRIVER') ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: OutlinedButton(
                          onPressed: noInternet ? null : cancelRide,
                          child: const Text('CANCEL RIDE'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _PlaceSuggestion {
  const _PlaceSuggestion({
    required this.placeId,
    required this.label,
  });

  final String placeId;
  final String label;
}

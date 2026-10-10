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
  int homeTab = 0;
  bool showBookingMap = false;
  bool searchingPickup = false;
  StreamSubscription<List<ConnectivityResult>>? connectivitySubscription;
  StreamSubscription<ServiceStatus>? locationServiceSubscription;
  Timer? destinationSearchDebounce;
  Timer? rideExpiryCheck;
  int destinationSearchGeneration = 0;

  final TextEditingController destinationSearchController =
      TextEditingController();
  final TextEditingController pickupSearchController = TextEditingController();

  List<_PlaceSuggestion> suggestions = [];
  String? riderUid;
  String? rideId;
  int selectedDriverRating = 0;
  int? savedDriverRating;
  String? tripPin;
  bool arrivalBellShown = false;
  bool submittingDriverRating = false;
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
    pickupSearchController.dispose();
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
    if (rideActive) return;
    // Editing a destination invalidates the previous route and fare.
    if (destination != null) {
      routeGeneration++;
      setState(() {
        destination = null;
        destinationAddress = '';
        roadRoute = [];
        drivingMinutes = null;
        routeLoading = false;
        routeError = null;
        distanceKm = 0;
        fare = 0;
        status = 'Choose your destination';
      });
    }
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
      final message = (error.message ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
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
      if (searchingPickup) {
        pickupSearchController.text = suggestion.label;
        setState(() {
          pickup = LatLng(lat, lng);
          pickupAddress = address != null && address.isNotEmpty ? address : suggestion.label;
          searchingPickup = false;
          selectingPlace = false;
          locationReady = false;
          suggestions = [];
          searchError = null;
        });
        if (destination != null) recalculateFare();
        return;
      }
      FocusManager.instance.primaryFocus?.unfocus();
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
      homeTab = 0;
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
      savedDriverRating = (data['riderRating'] as num?)?.toInt();
      status = riderUiStatus((data['status'] ?? 'requested').toString());
      if (data['status'] == 'arrived' && !arrivalBellShown) {
        arrivalBellShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🔔 Driver arrived! Tell the driver your 4-digit PIN.')));
        });
      }
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
      tripPin = await loadPermanentPin();
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

      if (nextStatus == 'completed') {
        rideExpiryCheck?.cancel();
        return; // Keep the completed trip visible until the rider acknowledges it.
      }
      if (nextStatus == 'cancelled' || nextStatus == 'expired') {
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
            showBookingMap = false;
            selectingPickup = false;
            selectingPlace = false;
          });
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
    if (id == null || !['SEARCHING_DRIVER', 'DRIVER_ACCEPTED', 'DRIVER_ARRIVED'].contains(status)) return;

    final afterAcceptance = status == 'DRIVER_ACCEPTED' || status == 'DRIVER_ARRIVED';
    final driverArrived = status == 'DRIVER_ARRIVED';
    final reasons = afterAcceptance
        ? const ['Wrong pickup location']
        : const [
            'Changed my plans',
            'Booked by mistake',
            'Waiting too long',
            'Wrong pickup location',
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
                if (afterAcceptance)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      driverArrived
                          ? 'Caution: Your driver has arrived. RideGo cancellation policy is the higher of ₹10 or the fare for the driver’s verified distance travelled towards pickup. The amount is not yet available in this version; no penalty will be charged automatically.'
                          : 'Caution: Your driver has accepted this ride. Cancelling while the driver travels to pickup may incur a penalty: the higher of ₹10 or the fare for verified distance travelled towards pickup. The amount is not yet available in this version; no penalty will be charged automatically.',
                    ),
                  ),
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
                  child: const Text('KEEP RIDE'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || reason == null || rideId != id || !['SEARCHING_DRIVER', 'DRIVER_ACCEPTED', 'DRIVER_ARRIVED'].contains(status)) return;
    try {
      await rideGoFirestore.runTransaction((transaction) async {
        final ref = rideGoFirestore.collection('rideRequests').doc(id);
        final snapshot = await transaction.get(ref);
        final currentStatus = snapshot.data()?['status'];
        if (!snapshot.exists ||
            !['requested', 'accepted', 'arrived'].contains(currentStatus) ||
            (currentStatus != 'requested' && reason != 'Wrong pickup location')) {
          throw StateError('Cancellation is no longer available for this reason');
        }
        transaction.update(ref, {
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancellationReason': reason,
          'cancelledBy': 'rider',
        });
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to cancel ride. Check Firebase rules or ride status.')),
        );
      }
    }
  }

  Future<String> loadPermanentPin() async {
    await ensureSignedIn();
    final uid = riderUid!;
    final ref = rideGoFirestore.collection('riderTripPins').doc(uid);
    return rideGoFirestore.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      if (existing.exists) {
        final value = existing.data()?['pin']?.toString();
        if (value != null && value.length == 4) return value;
        throw StateError('Invalid saved PIN');
      }
      final pin = math.Random.secure().nextInt(10000).toString().padLeft(4, '0');
      transaction.set(ref, {'pin': pin, 'riderId': uid, 'createdAt': FieldValue.serverTimestamp()});
      return pin;
    });
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
      setState(() { status = 'REQUESTING_RIDE'; showBookingMap = true; });
      await ensureSignedIn();
      await rideSubscription?.cancel();
      rideExpiryCheck?.cancel();

      final pin = await loadPermanentPin();
      final ride = rideGoFirestore.collection('rideRequests').doc();
      final batch = rideGoFirestore.batch();
      batch.set(ride, {
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
        'pinRequired': true,
      });
      await batch.commit();

      if (!mounted) return;
      setState(() {
        rideId = ride.id;
        tripPin = pin;
        arrivalBellShown = false;
        status = 'SEARCHING_DRIVER';
      });

      watchRide(ride.id);
    } on FirebaseException catch (error) {
      debugPrint('Ride booking Firebase error: ${error.code}: ${error.message}');
      if (mounted) {
        setState(() {
          status = 'Unable to request ride';
          showBookingMap = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Booking failed (${error.code}): ${error.message ?? 'Please try again'}'),
        ));
      }
    } catch (error) {
      debugPrint('Ride booking error: $error');
      if (mounted) {
        setState(() {
          status = 'Unable to request ride';
          showBookingMap = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to request ride. Please try again.')),
        );
      }
    }
  }

  String get shortPickupName {
    final plusCode = RegExp(r'^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4}$', caseSensitive: false);
    final parts = pickupAddress.split(',').map((part) => part.trim()).where((part) => part.isNotEmpty);
    for (final part in parts) {
      final cleaned = part.replaceFirst(RegExp(r'^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4}\s+', caseSensitive: false), '').trim();
      if (cleaned.isNotEmpty && !plusCode.hasMatch(cleaned) &&
          !RegExp(r'^\d{5,6}$').hasMatch(cleaned) &&
          cleaned.toLowerCase() != 'india') {
        return cleaned;
      }
    }
    return 'Choose pickup location';
  }

  Future<void> _openPickupSearch() async {
    if (rideActive) return;
    final chosen = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const _PickupSearchPage()),
    );
    if (!mounted || chosen == null || rideActive) return;
    setState(() {
      pickup = LatLng(chosen['latitude'] as double, chosen['longitude'] as double);
      pickupAddress = chosen['address'] as String;
      locationReady = false;
      selectingPickup = false;
      status = 'Pickup selected';
    });
    if (destination != null) recalculateFare();
  }

  Widget _initialHome() => Scaffold(
    appBar: AppBar(title: const Text('RideGo')),
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.all(16),
      child: homeTab == 0 ? Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.my_location),
            title: Text(shortPickupName, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openPickupSearch,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: destinationSearchController,
            onChanged: _onDestinationChanged,
            onSubmitted: searchDestinations,
            decoration: const InputDecoration(
              hintText: 'Search destination',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          if (searching) const LinearProgressIndicator(),
          if (searchError != null) Text(searchError!),
          for (final item in suggestions.take(5))
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(item.label, maxLines: 2),
              onTap: () => selectPlace(item),
            ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/images/ridego_promo.jpg',
              height: 260,
              width: double.infinity,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                height: 260,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                alignment: Alignment.center,
                child: const Text('RideGo • Bike  |  Auto  |  Cab'),
              ),
            ),
          ),
        ],
      ) : homeTab == 1 ? ListView(children: [
        for (final service in const ['Bike', 'Auto', 'Cab'])
          ListTile(
            leading: Icon(service == 'Bike' ? Icons.two_wheeler : service == 'Auto' ? Icons.electric_rickshaw : Icons.local_taxi),
            title: Text('Book a ${service.toLowerCase()}'),
            onTap: () => setState(() { vehicle = service; homeTab = 0; }),
          ),
        const ListTile(leading: Icon(Icons.people_outline), title: Text('Book for others'), subtitle: Text('Coming soon')),
      ]) : ListView(children: [
        ListTile(leading: const Icon(Icons.person_outline), title: const Text('My profile'),
          subtitle: Text(FirebaseAuth.instance.currentUser?.email ?? 'Account details')),
        ListTile(leading: const Icon(Icons.history), title: const Text('Ride history'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RiderHistoryScreen()))),
        const ListTile(leading: Icon(Icons.payments_outlined), title: Text('Payments'), subtitle: Text('Coming soon')),
        const ListTile(leading: Icon(Icons.card_giftcard), title: Text('Refer and earn'), subtitle: Text('Coming soon')),
        ListTile(leading: const Icon(Icons.logout), title: const Text('Logout'),
          onTap: () => FirebaseAuth.instance.signOut()),
      ]),
    )),
    bottomNavigationBar: NavigationBar(
      selectedIndex: homeTab,
      onDestinationSelected: (index) => setState(() => homeTab = index),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.grid_view_outlined), label: 'Menu'),
        NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
      ],
    ),
  );

  Widget _preBookingScreen() => Scaffold(
    appBar: AppBar(title: const Text('RideGo')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  ListTile(
                    leading: const Icon(Icons.my_location),
                    title: Text(shortPickupName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openPickupSearch,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: destinationSearchController,
                    onChanged: _onDestinationChanged,
                    onSubmitted: searchDestinations,
                    decoration: const InputDecoration(
                      labelText: 'Destination (tap to change)',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (searching) const LinearProgressIndicator(),
                  if (searchError != null) Text(searchError!),
                  for (final item in suggestions.take(5))
                    ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(item.label, maxLines: 2),
                      onTap: () => selectPlace(item),
                    ),
                  const SizedBox(height: 16),
                  const Text('Choose your ride', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  for (final service in const ['Bike', 'Auto', 'Cab'])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Material(
                        color: vehicle == service
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() {
                            vehicle = service;
                            recalculateFare();
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Icon(service == 'Bike'
                                    ? Icons.two_wheeler
                                    : service == 'Auto'
                                        ? Icons.local_taxi
                                        : Icons.directions_car),
                                const SizedBox(width: 12),
                                Expanded(child: Text(service, style: const TextStyle(fontSize: 18))),
                                Text('₹${_fareForService(service)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 12),
                                Icon(vehicle == service ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (routeLoading) const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  Text('${distanceKm.toStringAsFixed(1)} km • ${drivingMinutes == null ? "Calculating ETA" : "${drivingMinutes!} min"}'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: destination == null || fare <= 0 || noInternet ? null : () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  book();
                },
                child: const Text('BOOK RIDE'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  int _fareForService(String service) {
    final km = distanceKm;
    final base = service == 'Bike' ? 30 : service == 'Auto' ? 40 : 70;
    final perKm = service == 'Bike' ? 12 : service == 'Auto' ? 16 : 22;
    final minimum = service == 'Bike' ? 40 : service == 'Auto' ? 60 : 100;
    return math.max(minimum, (base + km * perKm).ceil());
  }

  void _dismissCompletedTrip() {
    rideSubscription?.cancel();
    rideSubscription = null;
    rideExpiryCheck?.cancel();
    destinationSearchController.clear();
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
      status = 'Choose your destination';
      suggestions = [];
      searchError = null;
      showBookingMap = false;
    });
  }

  Future<void> _submitDriverRating() async {
    final id = rideId;
    if (id == null || selectedDriverRating == 0 ||
        savedDriverRating != null || submittingDriverRating) return;
    setState(() => submittingDriverRating = true);
    try {
      await rideGoFirestore.collection('rideRequests').doc(id).update({
        'riderRating': selectedDriverRating,
        'ratedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() => savedDriverRating = selectedDriverRating);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thank you for rating your driver!')),
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.code == 'permission-denied'
            ? 'Rating could not be saved. Please check Firestore rules.'
            : 'Unable to save rating. Please try again.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save rating. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => submittingDriverRating = false);
    }
  }

  String get friendlyRideStatus => switch (status) {
    'DRIVER_ACCEPTED' => 'Driver accepted your ride',
    'DRIVER_ARRIVED' => 'Driver has arrived',
    'TRIP_STARTED' => 'Trip in progress',
    'COMPLETED' => 'Trip completed',
    'SEARCHING_DRIVER' => 'Searching for a driver…',
    _ => status,
  };

  Widget _completedTripScreen() => Scaffold(
    appBar: AppBar(title: const Text('RideGo')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            const Icon(Icons.check_circle, size: 80, color: Colors.green),
            const SizedBox(height: 20),
            Text('Trip Completed',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            const Text('Your ride has been completed successfully.',
                textAlign: TextAlign.center),
            const SizedBox(height: 32),
            if (destinationAddress.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: const Text('Destination'),
                subtitle: Text(destinationAddress),
              ),
            ListTile(
              leading: const Icon(Icons.directions_car_outlined),
              title: Text(vehicle),
              subtitle: Text('${distanceKm.toStringAsFixed(1)} km'),
            ),
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Trip fare'),
              trailing: Text('₹$fare',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            const SizedBox(height: 16),
            Text(savedDriverRating == null ? 'Rate your driver' : 'Your driver rating',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final rating = savedDriverRating ?? selectedDriverRating;
                return IconButton(
                  tooltip: '${index + 1} star${index == 0 ? '' : 's'}',
                  onPressed: savedDriverRating != null || submittingDriverRating
                      ? null
                      : () => setState(() => selectedDriverRating = index + 1),
                  icon: Icon(index < rating ? Icons.star : Icons.star_border,
                      color: Colors.amber, size: 34),
                );
              }),
            ),
            if (savedDriverRating == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.tonal(
                  onPressed: selectedDriverRating == 0 || submittingDriverRating
                      ? null : _submitDriverRating,
                  child: Text(submittingDriverRating ? 'SAVING...' : 'SUBMIT RATING'),
                ),
              )
            else
              const Text('Thank you for your feedback!',
                  textAlign: TextAlign.center),
            const Spacer(),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _dismissCompletedTrip,
                child: const Text('BACK TO HOME'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (rideActive && status == 'COMPLETED') {
      return _completedTripScreen();
    }
    if (!rideActive && !showBookingMap) {
      return destination == null ? _initialHome() : _preBookingScreen();
    }
    return Scaffold(
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: pickup, zoom: 14),
              myLocationEnabled: locationReady,
              myLocationButtonEnabled: false,
              onMapCreated: (controller) {
                map = controller;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || map != controller) return;
                  final points = roadRoute.isNotEmpty
                      ? roadRoute
                      : destination == null ? <LatLng>[] : <LatLng>[pickup, destination!];
                  _fitRouteOnMap(points);
                });
              },
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
                    points: roadRoute,
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
                        if (!rideActive) IconButton(
                          tooltip: 'Back to home',
                          onPressed: () => setState(() {
                            showBookingMap = false;
                            selectingPickup = false;
                            destination = null;
                            roadRoute = [];
                            fare = 0;
                            distanceKm = 0;
                            routeGeneration++;
                            destinationSearchController.clear();
                            suggestions = [];
                          }),
                          icon: const Icon(Icons.arrow_back),
                        ),
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
                                onPressed: rideActive ? null : _openPickupSearch,
                                child: const Text('CHANGE'),
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
                              if (status == 'DRIVER_ARRIVED' && tripPin != null)
                                Card(child: ListTile(leading: const Icon(Icons.notifications_active, color: Colors.orange),
                                  title: const Text('Driver arrived!'),
                                  subtitle: SelectableText('Tell your driver PIN: $tripPin'),
                                )),
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
                    if (['SEARCHING_DRIVER', 'DRIVER_ACCEPTED', 'DRIVER_ARRIVED'].contains(status)) ...[
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
}

class _PickupSearchPage extends StatefulWidget {
  const _PickupSearchPage();

  @override
  State<_PickupSearchPage> createState() => _PickupSearchPageState();
}

class _PickupSearchPageState extends State<_PickupSearchPage> {
  final controller = TextEditingController();
  Timer? debounce;
  int generation = 0;
  bool loading = false;
  String? error;
  List<_PlaceSuggestion> results = [];

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  void changed(String value) {
    debounce?.cancel();
    ++generation;
    if (value.trim().length < 2) {
      setState(() { results = []; error = null; loading = false; });
      return;
    }
    debounce = Timer(const Duration(milliseconds: 350), () => search(value));
  }

  Future<void> search(String value) async {
    final query = value.trim();
    if (query.length < 2) return;
    final request = ++generation;
    setState(() { loading = true; error = null; });
    try {
      final raw = await riderLocationChannel.invokeMethod<List<dynamic>>(
        'searchPlaces', {'query': query});
      if (!mounted || request != generation) return;
      setState(() {
        results = (raw ?? []).map((entry) {
          final data = Map<String, dynamic>.from(entry as Map);
          final id = data['placeId']?.toString();
          final label = data['label']?.toString();
          if (id == null || label == null || label.isEmpty) return null;
          return _PlaceSuggestion(placeId: id, label: label);
        }).whereType<_PlaceSuggestion>().toList();
        loading = false;
        error = results.isEmpty ? 'No pickup locations found' : null;
      });
    } catch (_) {
      if (mounted && request == generation) {
        setState(() { loading = false; error = 'Unable to search pickup locations'; });
      }
    }
  }

  Future<void> choose(_PlaceSuggestion item) async {
    setState(() { loading = true; error = null; });
    try {
      final raw = await riderLocationChannel.invokeMethod<Map<dynamic, dynamic>>(
        'placeDetails', {'placeId': item.placeId});
      final data = raw == null ? null : Map<String, dynamic>.from(raw);
      final lat = (data?['latitude'] as num?)?.toDouble();
      final lng = (data?['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) throw const FormatException();
      if (!mounted) return;
      Navigator.pop(context, <String, dynamic>{
        'latitude': lat,
        'longitude': lng,
        'address': data?['address']?.toString() ?? item.label,
      });
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'Unable to select pickup location'; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose pickup location')),
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        TextField(
          controller: controller,
          autofocus: true,
          onChanged: changed,
          onSubmitted: search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search pickup location',
            border: OutlineInputBorder(),
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Padding(
          padding: const EdgeInsets.all(12),
          child: Text(error!),
        ),
        Expanded(child: ListView.builder(
          itemCount: results.length,
          itemBuilder: (_, i) => ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(results[i].label),
            onTap: loading ? null : () => choose(results[i]),
          ),
        )),
      ]),
    )),
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

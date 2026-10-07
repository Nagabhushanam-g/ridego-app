import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth.dart';
import 'history.dart';
import 'notification_service.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

const String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
const String androidCertSha1 = String.fromEnvironment('GOOGLE_MAPS_ANDROID_CERT');
const String rideGoFirestoreDatabaseId = 'firestore-db-2';

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
  String vehicle = 'Bike';
  String status = 'Choose your destination';
  int fare = 0;
  double distanceKm = 0;
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

      map?.animateCamera(CameraUpdate.newLatLngZoom(current, 15));
    } catch (_) {
      if (mounted && !rideActive) {
        setState(() => status = 'Unable to get current location');
      }
    }
  }

  Future<void> searchDestinations(String value) async {
    if (noInternet) {
      if (mounted) setState(() => searchError = 'No internet connection');
      return;
    }
    final query = value.trim();
    if (query.length < 2) {
      if (mounted) {
        setState(() {
          suggestions = [];
          searchError = null;
        });
      }
      return;
    }

    if (googleMapsApiKey.isEmpty) {
      if (mounted) {
        setState(() {
          suggestions = [];
          searchError = 'Google Maps API key is not configured';
        });
      }
      return;
    }

    setState(() {
      searching = true;
      searchError = null;
    });

    try {
      final uri = Uri.parse(
        'https://places.googleapis.com/v1/places:autocomplete',
      );

      final body = {
        'input': query,
        'languageCode': 'en',
        'regionCode': 'IN',
        'locationBias': {
          'circle': {
            'center': {
              'latitude': pickup.latitude,
              'longitude': pickup.longitude,
            },
            'radius': 50000.0,
          },
        },
      };

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': googleMapsApiKey,
          if (androidCertSha1.isNotEmpty)
            'X-Android-Package': 'com.example.ridego_rider',
          if (androidCertSha1.isNotEmpty)
            'X-Android-Cert': androidCertSha1,
        },
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        throw Exception('Places search failed (\${response.statusCode})');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawSuggestions = (data['suggestions'] as List<dynamic>? ?? []);

      final parsed = rawSuggestions
          .map((item) {
            final prediction =
                item['placePrediction'] as Map<String, dynamic>?;
            if (prediction == null) return null;

            final placeId = prediction['placeId'] as String?;
            final text = prediction['text'] as Map<String, dynamic>?;
            final label = text?['text'] as String?;

            if (placeId == null || label == null || label.isEmpty) {
              return null;
            }

            return _PlaceSuggestion(placeId: placeId, label: label);
          })
          .whereType<_PlaceSuggestion>()
          .toList();

      if (!mounted) return;
      setState(() {
        suggestions = parsed;
        searching = false;
        searchError = parsed.isEmpty ? 'No destinations found' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        searching = false;
        suggestions = [];
        searchError = 'Unable to search destinations';
      });
    }
  }

  Future<void> selectPlace(_PlaceSuggestion suggestion) async {
    if (noInternet) {
      if (mounted) setState(() => searchError = 'No internet connection');
      return;
    }
    if (googleMapsApiKey.isEmpty) return;

    setState(() {
      selectingPlace = true;
      searchError = null;
      suggestions = [];
    });

    try {
      final encodedPlaceId = Uri.encodeComponent(suggestion.placeId);
      final uri = Uri.parse(
        'https://places.googleapis.com/v1/places/$encodedPlaceId',
      );

      final response = await http.get(
        uri,
        headers: {
          'X-Goog-Api-Key': googleMapsApiKey,
          'X-Goog-FieldMask': 'location,formattedAddress,displayName',
          if (androidCertSha1.isNotEmpty)
            'X-Android-Package': 'com.example.ridego_rider',
          if (androidCertSha1.isNotEmpty)
            'X-Android-Cert': androidCertSha1,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Place details failed (\${response.statusCode})');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final location = data['location'] as Map<String, dynamic>?;
      final lat = (location?['latitude'] as num?)?.toDouble();
      final lng = (location?['longitude'] as num?)?.toDouble();

      if (lat == null || lng == null) {
        throw Exception('Destination coordinates were not returned');
      }

      final address =
          data['formattedAddress'] as String? ?? suggestion.label;

      destinationSearchController.text = suggestion.label;
      selectDestination(
        LatLng(lat, lng),
        address: address,
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

    if (moveCamera) {
      map?.animateCamera(
        CameraUpdate.newLatLngZoom(point, 15),
      );
    }
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

  void watchRide(String id) {
    rideSubscription?.cancel();
    rideSubscription = rideGoFirestore
        .collection('rideRequests')
        .doc(id)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (data == null || !mounted) return;
      final nextStatus = (data['status'] ?? 'requested').toString();
      applyRideData(id, data);

      if (nextStatus == 'completed' || nextStatus == 'cancelled') {
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted || rideId != id) return;
          rideSubscription?.cancel();
          rideSubscription = null;
          destinationSearchController.clear();
          setState(() {
            rideId = null;
            destination = null;
            destinationAddress = '';
            fare = 0;
            distanceKm = 0;
            status = 'Choose your destination';
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No internet connection')),
        );
      }
      return;
    }
    final id = rideId;
    if (id == null || status != 'SEARCHING_DRIVER') return;

    try {
      await rideGoFirestore.collection('rideRequests').doc(id).update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to cancel ride. A driver may have accepted it.'),
          ),
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
                    points: [pickup, destination!],
                    width: 5,
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
                    Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white,
                      child: TextField(
                        controller: destinationSearchController,
                        textInputAction: TextInputAction.search,
                        enabled: !rideActive,
                        onSubmitted: searchDestinations,
                        onChanged: (value) {
                          if (value.trim().length < 2) {
                            setState(() {
                              suggestions = [];
                              searchError = null;
                            });
                          }
                        },
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
                    if (!rideActive) ...[
                      Row(
                        children: [
                          const Icon(Icons.my_location, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Pickup location',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton(
                            onPressed: selectingPickup ? null : _beginPickupSelection,
                            child: Text(selectingPickup ? 'SELECTING' : 'CHANGE'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Choose your ride',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'Bike',
                          label: Text('Bike'),
                          icon: Icon(Icons.two_wheeler),
                        ),
                        ButtonSegment(
                          value: 'Auto',
                          label: Text('Auto'),
                          icon: Icon(Icons.electric_rickshaw),
                        ),
                        ButtonSegment(
                          value: 'Cab',
                          label: Text('Cab'),
                          icon: Icon(Icons.local_taxi),
                        ),
                      ],
                      selected: {vehicle},
                      onSelectionChanged: rideActive
                          ? null
                          : (selection) {
                              setState(() => vehicle = selection.first);
                              recalculateFare();
                            },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(status),
                              if (destinationAddress.isNotEmpty)
                                Text(
                                  destinationAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (distanceKm > 0)
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
                        onPressed: destination == null || rideActive || noInternet ? null : book,
                        child: Text(rideActive ? 'RIDE IN PROGRESS' : 'BOOK RIDE'),
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

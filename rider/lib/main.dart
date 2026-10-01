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
  String? searchError;

  final TextEditingController destinationSearchController =
      TextEditingController();

  List<_PlaceSuggestion> suggestions = [];
  String? riderUid;
  String? rideId;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? rideSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await RideGoNotificationService.initialize(context, role: 'rider');
      await locate();
    });
  }

  @override
  void dispose() {
    rideSubscription?.cancel();
    destinationSearchController.dispose();
    super.dispose();
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
        pickup = current;
        locationReady = true;
        status = 'Choose your destination';
      });

      map?.animateCamera(CameraUpdate.newLatLngZoom(current, 15));
    } catch (_) {
      if (mounted) setState(() => status = 'Unable to get current location');
    }
  }

  Future<void> searchDestinations(String value) async {
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

  Future<void> book() async {
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

      rideSubscription = rideGoFirestore
          .collection('rideRequests')
          .doc(ride.id)
          .snapshots()
          .listen((snapshot) {
        final data = snapshot.data();
        if (data == null || !mounted) return;
        final nextStatus = data['status'] as String? ?? 'requested';
        setState(() {
          status = switch (nextStatus) {
            'accepted' => 'DRIVER_ACCEPTED',
            'arrived' => 'DRIVER_ARRIVED',
            'started' => 'TRIP_STARTED',
            'completed' => 'COMPLETED',
            'cancelled' => 'CANCELLED',
            _ => 'SEARCHING_DRIVER',
          };
        });
      });
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
              onTap: (point) => selectDestination(point),
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
                      onSelectionChanged: (selection) {
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
                        onPressed: destination == null ? null : book,
                        child: const Text('BOOK RIDE'),
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

class _PlaceSuggestion {
  const _PlaceSuggestion({
    required this.placeId,
    required this.label,
  });

  final String placeId;
  final String label;
}

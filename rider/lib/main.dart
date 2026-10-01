import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';

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
        home: const RiderHome(),
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
  String vehicle = 'Bike';
  String status = 'Choose your destination';
  int fare = 0;
  double distanceKm = 0;
  bool locationReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => locate());
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

  void selectDestination(LatLng point) {
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

    final calculatedFare =
        (baseFare + (km * perKm)).ceil().clamp(baseFare, 100000);

    setState(() {
      destination = point;
      distanceKm = km;
      fare = calculatedFare;
      status = 'Destination selected';
    });
  }

  void recalculateFare() {
    if (destination != null) {
      selectDestination(destination!);
    }
  }

  void book() {
    if (destination == null) return;
    setState(() => status = 'SEARCHING_DRIVER');
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => status = 'DRIVER_ASSIGNED');
    });
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
              onTap: selectDestination,
              markers: {
                Marker(markerId: const MarkerId('pickup'), position: pickup),
                if (destination != null)
                  Marker(
                    markerId: const MarkerId('destination'),
                    position: destination!,
                    infoWindow: const InfoWindow(title: 'Destination'),
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
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const CircleAvatar(child: Icon(Icons.person)),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'RideGo',
                        style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
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
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Choose your ride',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                              if (distanceKm > 0)
                                Text(
                                  distanceKm.toStringAsFixed(1) + ' km estimated distance',
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

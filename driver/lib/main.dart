import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

void main() => runApp(const RideGoDriver());

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
        home: const DriverHome(),
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
  int? rideId;

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
        location = current;
        locationReady = true;
        if (!online) status = 'Offline';
      });
      map?.animateCamera(CameraUpdate.newLatLngZoom(current, 15));
    } catch (_) {
      if (mounted) setState(() => status = 'Unable to get current location');
    }
  }

  void toggle() {
    setState(() {
      online = !online;
      rideId = null;
      status = online ? 'Online — waiting for rides' : 'Offline';
    });
  }

  void accept() {
    setState(() {
      rideId = 1001;
      status = 'DRIVER_ACCEPTED';
    });
  }

  void next() {
    if (status == 'DRIVER_ACCEPTED') {
      setState(() => status = 'DRIVER_ARRIVED');
    } else if (status == 'DRIVER_ARRIVED') {
      setState(() => status = 'TRIP_STARTED');
    } else if (status == 'TRIP_STARTED') {
      setState(() => status = 'COMPLETED');
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
                    const CircleAvatar(child: Icon(Icons.person)),
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
                    if (online && rideId == null)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.notifications_active),
                          title: const Text('New ride request'),
                          subtitle: const Text(
                            'Pickup nearby • Estimated fare ₹120',
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

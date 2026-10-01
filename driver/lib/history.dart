import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

const String _dbId = 'firestore-db-2';

FirebaseFirestore get _db => FirebaseFirestore.instanceFor(
  app: Firebase.app(),
  databaseId: _dbId,
);

class DriverHistoryScreen extends StatelessWidget {
  const DriverHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Please sign in again.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Trip history')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db.collection('rideRequests').where('driverId', isEqualTo: uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load trip history.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final trips = [...snapshot.data!.docs];
          trips.sort((a, b) {
            final at = (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            final bt = (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            return bt.compareTo(at);
          });

          if (trips.isEmpty) {
            return const Center(
              child: Text('No completed trips yet', style: TextStyle(fontSize: 18)),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: trips.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final data = trips[index].data();
              final status = (data['status'] ?? 'unknown').toString().toUpperCase();
              final vehicle = (data['vehicle'] ?? 'Ride').toString();
              final fare = data['fare'] ?? 0;
              final distance = data['distanceKm'] ?? 0;
              final destination = (data['destinationAddress'] ?? 'Destination not recorded').toString();

              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(
                    vehicle == 'Bike' ? Icons.two_wheeler :
                    vehicle == 'Auto' ? Icons.electric_rickshaw : Icons.local_taxi,
                  )),
                  title: Text('$vehicle • ₹$fare'),
                  subtitle: Text('$destination\n$distance km'),
                  isThreeLine: true,
                  trailing: Text(status, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

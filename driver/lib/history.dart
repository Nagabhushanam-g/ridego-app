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
        stream: _db
            .collection('rideRequests')
            .where('driverId', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load trip history.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final trips = snapshot.data!.docs
              .where((doc) => doc.data()['status'] == 'completed')
              .toList();

          trips.sort((a, b) {
            final at =
                (a.data()['completedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                    (a.data()['createdAt'] as Timestamp?)
                        ?.millisecondsSinceEpoch ??
                    0;
            final bt =
                (b.data()['completedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                    (b.data()['createdAt'] as Timestamp?)
                        ?.millisecondsSinceEpoch ??
                    0;
            return bt.compareTo(at);
          });

          final totalEarnings = trips.fold<int>(
            0,
            (sum, doc) => sum + ((doc.data()['fare'] as num?)?.round() ?? 0),
          );

          if (trips.isEmpty) {
            return const Center(
              child: Text(
                'No completed trips yet',
                style: TextStyle(fontSize: 18),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: trips.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          child: Icon(Icons.account_balance_wallet),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Completed trips',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${trips.length}',
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Total fares',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '₹$totalEarnings',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }

              final data = trips[index - 1].data();
              final vehicle = (data['vehicle'] ?? 'Ride').toString();
              final fare = data['fare'] ?? 0;
              final distance = data['distanceKm'] ?? 0;
              final destination =
                  (data['destinationAddress'] ?? 'Destination not recorded')
                      .toString();
              final rating = (data['riderRating'] as num?)?.toInt();

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      vehicle == 'Bike'
                          ? Icons.two_wheeler
                          : vehicle == 'Auto'
                              ? Icons.electric_rickshaw
                              : Icons.local_taxi,
                    ),
                  ),
                  title: Text('$vehicle • ₹$fare'),
                  subtitle: Text(
                    rating == null
                        ? '$destination\n$distance km'
                        : '$destination\n$distance km\nRider rating: $rating/5',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.check_circle_outline),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

const String _dbId = 'firestore-db-2';

FirebaseFirestore get _db => FirebaseFirestore.instanceFor(
  app: Firebase.app(),
  databaseId: _dbId,
);

class RiderHistoryScreen extends StatelessWidget {
  const RiderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Please sign in again.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ride history')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db.collection('rideRequests').where('riderId', isEqualTo: uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load ride history.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final rides = [...snapshot.data!.docs];
          rides.sort((a, b) {
            final at = (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            final bt = (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            return bt.compareTo(at);
          });

          if (rides.isEmpty) {
            return const Center(
              child: Text('No rides yet', style: TextStyle(fontSize: 18)),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rides.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = rides[index];
              final data = doc.data();
              final status = (data['status'] ?? 'unknown').toString().toUpperCase();
              final vehicle = (data['vehicle'] ?? 'Ride').toString();
              final fare = data['fare'] ?? 0;
              final distance = data['distanceKm'] ?? 0;
              final destination = (data['destinationAddress'] ?? 'Destination not recorded').toString();
              final rating = (data['riderRating'] as num?)?.toInt();

              return Card(
                child: ListTile(
                  onTap: status == 'COMPLETED'
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RideReceiptScreen(
                                rideId: doc.id,
                                ride: data,
                              ),
                            ),
                          )
                      : null,
                  leading: CircleAvatar(child: Icon(
                    vehicle == 'Bike' ? Icons.two_wheeler :
                    vehicle == 'Auto' ? Icons.electric_rickshaw : Icons.local_taxi,
                  )),
                  title: Text('$vehicle • ₹$fare'),
                  subtitle: Text(
                    rating == null
                        ? '$destination\n$distance km'
                        : '$destination\n$distance km\nRating: $rating/5',
                  ),
                  isThreeLine: rating == null,
                  trailing: status == 'COMPLETED'
                      ? const Icon(Icons.receipt_long)
                      : Text(status, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class RideReceiptScreen extends StatefulWidget {
  const RideReceiptScreen({
    super.key,
    required this.rideId,
    required this.ride,
  });

  final String rideId;
  final Map<String, dynamic> ride;

  @override
  State<RideReceiptScreen> createState() => _RideReceiptScreenState();
}

class _RideReceiptScreenState extends State<RideReceiptScreen> {
  bool saving = false;
  String? error;

  Future<void> rate(int value) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });

    try {
      await _db.collection('rideRequests').doc(widget.rideId).update({
        'riderRating': value,
        'ratedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks for rating your ride.')),
        );
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to save rating.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String _dateText(dynamic value) {
    if (value is! Timestamp) return 'Not recorded';
    final date = value.toDate().toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('rideRequests').doc(widget.rideId).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? widget.ride;
        final vehicle = (data['vehicle'] ?? 'Ride').toString();
        final fare = data['fare'] ?? 0;
        final distance = data['distanceKm'] ?? 0;
        final destination =
            (data['destinationAddress'] ?? 'Destination not recorded').toString();
        final rating = (data['riderRating'] as num?)?.toInt();

        return Scaffold(
          appBar: AppBar(title: const Text('Ride receipt')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(Icons.check_circle, size: 64),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'Trip completed',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      _ReceiptRow(label: 'Ride ID', value: widget.rideId),
                      _ReceiptRow(label: 'Vehicle', value: vehicle),
                      _ReceiptRow(label: 'Destination', value: destination),
                      _ReceiptRow(label: 'Distance', value: '$distance km'),
                      _ReceiptRow(label: 'Fare', value: '₹$fare'),
                      _ReceiptRow(label: 'Payment', value: 'Cash'),
                      _ReceiptRow(
                        label: 'Completed',
                        value: _dateText(data['completedAt']),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                rating == null ? 'Rate your ride' : 'Your rating',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final value = index + 1;
                  return IconButton(
                    tooltip: '$value star',
                    onPressed: saving ? null : () => rate(value),
                    iconSize: 38,
                    icon: Icon(
                      rating != null && value <= rating
                          ? Icons.star
                          : Icons.star_border,
                    ),
                  );
                }),
              ),
              if (saving)
                const Center(child: CircularProgressIndicator()),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

FirebaseFirestore get _db => FirebaseFirestore.instanceFor(
  app: Firebase.app(),
  databaseId: 'firestore-db-2',
);

class DriverHistoryScreen extends StatefulWidget {
  const DriverHistoryScreen({super.key});

  @override
  State<DriverHistoryScreen> createState() => _DriverHistoryScreenState();
}

class _DriverHistoryScreenState extends State<DriverHistoryScreen> {
  late DateTime _from;
  late DateTime _to;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month);
    _to = DateTime(now.year, now.month + 1, 0);
  }

  DateTime? _tripDate(Map<String, dynamic> data) {
    final completed = data['completedAt'];
    if (completed is Timestamp) return completed.toDate();
    final created = data['createdAt'];
    if (created is Timestamp) return created.toDate();
    return null;
  }

  bool _inRange(Map<String, dynamic> data) {
    final date = _tripDate(data)?.toLocal();
    if (date == null) return false;
    final start = DateTime(_from.year, _from.month, _from.day);
    final endExclusive = DateTime(_to.year, _to.month, _to.day + 1);
    return !date.isBefore(start) && date.isBefore(endExclusive);
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  Future<void> _chooseRange() async {
    final range = await showDateRangePicker(
      context: context,
      entryMode: DatePickerEntryMode.calendarOnly,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to.isAfter(DateTime.now()) ? DateTime.now() : _to),
      helpText: 'Choose trip history dates',
    );
    if (range != null && mounted) {
      setState(() {
        _from = DateTime(range.start.year, range.start.month, range.start.day);
        _to = DateTime(range.end.year, range.end.month, range.end.day);
      });
    }
  }

  void _currentMonth() {
    final now = DateTime.now();
    setState(() {
      _from = DateTime(now.year, now.month);
      _to = DateTime(now.year, now.month + 1, 0);
    });
  }

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

          final completed = snapshot.data!.docs
              .where((doc) => (doc.data()['status'] ?? '').toString().toLowerCase() == 'completed')
              .toList();
          final missingDate = completed.where((doc) => _tripDate(doc.data()) == null).length;
          final trips = completed.where((doc) => _inRange(doc.data())).toList();
          trips.sort((a, b) => _tripDate(b.data())!.compareTo(_tripDate(a.data())!));

          final totalFares = trips.fold<int>(
            0, (sum, doc) => sum + ((doc.data()['fare'] as num?)?.round() ?? 0),
          );

          final cashCollected = trips
              .where((doc) => doc.data()['paymentMethod'] == 'cash'
                  && doc.data()['paymentStatus'] == 'paid')
              .fold<int>(0, (sum, doc) =>
                  sum + ((doc.data()['fare'] as num?)?.round() ?? 0));
          final unverifiedFares = totalFares - cashCollected;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Selected period', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('${_date(_from)} – ${_date(_to)}'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _chooseRange,
                            icon: const Icon(Icons.date_range),
                            label: const Text('FROM / TO DATES'),
                          ),
                          TextButton(
                            onPressed: _currentMonth,
                            child: const Text('CURRENT MONTH'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      const CircleAvatar(child: Icon(Icons.account_balance_wallet)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Completed trips'),
                            Text('${trips.length}', style: Theme.of(context).textTheme.headlineSmall),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Total fares'),
                          Text('₹$totalFares', style: Theme.of(context).textTheme.headlineSmall),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Payment summary',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('Confirmed cash collected: ₹$cashCollected'),
                      const SizedBox(height: 4),
                      Text('Fares without confirmed cash collection: ₹$unverifiedFares'),
                      const SizedBox(height: 6),
                      const Text(
                        'Historical fares without payment confirmation are not counted as collected. '
                        'Commission and net earnings are not yet calculated.',
                      ),
                    ],
                  ),
                ),
              ),
              if (missingDate > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('$missingDate older completed trip(s) have no recorded date and cannot be filtered.'),
                ),
              if (trips.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No completed trips in the selected period.')),
                ),
              for (final doc in trips) ...[
                const SizedBox(height: 10),
                Builder(builder: (context) {
                  final data = doc.data();
                  final vehicle = (data['vehicle'] ?? 'Ride').toString();
                  final fare = data['fare'] ?? 0;
                  final distance = data['distanceKm'] ?? 0;
                  final destination = (data['destinationAddress'] ?? 'Destination not recorded').toString();
                  final rating = (data['riderRating'] as num?)?.toInt();
                  final date = _tripDate(data)!.toLocal();
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(vehicle == 'Bike'
                            ? Icons.two_wheeler
                            : vehicle == 'Auto'
                                ? Icons.electric_rickshaw
                                : Icons.local_taxi),
                      ),
                      title: Text('$vehicle • ₹$fare'),
                      subtitle: Text(
                        '${_date(date)}\n$destination\n$distance km'
                        '${rating == null ? '' : '\nRider rating: $rating/5'}'
                        '\nPayment: ${data['paymentStatus'] == 'paid' && data['paymentMethod'] == 'cash' ? 'Cash received' : 'Not verified'}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.check_circle_outline),
                    ),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }
}

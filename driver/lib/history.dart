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
      initialEntryMode: DatePickerEntryMode.calendarOnly,
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

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Completed trips', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Period: ${_date(_from)} – ${_date(_to)}'),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: _chooseRange,
                  icon: const Icon(Icons.date_range),
                  label: const Text('SELECT DATES'),
                ),
                TextButton(onPressed: _currentMonth, child: const Text('CURRENT MONTH')),
              ]),
              const SizedBox(height: 8),
              Text('${trips.length} completed trip(s) • Tap a trip for its transaction details.'),
              if (missingDate > 0)
                Text('$' + '{missingDate} older trip(s) have no recorded date and are excluded.'),
              if (trips.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No completed trips in the selected period.')),
                ),
              for (final doc in trips)
                Builder(builder: (context) {
                  final data = doc.data();
                  final fare = (data['fare'] as num?)?.round() ?? 0;
                  final vehicle = (data['vehicle'] ?? 'Ride').toString();
                  final date = _tripDate(data)!.toLocal();
                  final isCashPaid = data['paymentMethod'] == 'cash' &&
                      data['paymentStatus'] == 'paid';
                  final commission = data['commissionPaise'];
                  final net = data['partnerNetPaise'];
                  final hasAccounting = isCashPaid && commission is int && net is int;
                  final gross = data['grossPaise'] is int
                      ? data['grossPaise'] as int
                      : (hasAccounting ? (commission as int) + (net as int) : 0);
                  final destination = (data['destinationAddress'] ?? 'Not recorded').toString();
                  final rating = (data['riderRating'] as num?)?.toInt();
                  final receipt = data['paymentReceiptId'];
                  return Card(
                    margin: const EdgeInsets.only(top: 10),
                    child: ExpansionTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text('₹$' + '{fare} • $' + '{vehicle}'),
                      subtitle: Text('${_date(date)} • ${isCashPaid ? 'Cash received' : 'Payment not verified'}'),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(),
                        Text('Trip ID: ${doc.id}'),
                        Text('Date: ${_date(date)}'),
                        Text('Destination: $' + '{destination}'),
                        Text('Distance: ${data['distanceKm'] ?? 'Not recorded'} km'),
                        Text('Trip fare: ₹$' + '{fare}'),
                        Text('Payment: ${isCashPaid ? 'Cash received' : 'Not verified as cash'}'),
                        if (receipt is String && receipt.isNotEmpty)
                          Text('Receipt ID: $' + '{receipt}'),
                        if (hasAccounting) ...[
                          Text('Accounted cash fare: ₹${(gross / 100).toStringAsFixed(2)}'),
                          Text('RideGo commission (10%): ₹${(commission / 100).toStringAsFixed(2)}'),
                          Text('Partner net earning: ₹${(net / 100).toStringAsFixed(2)}'),
                        ] else if (isCashPaid)
                          const Text('Historical cash receipt: commission and net not recorded.'),
                        if (rating != null) Text('Rider rating: $' + '{rating}/5'),
                      ],
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

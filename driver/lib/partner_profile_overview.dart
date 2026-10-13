import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'profile.dart';
import 'history.dart';
import 'partner_documents_section.dart';

/// Profile overview. Verification and payout are intentionally read-only
/// until their protected backend workflows are implemented.
class PartnerProfileOverview extends StatelessWidget {
  const PartnerProfileOverview({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please sign in again.')));
    }
    final db = FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: 'firestore-db-2',
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Partner Profile'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.collection('profiles').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load Partner profile.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snapshot.data!.data() ?? <String, dynamic>{};
          String field(String key) {
            final value = profile[key]?.toString().trim() ?? '';
            return value.isEmpty ? 'Not provided' : value;
          }

          Widget section(String title, IconData icon, List<Widget> children) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(icon),
                      const SizedBox(width: 10),
                      Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                    ]),
                    const SizedBox(height: 12),
                    ...children,
                  ],
                ),
              ),
            );
          }

          Widget detail(String label, String value) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('$label: $value'),
              );

          Widget editButton() => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (editContext) => DriverProfileScreen(
                        editing: true,
                        onSaved: () => Navigator.of(editContext).pop(),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('EDIT PERSONAL & VEHICLE DETAILS'),
                ),
              );

          Widget group(String title, IconData icon, List<Widget> children,
              {bool expanded = false}) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ExpansionTile(
                  initiallyExpanded: expanded,
                  leading: Icon(icon),
                  title: Text(title),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              group('Personal', Icons.person_outline, [
                section('Personal details', Icons.person_outline, [
                  const Center(child: CircleAvatar(radius: 30, child: Icon(Icons.person, size: 34))),
                  const SizedBox(height: 8),
                  detail('Full name', field('fullName')),
                  detail('Mobile', field('phone')),
                  detail('Email', user.email ?? 'Not provided'),
                  const Text('Profile photo upload: Coming soon'),
                ]),
                editButton(),
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Sign out?'),
                        content: const Text('You will need to sign in again.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                              child: const Text('CANCEL')),
                          TextButton(onPressed: () => Navigator.pop(dialogContext, true),
                              child: const Text('SIGN OUT')),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('SIGN OUT'),
                ),
              ]),
              group('Vehicle', Icons.directions_car_outlined, [
                section('Vehicle details', Icons.directions_car_outlined, [
                  detail('Vehicle type', field('vehicleType')),
                  detail('Registration number', field('vehicleNumber')),
                  detail('Make and model', field('vehicleModel')),
                ]),
                editButton(),
              ]),
              group('Earnings', Icons.account_balance_wallet_outlined, [
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: db.collection('rideRequests')
                      .where('driverId', isEqualTo: user.uid).snapshots(),
                  builder: (context, ridesSnapshot) {
                    if (ridesSnapshot.hasError) {
                      return const Text('Unable to load earnings.');
                    }
                    if (!ridesSnapshot.hasData) return const LinearProgressIndicator();
                    final now = DateTime.now();
                    final monthTrips = ridesSnapshot.data!.docs.where((doc) {
                      final data = doc.data();
                      if ((data['status'] ?? '').toString().toLowerCase() != 'completed') return false;
                      final timestamp = data['completedAt'] is Timestamp
                          ? data['completedAt'] as Timestamp
                          : data['createdAt'];
                      if (timestamp is! Timestamp) return false;
                      final date = timestamp.toDate().toLocal();
                      return date.year == now.year && date.month == now.month;
                    }).toList();
                    final accounted = monthTrips.where((doc) {
                      final data = doc.data();
                      return data['paymentMethod'] == 'cash' &&
                          data['paymentStatus'] == 'paid' &&
                          data['commissionPaise'] is int &&
                          data['partnerNetPaise'] is int;
                    }).toList();
                    final commission = accounted.fold<int>(0,
                        (sum, doc) => sum + (doc.data()['commissionPaise'] as int));
                    final net = accounted.fold<int>(0,
                        (sum, doc) => sum + (doc.data()['partnerNetPaise'] as int));
                    final gross = accounted.fold<int>(0, (sum, doc) {
                      final data = doc.data();
                      return sum + (data['grossPaise'] is int
                          ? data['grossPaise'] as int
                          : (data['commissionPaise'] as int) +
                              (data['partnerNetPaise'] as int));
                    });
                    return section('Partner earnings summary', Icons.account_balance_wallet_outlined, [
                      detail('Current month trips', '${monthTrips.length}'),
                      detail('Current month cash fare', '₹${(gross / 100).toStringAsFixed(2)}'),
                      detail('RideGo commission', '₹${(commission / 100).toStringAsFixed(2)}'),
                      detail('Net earning', '₹${(net / 100).toStringAsFixed(2)}'),
                      const SizedBox(height: 8),
                      const Text('Cash fare and earnings include only verified backend-accounted cash rides this month. Older receipts without commission records are excluded.'),
                    ]);
                  },
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DriverHistoryScreen()),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('VIEW TRIP HISTORY'),
                ),
                const Text('Cash settlement and payouts are not yet available.'),
              ], expanded: true),
              group('Documents', Icons.description_outlined, [
                section('Documents', Icons.description_outlined, [
                  const PartnerDocumentsSection(),
                ]),
                section('Bank and UPI', Icons.account_balance_outlined, [
                  const Text('Payout account configuration: Coming soon'),
                  const Text('Do not enter bank details until secure setup is available.'),
                ]),
                section('Verification', Icons.verified_user_outlined, [
                  const Text('Partner document review and approval: Not yet configured'),
                ]),
              ]),
            ],
          );
        },
      ),
    );
  }
}

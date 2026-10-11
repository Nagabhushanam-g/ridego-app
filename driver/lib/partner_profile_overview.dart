import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'profile.dart';
import 'history.dart';

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
      appBar: AppBar(title: const Text('My Partner Profile')),
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

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              section('Personal details', Icons.person_outline, [
                const Center(child: CircleAvatar(radius: 30, child: Icon(Icons.person, size: 34))),
                const SizedBox(height: 8),
                detail('Full name', field('fullName')),
                detail('Mobile', field('phone')),
                detail('Email', user.email ?? 'Not provided'),
                const Text('Profile photo upload: Coming soon'),
              ]),
              section('Vehicle details', Icons.directions_car_outlined, [
                detail('Vehicle type', field('vehicleType')),
                detail('Registration number', field('vehicleNumber')),
                detail('Make and model', field('vehicleModel')),
              ]),
              Padding(
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
              ),
              section('Trip history', Icons.history, [
                const Text('Review completed rides, fares, trip distances and rider ratings.'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DriverHistoryScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('VIEW TRIP HISTORY'),
                ),
              ]),
              section('Documents', Icons.description_outlined, [
                const Text('Driving licence, registration certificate (RC), insurance and applicable permits.'),
                const SizedBox(height: 6),
                const Text('Secure document upload: Coming soon'),
              ]),
              section('Bank and UPI', Icons.account_balance_outlined, [
                const Text('Payout account configuration: Coming soon'),
                const Text('Do not enter bank details until secure setup is available.'),
              ]),
              section('Verification', Icons.verified_user_outlined, [
                const Text('Partner document review and approval: Not yet configured'),
                const Text('Online availability is not an approval status.'),
              ]),
              section('Account settings', Icons.settings_outlined, [
                const Text('Use GO ONLINE / GO OFFLINE on the Partner home screen.'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Sign out?'),
                        content: const Text('You will need to sign in again to use RideGo Partner.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, false),
                            child: const Text('CANCEL'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('SIGN OUT'),
                          ),
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
            ],
          );
        },
      ),
    );
  }
}

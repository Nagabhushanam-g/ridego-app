import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

const String _rideGoFirestoreDatabaseId = 'firestore-db-2';

FirebaseFirestore get _profilesDb => FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: _rideGoFirestoreDatabaseId,
    );

class RiderProfileGate extends StatefulWidget {
  const RiderProfileGate({super.key, required this.home});
  final Widget home;

  @override
  State<RiderProfileGate> createState() => _RiderProfileGateState();
}

class _RiderProfileGateState extends State<RiderProfileGate> {
  Future<bool>? _profileFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _profileFuture = uid == null
        ? Future.value(false)
        : _profilesDb.collection('profiles').doc(uid).get().then((doc) => doc.exists);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Unable to load your profile.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(_refresh),
                      child: const Text('RETRY'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (snapshot.data == true) return widget.home;
        return RiderProfileScreen(onSaved: () => setState(_refresh));
      },
    );
  }
}

class RiderProfileScreen extends StatefulWidget {
  const RiderProfileScreen({super.key, required this.onSaved});
  final VoidCallback onSaved;

  @override
  State<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends State<RiderProfileScreen> {
  final name = TextEditingController();
  final phone = TextEditingController();
  bool saving = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final user = FirebaseAuth.instance.currentUser;
    final fullName = name.text.trim();
    final mobile = phone.text.trim();
    if (user == null) return;
    if (fullName.length < 2 || mobile.length < 10) {
      setState(() => error = 'Enter your full name and a valid mobile number.');
      return;
    }

    setState(() {
      saving = true;
      error = null;
    });

    try {
      final profileRef = _profilesDb.collection('profiles').doc(user.uid);
      final existing = await profileRef.get();
      final existingPin = existing.data()?['ridePin']?.toString();
      final ridePin = existingPin != null && RegExp(r'^\d{4}
        'uid': user.uid,
        'role': 'rider',
        'fullName': fullName,
        'phone': mobile,
        'email': user.email,
        'ridePin': ridePin,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) widget.onSaved();
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to save profile. Please try again.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Rider profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.person, size: 72),
            const SizedBox(height: 12),
            const Text('Complete your profile', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextField(controller: name, textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder())),
            const SizedBox(height: 14),
            TextField(controller: phone, keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile number', prefixIcon: Icon(Icons.phone_outlined), border: OutlineInputBorder())),
            const SizedBox(height: 14),
            Text('Email: $email'),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            SizedBox(height: 50, child: FilledButton(
              onPressed: saving ? null : save,
              child: saving ? const CircularProgressIndicator() : const Text('SAVE & CONTINUE'),
            )),
          ],
        ),
      ),
    );
  }
}
).hasMatch(existingPin)
          ? existingPin
          : (1000 + math.Random.secure().nextInt(9000)).toString();
      await profileRef.set({
        'uid': user.uid,
        'role': 'rider',
        'fullName': fullName,
        'phone': mobile,
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) widget.onSaved();
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to save profile. Please try again.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Rider profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.person, size: 72),
            const SizedBox(height: 12),
            const Text('Complete your profile', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextField(controller: name, textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder())),
            const SizedBox(height: 14),
            TextField(controller: phone, keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile number', prefixIcon: Icon(Icons.phone_outlined), border: OutlineInputBorder())),
            const SizedBox(height: 14),
            Text('Email: $email'),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            SizedBox(height: 50, child: FilledButton(
              onPressed: saving ? null : save,
              child: saving ? const CircularProgressIndicator() : const Text('SAVE & CONTINUE'),
            )),
          ],
        ),
      ),
    );
  }
}

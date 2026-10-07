import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

const String _rideGoFirestoreDatabaseId = 'firestore-db-2';

FirebaseFirestore get _profilesDb => FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: _rideGoFirestoreDatabaseId,
    );

class DriverProfileGate extends StatefulWidget {
  const DriverProfileGate({super.key, required this.home});
  final Widget home;

  @override
  State<DriverProfileGate> createState() => _DriverProfileGateState();
}

class _DriverProfileGateState extends State<DriverProfileGate> {
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
        return DriverProfileScreen(onSaved: () => setState(_refresh));
      },
    );
  }
}

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key, required this.onSaved});
  final VoidCallback onSaved;

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final vehicleNumber = TextEditingController();
  final drivingLicense = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  XFile? rcFront;
  XFile? rcBack;
  String vehicleType = 'Bike';
  bool saving = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    vehicleNumber.dispose();
    drivingLicense.dispose();
    super.dispose();
  }

  Future<void> pickRc(bool front) async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;
    setState(() {
      if (front) {
        rcFront = image;
      } else {
        rcBack = image;
      }
      error = null;
    });
  }

  Future<String> uploadRc(String uid, XFile file, String side) async {
    final ref = FirebaseStorage.instance.ref('driver_documents/$uid/rc_$side.jpg');
    await ref.putData(await file.readAsBytes(), SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<void> save() async {
    final user = FirebaseAuth.instance.currentUser;
    final fullName = name.text.trim();
    final mobile = phone.text.trim();
    final number = vehicleNumber.text.trim().toUpperCase();
    final license = drivingLicense.text.trim().toUpperCase();
    if (user == null) return;
    if (fullName.length < 2 ||
        mobile.length < 10 ||
        number.length < 4 ||
        license.length < 5 ||
        rcFront == null ||
        rcBack == null) {
      setState(() => error =
          'Enter all details, driving license number, and upload RC front and back copies.');
      return;
    }

    setState(() {
      saving = true;
      error = null;
    });

    try {
      final rcFrontUrl = await uploadRc(user.uid, rcFront!, 'front');
      final rcBackUrl = await uploadRc(user.uid, rcBack!, 'back');
      await _profilesDb.collection('profiles').doc(user.uid).set({
        'uid': user.uid,
        'role': 'driver',
        'fullName': fullName,
        'phone': mobile,
        'email': user.email,
        'vehicleType': vehicleType,
        'vehicleNumber': number,
        'drivingLicense': license,
        'rcFrontUrl': rcFrontUrl,
        'rcBackUrl': rcBackUrl,
        'documentsSubmittedAt': FieldValue.serverTimestamp(),
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
      appBar: AppBar(title: const Text('Driver profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.local_taxi, size: 72),
            const SizedBox(height: 12),
            const Text('Complete your driver profile', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextField(controller: name, textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder())),
            const SizedBox(height: 14),
            TextField(controller: phone, keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile number', prefixIcon: Icon(Icons.phone_outlined), border: OutlineInputBorder())),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: vehicleType,
              decoration: const InputDecoration(labelText: 'Vehicle type', border: OutlineInputBorder()),
              items: const ['Bike', 'Auto', 'Cab']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: saving ? null : (v) => setState(() => vehicleType = v ?? vehicleType),
            ),
            const SizedBox(height: 14),
            TextField(controller: vehicleNumber, textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Vehicle number', prefixIcon: Icon(Icons.confirmation_number_outlined), border: OutlineInputBorder())),
            const SizedBox(height: 14),
            TextField(
              controller: drivingLicense,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Driving license number',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: saving ? null : () => pickRc(true),
              icon: Icon(rcFront == null ? Icons.upload_file : Icons.check_circle),
              label: Text(rcFront == null ? 'Upload RC front copy' : 'RC front selected'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: saving ? null : () => pickRc(false),
              icon: Icon(rcBack == null ? Icons.upload_file : Icons.check_circle),
              label: Text(rcBack == null ? 'Upload RC back copy' : 'RC back selected'),
            ),
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

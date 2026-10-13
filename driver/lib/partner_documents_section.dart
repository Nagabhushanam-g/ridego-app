import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

/// Partner-submitted details are NOT approval or identity verification.
class PartnerDocumentsSection extends StatefulWidget {
  const PartnerDocumentsSection({super.key});

  @override
  State<PartnerDocumentsSection> createState() => _PartnerDocumentsSectionState();
}

class _PartnerDocumentsSectionState extends State<PartnerDocumentsSection> {
  static const maxBytes = 5 * 1024 * 1024;
  final _licence = TextEditingController();
  DateTime? _licenceExpiry;
  bool _rcSubmitted = false;
  bool _licenceSaved = false;
  bool _busy = false;
  String? _error;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  Reference? get _rcRef => _uid == null
      ? null
      : FirebaseStorage.instance.ref('partnerDocuments/$_uid/registrationCertificate');

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _licence.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final db = FirebaseFirestore.instanceFor(
        app: Firebase.app(), databaseId: 'firestore-db-2');
      final profile = await db.collection('profiles').doc(uid).get();
      final number = (profile.data()?['drivingLicenceNumber'] ?? '').toString();
      final storedExpiry = profile.data()?['drivingLicenceExpiryDate'];
      final expiry = storedExpiry is Timestamp ? storedExpiry.toDate() : null;
      if (mounted) {
        _licence.text = number;
        setState(() {
          _licenceExpiry = expiry;
          _licenceSaved = number.isNotEmpty && expiry != null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load licence details.');
    }
    try {
      await _rcRef?.getMetadata();
      if (mounted) setState(() => _rcSubmitted = true);
    } on FirebaseException catch (e) {
      if (mounted && e.code != 'object-not-found') {
        setState(() => _error = 'Unable to check RC upload status.');
      }
    }
  }

  Future<void> _saveLicence() async {
    final uid = _uid;
    if (uid == null || _busy) return;
    final number = _licence.text.trim().toUpperCase().replaceAll(' ', '');
    if (!RegExp(r'^[A-Z0-9-]{8,25}$').hasMatch(number)) {
      setState(() => _error = 'Enter a valid driving licence number (8–25 letters/digits).');
      return;
    }
    final expiry = _licenceExpiry;
    final today = DateUtils.dateOnly(DateTime.now());
    if (expiry == null || !DateUtils.dateOnly(expiry).isAfter(today)) {
      setState(() => _error = 'Select a driving licence expiry date after today.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final db = FirebaseFirestore.instanceFor(
        app: Firebase.app(), databaseId: 'firestore-db-2');
      await db.collection('profiles').doc(uid).update({
        'drivingLicenceNumber': number,
        'drivingLicenceExpiryDate': Timestamp.fromDate(DateUtils.dateOnly(expiry)),
        'drivingLicenceSubmittedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() { _licenceSaved = true; _licence.text = number; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Licence number and expiry saved. Verification pending.')));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to save licence number.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadRc() async {
    final ref = _rcRef;
    if (ref == null || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        withData: true,
        allowMultiple: false,
      );
      if (result == null) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty || bytes.length > maxBytes) {
        throw StateError('Select a JPG or PNG image smaller than 5 MB.');
      }
      final ext = (file.extension ?? '').toLowerCase();
      final mime = switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        _ => throw StateError('Only JPG and PNG images are allowed.'),
      };
      await ref.putData(bytes, SettableMetadata(contentType: mime));
      if (mounted) {
        setState(() => _rcSubmitted = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('RC image uploaded. Verification pending.')));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'RC upload failed. Check image size and Storage rules.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Driving licence number'),
        const SizedBox(height: 8),
        TextField(
          controller: _licence,
          enabled: !_busy,
          textCapitalization: TextCapitalization.characters,
          maxLength: 25,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: 'Enter licence number',
            helperText: _licenceSaved ? 'Saved • Pending verification' : 'No document upload required',
          ),
          onChanged: (_) {
            if (_licenceSaved) setState(() => _licenceSaved = false);
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : () async {
            final today = DateUtils.dateOnly(DateTime.now());
            final selected = await showDatePicker(
              context: context,
              initialDate: _licenceExpiry != null && _licenceExpiry!.isAfter(today)
                  ? _licenceExpiry! : today.add(const Duration(days: 1)),
              firstDate: today.add(const Duration(days: 1)),
              lastDate: DateTime(today.year + 30, 12, 31),
              helpText: 'Driving licence expiry date',
            );
            if (selected != null && mounted) {
              setState(() {
                _licenceExpiry = selected;
                _licenceSaved = false;
              });
            }
          },
          icon: const Icon(Icons.event_outlined),
          label: Text(_licenceExpiry == null
              ? 'SELECT LICENCE EXPIRY DATE'
              : 'Expiry: ${_licenceExpiry!.day.toString().padLeft(2, '0')}/${_licenceExpiry!.month.toString().padLeft(2, '0')}/${_licenceExpiry!.year}'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _saveLicence,
          icon: const Icon(Icons.save_outlined),
          label: const Text('SAVE LICENCE DETAILS'),
        ),
        const SizedBox(height: 20),
        Text('Registration certificate (RC)',
          style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(_rcSubmitted ? 'Image uploaded • Pending verification' : 'Not uploaded'),
        const Text('Upload one JPG or PNG image, maximum 5 MB. PDF is not accepted.'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _uploadRc,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(_rcSubmitted ? 'REPLACE RC IMAGE' : 'UPLOAD RC IMAGE'),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 12),
        const Text('Submission does not mean approval. Only authorized staff can verify partner details.'),
      ],
    );
  }
}

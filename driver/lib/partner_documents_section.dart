import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

/// Private uploads. Submission is NOT approval or identity verification.
class PartnerDocumentsSection extends StatefulWidget {
  const PartnerDocumentsSection({super.key});

  @override
  State<PartnerDocumentsSection> createState() => _PartnerDocumentsSectionState();
}

class _PartnerDocumentsSectionState extends State<PartnerDocumentsSection> {
  static const documents = <String, String>{
    'drivingLicence': 'Driving licence',
    'registrationCertificate': 'Registration certificate (RC)',
    'insurance': 'Vehicle insurance',
    'permit': 'Applicable permit (if required)',
  };
  static const maxBytes = 5 * 1024 * 1024;
  final Map<String, bool> _submitted = {};
  String? _busy;
  String? _error;

  Reference? _reference(String key) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseStorage.instance.ref('partnerDocuments/$uid/$key');
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    for (final key in documents.keys) {
      final ref = _reference(key);
      if (ref == null) return;
      try {
        await ref.getMetadata();
        if (mounted) setState(() => _submitted[key] = true);
      } on FirebaseException catch (e) {
        if (e.code == 'object-not-found') {
          if (mounted) setState(() => _submitted[key] = false);
        } else if (mounted) {
          setState(() => _error = 'Document status unavailable. Check Storage access.');
        }
      }
    }
  }

  Future<void> _upload(String key) async {
    final ref = _reference(key);
    if (ref == null || _busy != null) return;
    setState(() { _busy = key; _error = null; });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
        allowMultiple: false,
      );
      if (result == null) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) throw StateError('Unable to read the selected file.');
      if (bytes.isEmpty || bytes.length > maxBytes) {
        throw StateError('Choose a file smaller than 5 MB.');
      }
      final ext = (file.extension ?? '').toLowerCase();
      final mime = switch (ext) {
        'pdf' => 'application/pdf',
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        _ => throw StateError('Only PDF, JPG and PNG are supported.'),
      };
      await ref.putData(bytes, SettableMetadata(contentType: mime));
      if (mounted) {
        setState(() => _submitted[key] = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document submitted. Verification is pending.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Upload PDF, JPG or PNG files, up to 5 MB each. Documents are private and are not verified automatically.'),
        const SizedBox(height: 12),
        for (final entry in documents.entries)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.value, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(_submitted[entry.key] == true
                      ? 'Submitted • Pending review'
                      : 'Not submitted'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy == null ? () => _upload(entry.key) : null,
                    icon: _busy == entry.key
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.upload_file),
                    label: Text(_submitted[entry.key] == true ? 'REPLACE DOCUMENT' : 'UPLOAD DOCUMENT'),
                  ),
                ],
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const Text('Uploading does not activate Partner approval. Only authorized staff can verify documents.'),
      ],
    );
  }
}

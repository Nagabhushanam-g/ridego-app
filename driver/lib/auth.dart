import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'profile.dart';

class DriverAuthGate extends StatelessWidget {
  const DriverAuthGate({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data != null) return DriverProfileGate(home: home);
        return const DriverAuthScreen();
      },
    );
  }
}

class DriverAuthScreen extends StatefulWidget {
  const DriverAuthScreen({super.key});

  @override
  State<DriverAuthScreen> createState() => _DriverAuthScreenState();
}

class _DriverAuthScreenState extends State<DriverAuthScreen> {
  final phone = TextEditingController();
  final otp = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  String? verificationId;
  int? resendToken;
  bool busy = false;
  bool useEmail = false;
  String? error;

  @override
  void dispose() {
    phone.dispose();
    otp.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  String get number => '+91${phone.text.trim()}';

  Future<void> sendCode({bool resend = false}) async {
    if (!RegExp(r'^[6-9][0-9]{9}$').hasMatch(phone.text.trim())) {
      setState(() => error = 'Enter a valid 10-digit Indian mobile number.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: number,
        forceResendingToken: resend ? resendToken : null,
        verificationCompleted: (credential) async {
          try {
            await FirebaseAuth.instance.signInWithCredential(credential);
          } on FirebaseAuthException catch (e) {
            if (mounted) setState(() => error = e.message ?? e.code);
          }
        },
        verificationFailed: (e) {
          if (mounted) setState(() { busy = false; error = e.message ?? e.code; });
        },
        codeSent: (id, token) {
          if (mounted) setState(() {
            verificationId = id;
            resendToken = token;
            busy = false;
          });
        },
        codeAutoRetrievalTimeout: (id) {
          if (mounted) setState(() { verificationId = id; busy = false; });
        },
      );
    } catch (e) {
      if (mounted) setState(() { busy = false; error = 'Could not send OTP: $e'; });
    }
  }

  Future<void> verifyCode() async {
    if (verificationId == null || !RegExp(r'^[0-9]{6}$').hasMatch(otp.text.trim())) {
      setState(() => error = 'Enter the 6-digit OTP.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId!, smsCode: otp.text.trim());
      await FirebaseAuth.instance.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => error = e.message ?? e.code);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> emailSignIn() async {
    setState(() { busy = true; error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.text.trim(), password: password.text);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => error = e.message ?? e.code);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('RideGo Partner')),
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.phone_android, size: 64, color: Color(0xFF1565C0)),
          const SizedBox(height: 16),
          Text('Sign in with mobile OTP',
            style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Verify your number to continue securely.'),
          const SizedBox(height: 24),
          if (!useEmail) ...[
            TextField(
              controller: phone, enabled: !busy && verificationId == null,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              decoration: const InputDecoration(
                prefixText: '+91 ', labelText: 'Mobile number',
                border: OutlineInputBorder()),
            ),
            if (verificationId != null) ...[
              const SizedBox(height: 12),
              TextField(controller: otp, keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: '6-digit SMS OTP', border: OutlineInputBorder())),
              TextButton(onPressed: busy ? null : () => sendCode(resend: true),
                child: const Text('Resend OTP')),
              TextButton(onPressed: busy ? null : () => setState(() {
                verificationId = null; otp.clear(); error = null;
              }), child: const Text('Change mobile number')),
            ],
          ] else ...[
            TextField(controller: email, keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Existing account email', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: password, obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password', border: OutlineInputBorder())),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, height: 48,
            child: FilledButton(
              onPressed: busy ? null : useEmail ? emailSignIn :
                verificationId == null ? sendCode : verifyCode,
              child: busy ? const CircularProgressIndicator() :
                Text(useEmail ? 'SIGN IN WITH EMAIL' :
                  verificationId == null ? 'SEND OTP' : 'VERIFY & CONTINUE'),
            )),
          const SizedBox(height: 12),
          TextButton(
            onPressed: busy ? null : () => setState(() {
              useEmail = !useEmail; error = null;
            }),
            child: Text(useEmail ? 'Use mobile number and OTP' :
              'Existing email account? Sign in here'),
          ),
          const SizedBox(height: 8),
          const Text('Existing email accounts should use email sign-in until '
            'their mobile number is linked, to preserve ride history.',
            textAlign: TextAlign.center),
        ]),
      ),
    ))),
  );
}

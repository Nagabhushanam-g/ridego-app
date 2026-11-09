import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'profile.dart';

class RiderAuthGate extends StatelessWidget {
  const RiderAuthGate({super.key, required this.home});

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
        // Only verified phone or legacy email accounts may pass this gate.
        // Anonymous sessions from older builds must sign in again.
        if (snapshot.data?.isAnonymous == true) {
          return const RiderAuthScreen();
        }
        if (snapshot.data != null) return RiderProfileGate(home: home);
        return const RiderAuthScreen();
      },
    );
  }
}

class RiderAuthScreen extends StatefulWidget {
  const RiderAuthScreen({super.key});

  @override
  State<RiderAuthScreen> createState() => _RiderAuthScreenState();
}

class _RiderAuthScreenState extends State<RiderAuthScreen> {
  final phone = TextEditingController();
  final otp = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  String? verificationId;
  int? resendToken;
  bool busy = false;
  bool useEmail = false;
  Timer? _cooldownTimer;
  int _resendSeconds = 0;
  bool _firebaseBlocked = false;

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    if (!mounted) return;
    setState(() => _resendSeconds = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() {
          _resendSeconds = 0;
          // Local cooldown has ended; Firebase may still reject another
          // attempt, which is handled by verificationFailed.
          _firebaseBlocked = false;
        });
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  void _handlePhoneError(FirebaseAuthException e) {
    if (!mounted) return;
    final blocked = e.code == 'too-many-requests' ||
        e.code == 'quota-exceeded' ||
        (e.message ?? '').toLowerCase().contains('unusual activity');
    setState(() {
      busy = false;
      _firebaseBlocked = blocked;
      error = blocked
          ? 'Firebase has temporarily blocked SMS requests. Stop retrying and use your existing email sign-in until Firebase allows requests again.'
          : e.code == 'operation-not-allowed'
              ? 'Phone authentication is unavailable. Check Firebase Phone sign-in and SMS region settings.'
              : e.code == 'invalid-phone-number'
                  ? 'Enter a valid mobile number.'
                  : e.message ?? 'Unable to send OTP (${e.code}).';
    });
    if (blocked) _startCooldown(3600);
  }

  String? error;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    phone.dispose();
    otp.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  String get number => '+91${phone.text.trim()}';

  Future<void> sendCode({bool resend = false}) async {
    if (_resendSeconds > 0 || _firebaseBlocked) return;
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
            _handlePhoneError(e);
          }
        },
        verificationFailed: _handlePhoneError,
        codeSent: (id, token) {
          if (mounted) setState(() {
            verificationId = id;
            resendToken = token;
            busy = false;
          });
          _startCooldown(60);
        },
        codeAutoRetrievalTimeout: (id) {
          if (mounted) setState(() { verificationId = id; busy = false; });
        },
      );
    } catch (e) {
      if (e is FirebaseAuthException) {
        _handlePhoneError(e);
      } else if (mounted) {
        setState(() { busy = false; error = 'Could not send OTP. Check your connection and try later.'; });
      }
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
    appBar: AppBar(title: const Text('RideGo Rider')),
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
              TextButton(onPressed: busy || _resendSeconds > 0 || _firebaseBlocked
                  ? null : () => sendCode(resend: true),
                child: Text(_resendSeconds > 0
                    ? 'Resend OTP in ${_resendSeconds}s' : 'Resend OTP')),
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
                verificationId == null
                    ? (_resendSeconds > 0 || _firebaseBlocked ? null : sendCode)
                    : verifyCode,
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

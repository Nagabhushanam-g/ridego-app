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
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool register = false;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final e = email.text.trim();
    final p = password.text;
    if (e.isEmpty || p.length < 6) {
      setState(() => error = 'Enter a valid email and a password of at least 6 characters.');
      return;
    }
    if (register && p != confirm.text) {
      setState(() => error = 'Passwords do not match.');
      return;
    }

    setState(() {
      busy = true;
      error = null;
    });

    try {
      if (register) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: e,
          password: p,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: e,
          password: p,
        );
      }
    } on FirebaseAuthException catch (ex) {
      setState(() => error = _message(ex.code));
    } catch (_) {
      setState(() => error = 'Unable to complete authentication.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _message(String code) => switch (code) {
        'invalid-credential' => 'Email or password is incorrect.',
        'invalid-email' => 'Enter a valid email address.',
        'email-already-in-use' => 'This email is already registered.',
        'weak-password' => 'Use a stronger password.',
        'user-disabled' => 'This account has been disabled.',
        'operation-not-allowed' => 'Email/password sign-in is not enabled in Firebase yet.',
        _ => 'Authentication error: $code',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  const Icon(Icons.local_taxi, size: 72),
                  const SizedBox(height: 12),
                  const Text(
                    'RideGo Driver',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    register ? 'Create your driver account' : 'Sign in to RideGo',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (register) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: confirm,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                        prefixIcon: Icon(Icons.lock_reset_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: busy ? null : submit,
                      child: busy
                          ? const CircularProgressIndicator()
                          : Text(register ? 'CREATE ACCOUNT' : 'LOGIN'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                              register = !register;
                              error = null;
                            }),
                    child: Text(
                      register
                          ? 'Already have an account? Login'
                          : 'New to RideGo? Create account',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

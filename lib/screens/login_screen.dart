import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/socket_service.dart';
import '../services/drone_service.dart';
import 'home_screen.dart';
import 'client_home_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isSubmitting = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guardian'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Stack(
                children: [
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Column(
                              children: [
                                Icon(Icons.shield, size: 54, color: theme.primaryColor),
                                const SizedBox(height: 8),
                                Text(
                                  'Guardian Drone Controller',
                                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Please sign in to continue',
                                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Enter email';
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _obscure ? 'Show' : 'Hide',
                                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                              ),
                              obscureText: _obscure,
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Enter password';
                                if (v.length < 6) return 'Min 6 characters';
                                return null;
                              },
                            ),

                            const SizedBox(height: 20),
                            SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _isSubmitting ? null : () => _submitLogin(context),
                                icon: _isSubmitting
                                    ? const SizedBox(
                                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                                      )
                                    : const Icon(Icons.login),
                                label: Text(_isSubmitting ? 'Signing in...' : 'Login'),
                              ),
                            ),

                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _isSubmitting ? null : () => Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const SignupScreen()),
                                    ),
                                    icon: const Icon(Icons.person_add_alt),
                                    label: const Text('Create Account'),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _isSubmitting ? null : _signInWithGoogle,
                                    icon: const Icon(Icons.g_mobiledata),
                                    label: const Text('Continue with Google'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _isSubmitting ? null : _signInWithFacebook,
                                    icon: const Icon(Icons.facebook),
                                    label: const Text('Continue with Facebook'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Material(
                      color: Colors.transparent,
                      child: IconButton(
                        tooltip: 'Skip',
                        icon: const Icon(Icons.close),
                        onPressed: _isSubmitting ? null : () => _skipToClient(context),
                      ),
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

  Future<void> _submitLogin(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final email = _emailController.text.trim();
      final pwd = _passwordController.text;
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pwd);
      _routeAfterAuth(email);
    } on FirebaseAuthException catch (e) {
      _showError('${e.code}: ${e.message ?? 'Login failed'}');
    } catch (e) {
      _showError('Login failed: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _routeAfterAuth(String email) {
    final normalized = email.toLowerCase();
    final socketService = context.read<SocketService>();
    final droneService = context.read<DroneService>();
    droneService.initialize(socketService);
    if (normalized == 'admin@guardian.com') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ClientHomeScreen()),
      );
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _signInWithGoogle() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Google Sign-In will be enabled after Firebase setup.')),
    );
  }

  void _signInWithFacebook() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Facebook Sign-In will be enabled after Firebase setup.')),
    );
  }

  void _skipToClient(BuildContext context) {
    final socketService = context.read<SocketService>();
    final droneService = context.read<DroneService>();
    droneService.initialize(socketService);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ClientHomeScreen()),
    );
  }
}

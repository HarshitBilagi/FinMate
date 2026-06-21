/// Splash-to-Auth lock screen.
///
/// Shows a frosted-glass blur effect until the user successfully
/// authenticates via fingerprint, face, or device PIN.
/// The app cannot proceed past this screen without authentication.
library;

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:personal_finance_assistant/providers/auth_provider.dart';
import 'package:personal_finance_assistant/core/theme/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Check biometrics and auto-trigger on load
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      await auth.checkBiometrics();
      if (auth.biometricsAvailable) {
        _triggerAuth();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _triggerAuth() async {
    final auth = context.read<AuthProvider>();
    final success = await auth.authenticate();
    if (success && mounted) {
      Navigator.of(context).pushReplacementNamed('/loading');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // ── Background gradient ────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: isDark
                  ? AppTheme.heroGradientDark
                  : AppTheme.heroGradientLight,
            ),
          ),

          // ── Frosted glass overlay ──────────────────────────────────
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: (isDark ? Colors.black : Colors.white)
                  .withValues(alpha: 0.3),
            ),
          ),

          // ── Content ────────────────────────────────────────────────
          SafeArea(
            child: Center(
              child: Consumer<AuthProvider>(
                builder: (context, auth, _) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // App icon
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) => Transform.scale(
                        scale: _pulseAnimation.value,
                        child: child,
                      ),
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.15),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.shield_outlined,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Title
                    Text(
                      'Finance Friend',
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Authenticate to continue',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Error message
                    if (auth.errorMessage != null) ...[
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.expense.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.expense.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          auth.errorMessage!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Auth button
                    if (auth.isAuthenticating)
                      const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      )
                    else
                      _AuthButton(
                        onPressed: _triggerAuth,
                        biometricsAvailable: auth.biometricsAvailable,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool biometricsAvailable;

  const _AuthButton({
    required this.onPressed,
    required this.biometricsAvailable,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              biometricsAvailable
                  ? Icons.fingerprint
                  : Icons.lock_outline,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              biometricsAvailable ? 'Unlock with Biometrics' : 'Unlock',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

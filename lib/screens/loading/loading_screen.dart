import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:personal_finance_assistant/providers/dashboard_provider.dart';
import 'package:personal_finance_assistant/core/theme/app_theme.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late DashboardProvider _dashboardProvider;

  final List<String> _quotes = [
    "Budgeting isn't about restriction; it is about intentionality.",
    "You do what is in your heart, son. You will be fine.",
    "Do not save what is left after spending, but spend what is left after saving.",
    "An investment in knowledge pays the best interest.",
    "Beware of little expenses; a small leak will sink a great ship.",
  ];

  int _currentQuoteIndex = 0;
  Timer? _quoteTimer;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();

    // Pulse animation for the app logo
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Rotate quotes every 4 seconds
    _quoteTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted && !_hasError) {
        setState(() {
          _currentQuoteIndex = (_currentQuoteIndex + 1) % _quotes.length;
        });
      }
    });

    _dashboardProvider = Provider.of<DashboardProvider>(context, listen: false);
    _dashboardProvider.addListener(_onDashboardStateChanged);

    // Trigger dashboard data sync on mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dashboardProvider.loadDashboard();
    });
  }

  @override
  void dispose() {
    _dashboardProvider.removeListener(_onDashboardStateChanged);
    _quoteTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _onDashboardStateChanged() {
    if (!mounted) return;
    
    if (!_dashboardProvider.isLoading) {
      if (_dashboardProvider.errorMessage == null) {
        setState(() {
          _hasError = false;
        });
        // Transition to HomeScreen with a smooth custom fade transition or default router push
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        setState(() {
          _hasError = true;
        });
      }
    } else {
      // If loading restarts (e.g. from retry), hide error state
      setState(() {
        _hasError = false;
      });
    }
  }

  void _retryConnection() {
    _dashboardProvider.loadDashboard();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // ── Background gradient matching the theme ─────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: isDark
                  ? AppTheme.heroGradientDark
                  : AppTheme.heroGradientLight,
            ),
          ),

          // ── Frosted glass blur effect for premium look ─────────────────────
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.25),
            ),
          ),

          // ── Main UI Content ────────────────────────────────────────────────
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 3),

                    // Pulsing App Icon Container
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) => Transform.scale(
                        scale: _hasError ? 1.0 : _pulseAnimation.value,
                        child: child,
                      ),
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.15),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.tealAccent.withValues(alpha: 0.2),
                              blurRadius: 20,
                              spreadRadius: 2,
                            )
                          ],
                        ),
                        child: const Icon(
                          Icons.bubble_chart_outlined,
                          size: 56,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // App Title
                    Text(
                      'FinMate',
                      style: GoogleFonts.outfit(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Loading or Error State details
                    if (!_hasError) ...[
                      Text(
                        'Securing connection & hydrating keys...',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 32),
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      ),
                    ] else ...[
                      // Premium Error View
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.cloud_off_outlined,
                              size: 40,
                              color: Colors.white70,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Connection Timeout',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _dashboardProvider.errorMessage ??
                                  'The server is taking longer than usual to wake up from cold sleep.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _retryConnection,
                              icon: const Icon(Icons.refresh_rounded, size: 20),
                              label: const Text('Retry Connection'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.teal.shade800,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const Spacer(flex: 3),

                    // Rotating Finance Quote (Hidden or dimmed on error)
                    AnimatedOpacity(
                      opacity: _hasError ? 0.3 : 1.0,
                      duration: const Duration(milliseconds: 500),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        height: 120,
                        alignment: Alignment.center,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 800),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          child: Column(
                            key: ValueKey<int>(_currentQuoteIndex),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '"${_quotes[_currentQuoteIndex]}"',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.white,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: 40,
                                height: 2,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
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

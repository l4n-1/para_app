import 'dart:math';

import 'package:flutter/material.dart';
import 'package:para2/pages/home/pasa/pasaheroverification.dart';
import 'package:para2/pages/home/tsuper/tsuperheroverification.dart';

class RolePick extends StatelessWidget {
  const RolePick({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hero Selection',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'HelveticaNowText',
      ),
      home: HeroSelectionScreen(),
    );
  }
}

class HeroSelectionScreen extends StatefulWidget {
  @override
  _HeroSelectionScreenState createState() => _HeroSelectionScreenState();
}

class _HeroSelectionScreenState extends State<HeroSelectionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _whiteOverlayAnimation;
  late Animation<Offset> _positionAnimation;
  late Animation<double> _imageFadeAnimation;

  String? _selectedHero;
  bool _isTransitioning = false;
  Image? _selectedHeroLogo;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 2500),
    );

    // Animation setup
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(0.0, 0.3, curve: Curves.easeInOut),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(0.1, 0.3, curve: Curves.easeOut),
      ),
    );

    _whiteOverlayAnimation = Tween<double>(begin: 0.0, end: 5.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(0.5, 0.9, curve: Curves.easeIn),
      ),
    );

    _imageFadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(0.5, 0.9, curve: Curves.easeIn),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setSelectedHeroLogo(String hero) {
    setState(() {
      _selectedHeroLogo = Image.asset(
        hero == 'PASAHERO'
            ? 'assets/pasaherologo.png'
            : 'assets/tsuperherologo.png',
        fit: BoxFit.cover,
      );
    });
  }

  void _selectHero(String hero) {
    if (_isTransitioning) return;

    // Set the correct logo before starting transition
    _setSelectedHeroLogo(hero);

    setState(() {
      _selectedHero = hero;
      _isTransitioning = true;

      // Set up position animation based on selected hero
      _positionAnimation =
          Tween<Offset>(
            begin: hero == 'PASAHERO' ? Offset(-0.5, 0) : Offset(0.5, 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(
              parent: _controller,
              curve: Interval(0.0, 0.3, curve: Curves.easeInOut),
            ),
          );
    });

    _controller.forward().then((_) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) {
            return _selectedHero == 'PASAHERO'
                ? PasaheroVerificationPage()
                : TsuperheroVerificationPage();
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: Duration(milliseconds: 500),
        ),
      ).then((_) {
        if (mounted) {
          setState(() {
            _isTransitioning = false;
            _selectedHero = null;
            _controller.reset();
          });
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final maxDimension = max(screenSize.width, screenSize.height) * 1.5;

    return Scaffold(
      backgroundColor: Color.fromARGB(255, 22, 24, 27),
      body: Stack(
        children: [
          // Logo at the top
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Center(
              child: Image.asset(
                'assets/Paralogotemp.png',
                height: 120,
                fit: BoxFit.contain,
              ),
            ),
          ),

          // Hero options - clickable area
          if (!_isTransitioning)
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // PASAHERO option
                  _HeroOption(
                    label: 'PASAHERO',
                    imagePath: 'assets/pasaherologo.png',
                    onTap: () => _selectHero('PASAHERO'),
                  ),
                  SizedBox(width: 40),
                  // TSUPERHERO option
                  _HeroOption(
                    label: 'TSUPERHERO',
                    imagePath:
                        'assets/template.png', // Make sure this is correct
                    onTap: () => _selectHero('TSUPERHERO'),
                  ),
                ],
              ),
            ),

          // Animated hero during transition
          if (_isTransitioning &&
              _selectedHero != null &&
              _selectedHeroLogo != null)
            Center(
              child: SlideTransition(
                position: _positionAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        opacity: _imageFadeAnimation.value,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.white.withOpacity(0.1),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _selectedHeroLogo,
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        _selectedHero!,
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Helvetica',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // White gradient overlay
          if (_isTransitioning)
            Center(
              child: ScaleTransition(
                scale: _whiteOverlayAnimation,
                child: Image.asset(
                  'assets/circlegradientwhite.png',
                  width: maxDimension,
                  height: maxDimension,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeroOption extends StatelessWidget {
  final String label;
  final String imagePath;
  final VoidCallback onTap;

  const _HeroOption({
    required this.label,
    required this.imagePath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white.withOpacity(0.1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(imagePath, fit: BoxFit.cover),
            ),
          ),
          SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'HelveticaNowText',
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

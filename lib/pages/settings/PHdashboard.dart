import 'dart:math' as math;
import 'package:para2/pages/home/shared_home.dart';
import 'package:flutter/material.dart';



class PHDashboard extends StatefulWidget {
  final String displayName;
  const PHDashboard({Key? key, required this.displayName}) : super(key: key);

  @override
  State<PHDashboard> createState() => _PHDashboardState();
}

class _PHDashboardState extends State<PHDashboard>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _gradientController;
  late Animation<double> _gradientAnim;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _gradientController =
        AnimationController(vsync: this, duration: const Duration(seconds: 6))
          ..repeat(reverse: true);
    _gradientAnim = CurvedAnimation(
      parent: _gradientController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _gradientController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 27, 27, 27),
      body: SizedBox.expand(
        child: 
       Column(
        children: [
          // Top gradient header
          AnimatedBuilder(
            animation: _gradientAnim,
            builder: (context, child) {
              // Use a smooth sinusoidal offset to create a gentle vertical wave
              final t = _gradientAnim.value;
              final offset = math.sin(t * 0.3 * math.pi) * 0.4; // -0.4..0.4
              // Shift gradient vertically while keeping horizontal center constant
              final begin = Alignment(0.0, -1.0 + offset);
              final end = Alignment(0.0, 1.0 + offset);
              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 50),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: begin,
                    end: end,
                    colors: const [
                      Color.fromRGBO(0, 7, 4, 1),
                      Color.fromARGB(255, 15, 8, 22),
                      Color.fromARGB(255, 3, 1, 32),
                      Color.fromARGB(255, 44, 2, 48),
                      Color.fromARGB(255, 41, 0, 58),
                      Color.fromARGB(255, 41, 12, 75),
                      Color.fromARGB(255, 63, 19, 114),
                      Color.fromARGB(255, 65, 40, 158),
                    ],
                    stops: [0.45,0.55, 0.60, 0.65, 0.70, 0.75, 0.85, 1.0],
                    tileMode: TileMode.clamp,
                  ),
                ),
                child: child,
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile row
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 35,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.displayName,
                      style: const TextStyle(
                        color: Color.fromARGB(255, 255, 255, 255),
                        fontFamily:'HelveticaNowText',
                        fontWeight: FontWeight.bold,
                        fontSize: 27,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Action buttons
                Row(
                  children: [
                    _buildHeaderButton(),
                    const SizedBox(width: 10),
                    _buildHeaderButton(),
                    const SizedBox(width: 10),
                    _buildHeaderButton(),
                    const Spacer(),
                    const Icon(Icons.lock_outline, color: Colors.white),
                  ],
                ),
              ],
            ),
          ),

          // Tabs
          Container(
            height: 45,
            color: const Color.fromARGB(255, 34, 34, 34),
            child: TabBar(
              controller: _tabController,
              labelColor: const Color.fromARGB(255, 171, 236, 66),
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.white,
              tabs: const [
                Tab(icon: Icon(Icons.person)),
                Tab(icon: Icon(Icons.list_alt)),
              ],
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTabSection(),
                _buildTabSection(),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildHeaderButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  Widget _buildTabSection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 0, 0, 0),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            height: 300,
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 24, 24, 24),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../../core/constants/app_dimensions.dart';

class AgentDashboardView extends StatelessWidget {
  const AgentDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.paddingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today\'s Overview',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: AppDimensions.marginL),
            _buildStatsCards(),
            const SizedBox(height: AppDimensions.marginL),
            Text(
              'Upcoming Bookings',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppDimensions.marginM),
            // Bookings list will go here
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.book_online), label: 'Bookings'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildStatsCards() {
    return const Row(
      children: [
        Expanded(child: _StatCard(title: 'Today', value: '5', icon: Icons.today)),
        SizedBox(width: AppDimensions.marginM),
        Expanded(child: _StatCard(title: 'Pending', value: '3', icon: Icons.pending)),
        SizedBox(width: AppDimensions.marginM),
        Expanded(child: _StatCard(title: 'Completed', value: '12', icon: Icons.check_circle)),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingM),
        child: Column(
          children: [
            Icon(icon, size: AppDimensions.iconL),
            const SizedBox(height: AppDimensions.marginS),
            Text(value, style: Theme.of(context).textTheme.displaySmall),
            Text(title, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GoogleMapController? _controller;
  static const LatLng _center = LatLng(23.0225, 72.5714); // Ahmedabad

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("SafeRoute Map")),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.indigo),
              child: Text('SafeRoute', style: TextStyle(color: Colors.white, fontSize: 20)),
            ),
            ListTile(title: const Text('Home'), onTap: () => Navigator.pushReplacementNamed(context, '/')),
            ListTile(title: const Text('Profile'), onTap: () => Navigator.pushNamed(context, '/profile')),
            ListTile(title: const Text('Settings'), onTap: () => Navigator.pushNamed(context, '/settings')),
            ListTile(title: const Text('Onboarding'), onTap: () => Navigator.pushNamed(context, '/onboarding')),
            ListTile(title: const Text('Map Detail'), onTap: () => Navigator.pushNamed(context, '/map_detail')),
            ListTile(title: const Text('Contacts'), onTap: () => Navigator.pushNamed(context, '/contacts')),
            ListTile(title: const Text('Logout'), onTap: () => Navigator.pushReplacementNamed(context, '/login')),
          ],
        ),
      ),
      body: GoogleMap(
        onMapCreated: (controller) => _controller = controller,
        initialCameraPosition: const CameraPosition(target: _center, zoom: 14),
        // Disable showing device location by default while debugging ImageReader
        // warnings. Re-enable if you need the blue-dot location feature.
        myLocationEnabled: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.route),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

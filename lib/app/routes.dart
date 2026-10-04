import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:serene/app/widgets/bottom_nav_bar.dart';
import 'package:serene/features/auth/presentation/screens/auth_screen.dart';
import 'package:serene/features/home/presentation/screens/home_screen.dart';
import 'package:serene/features/settings/presentation/screens/settings_screen.dart';
import 'package:serene/features/evidence_vault/presentation/screens/vault_screen.dart';
import 'package:serene/core/services/session_manager.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Route config
GoRouter createRouter(SessionManager sessionManager) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: sessionManager,
    redirect: (context, state) {
      if (!sessionManager.isAuthenticated && state.uri.path != '/') {
        return '/';
      }
      if (sessionManager.isAuthenticated && state.uri.path == '/') {
        return '/home';
      }
      return null;
    },
    routes: [
      // Authentication route (initial route)
      GoRoute(
        path: '/',
        name: 'auth',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            MaterialPage<void>(key: state.pageKey, child: const AuthScreen()),
      ),

      // Bottom navigation routes (HOME, VAULT, SETTINGS)
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return Scaffold(
            extendBody: true,
            backgroundColor: Colors.transparent,
            body: navigationShell,
            bottomNavigationBar: BottomNavBar(
              selectedIndex: navigationShell.currentIndex,
            ),
          );
        },
        branches: [
          // HOME
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: 'home',
                pageBuilder: (context, state) => MaterialPage<void>(
                  key: state.pageKey,
                  child: const HomeScreen(),
                ),
              ),
            ],
          ),

          // VAULT (Baúl de Evidencias)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/vault',
                name: 'vault',
                pageBuilder: (context, state) => MaterialPage<void>(
                  key: state.pageKey,
                  child: const VaultScreen(),
                ),
              ),
            ],
          ),

          // SETTINGS (Configuración y Privacidad)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                name: 'settings',
                pageBuilder: (context, state) => MaterialPage<void>(
                  key: state.pageKey,
                  child: const SettingsScreen(),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
    errorPageBuilder: (context, state) => MaterialPage<void>(
      key: state.pageKey,
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16.0),
              Text(
                'Ruta no encontrada',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24.0),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Ir a Inicio'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

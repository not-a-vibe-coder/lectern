import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/created_screen.dart';
import 'screens/home_screen.dart';
import 'screens/item_screen.dart';
import 'screens/manage_screen.dart';
import 'screens/shelf_screen.dart';
import 'theme/tokens.dart';
import 'widgets/layout.dart';

/// A short fade between pages; none when reduced motion is on.
Page<void> _page(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 160),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      transitionsBuilder: (context, animation, secondary, child) {
        if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Motion.curve),
          child: child,
        );
      },
    );

GoRouter buildRouter({String initialLocation = '/app'}) => GoRouter(
  initialLocation: initialLocation,
  errorPageBuilder: (context, state) => _page(state, const NotFoundScreen()),
  routes: [
    // The marketing page lives at `/` as plain HTML served by the server;
    // the app's own home is `/app`.
    GoRoute(path: '/', redirect: (context, state) => '/app'),
    GoRoute(
      path: '/app',
      pageBuilder: (context, state) => _page(state, const HomeScreen()),
    ),
    // Flat routes: a deep link to an item builds only the item page, not the
    // shelf under it (one request instead of two on mobile data).
    GoRoute(
      path: '/s/:shelfId',
      pageBuilder: (context, state) => _page(
        state,
        ShelfScreen(
          key: ValueKey('shelf-${state.pathParameters['shelfId']}'),
          shelfId: state.pathParameters['shelfId']!,
        ),
      ),
    ),
    GoRoute(
      path: '/s/:shelfId/i/:itemId',
      pageBuilder: (context, state) => _page(
        state,
        ItemScreen(
          key: ValueKey('item-${state.pathParameters['itemId']}'),
          shelfId: state.pathParameters['shelfId']!,
          itemId: state.pathParameters['itemId']!,
        ),
      ),
    ),
    GoRoute(
      path: '/s/:shelfId/manage',
      pageBuilder: (context, state) => _page(
        state,
        ManageScreen(
          key: ValueKey('manage-${state.pathParameters['shelfId']}'),
          shelfId: state.pathParameters['shelfId']!,
        ),
      ),
    ),
    GoRoute(
      path: '/s/:shelfId/created',
      pageBuilder: (context, state) => _page(
        state,
        CreatedScreen(shelfId: state.pathParameters['shelfId']!),
      ),
    ),
  ],
);

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) => PageFrame(
    child: MessageState(
      icon: Icons.explore_off_outlined,
      title: 'This page is not here',
      body: 'Check the link, or start from the Lectern home page.',
      actions: [
        FilledButton(
          onPressed: () => context.go('/app'),
          child: const Text('Go to Lectern'),
        ),
      ],
    ),
  );
}

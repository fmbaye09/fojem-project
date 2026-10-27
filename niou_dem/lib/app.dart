import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'providers/app_provider.dart';
import 'providers/search_provider.dart';
import 'features/onboarding/screens/splash_screen.dart';
import 'features/onboarding/screens/auth_screen.dart';
import 'features/home/screens/home_screen.dart';
import 'features/search/screens/trips_screen.dart';
import 'features/booking/screens/trip_detail_screen.dart';
import 'features/booking/screens/booking_confirmation_screen.dart';
import 'features/booking/screens/booking_success_screen.dart';
import 'features/booking/screens/my_trips_screen.dart';
import 'features/booking/screens/trip_tracking_screen.dart';
import 'features/profile/screens/driver_profile_screen.dart';
import 'features/profile/screens/profile_settings_screen.dart';
import 'features/profile/screens/notifications_screen.dart';
import 'features/profile/screens/rating_screen.dart';
import 'features/profile/screens/support_screen.dart';
import 'features/profile/screens/identity_verification_screen.dart';
import 'features/onboarding/screens/language_screen.dart';
import 'features/profile/screens/terms_of_service_screen.dart';
import 'features/profile/screens/privacy_policy_screen.dart';
import 'features/seat_selection/screens/seat_selection_screen.dart';
import 'features/ride_request/screens/create_ride_request_screen.dart';
import 'features/ride_request/screens/my_ride_requests_screen.dart';
import 'features/chat/screens/conversation_list_screen.dart';
import 'features/chat/screens/chat_screen.dart';
import 'services/push_notification_service.dart';

CustomTransitionPage<void> _tabPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// Chemins accessibles sans session (avant connexion).
const _publicPaths = {'/splash', '/role-selection'};

GoRouter _buildRouter(AppProvider appProvider) => GoRouter(
  initialLocation: '/splash',
  debugLogDiagnostics: false,
  refreshListenable: appProvider,
  redirect: (context, state) {
    final path = state.matchedLocation;
    if (appProvider.isLoading) return null;

    // Session stockée mais serveur injoignable : on reste sur l'accueil,
    // qui propose de réessayer, au lieu de renvoyer vers la connexion.
    if (appProvider.sessionUnavailable) {
      return path == '/splash' ? null : '/splash';
    }

    if (!appProvider.isLoggedIn) {
      return _publicPaths.contains(path) ? null : '/role-selection';
    }

    if (_publicPaths.contains(path)) return '/home';
    return null;
  },
  routes: [
    GoRoute(
      path: '/splash',
      builder: (_, __) => const SplashScreen(),
    ),
    GoRoute(
      path: '/role-selection',
      builder: (_, __) => const AuthScreen(),
    ),
    // Onglets de la barre du bas : simple fondu entre eux, comme une barre
    // d'onglets native, plutôt qu'un glissement de page.
    GoRoute(
      path: '/home',
      pageBuilder: (_, state) => _tabPage(state, const HomeScreen()),
    ),
    GoRoute(
      path: '/trips',
      pageBuilder: (_, state) => _tabPage(state, const TripsScreen()),
    ),
    GoRoute(
      path: '/chat',
      pageBuilder: (_, state) => _tabPage(state, const ConversationListScreen()),
    ),
    GoRoute(
      path: '/profile/settings',
      pageBuilder: (_, state) => _tabPage(state, const ProfileSettingsScreen()),
    ),
    GoRoute(
      path: '/trip/:id',
      builder: (_, state) {
        final tripId = state.pathParameters['id']!;
        return TripDetailScreen(
          tripId: tripId,
          boardingStopId: state.uri.queryParameters['board'],
          alightingStopId: state.uri.queryParameters['alight'],
        );
      },
    ),
    GoRoute(
      path: '/booking/confirm',
      builder: (_, state) {
        final tripId = state.uri.queryParameters['tripId'] ?? '';
        final seats = (state.uri.queryParameters['seats'] ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList();
        return BookingConfirmationScreen(
          tripId: tripId,
          seatIds: seats,
          boardingStopId: state.uri.queryParameters['board'],
          alightingStopId: state.uri.queryParameters['alight'],
        );
      },
    ),
    GoRoute(
      path: '/booking/success',
      builder: (_, state) {
        final bookingId = state.uri.queryParameters['bookingId'] ?? '';
        return BookingSuccessScreen(bookingId: bookingId);
      },
    ),
    GoRoute(
      path: '/my-trips',
      builder: (_, __) => const MyTripsScreen(),
    ),
    GoRoute(
      path: '/my-requests',
      builder: (_, __) => const MyRideRequestsScreen(),
    ),
    GoRoute(
      path: '/trip/:id/tracking',
      builder: (_, state) {
        final tripId = state.pathParameters['id']!;
        return TripTrackingScreen(tripId: tripId);
      },
    ),
    GoRoute(
      path: '/profile/driver/:id',
      builder: (_, state) {
        final driverId = state.pathParameters['id']!;
        return DriverProfileScreen(driverId: driverId);
      },
    ),
    GoRoute(
      path: '/notifications',
      builder: (_, __) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/rate/:tripId',
      builder: (_, state) {
        final tripId = state.pathParameters['tripId']!;
        return RatingScreen(tripId: tripId);
      },
    ),
    GoRoute(
      path: '/support',
      builder: (_, __) => const SupportScreen(),
    ),
    GoRoute(
      path: '/seat-selection',
      builder: (_, state) {
        final tripId = state.uri.queryParameters['tripId'];
        return SeatSelectionScreen(
          tripId: tripId,
          boardingStopId: state.uri.queryParameters['board'],
          alightingStopId: state.uri.queryParameters['alight'],
        );
      },
    ),
    GoRoute(
      path: '/profile/identity',
      builder: (_, __) => const IdentityVerificationScreen(),
    ),
    GoRoute(
      path: '/profile/language',
      builder: (_, __) => const LanguageScreen(),
    ),
    GoRoute(
      path: '/profile/terms',
      builder: (_, __) => const TermsOfServiceScreen(),
    ),
    GoRoute(
      path: '/profile/privacy',
      builder: (_, __) => const PrivacyPolicyScreen(),
    ),
    GoRoute(
      path: '/ride-request/create',
      builder: (_, state) {
        final from = state.uri.queryParameters['from'];
        final to = state.uri.queryParameters['to'];
        return CreateRideRequestScreen(initialFrom: from, initialTo: to);
      },
    ),
    GoRoute(
      path: '/chat/:id',
      builder: (_, state) {
        final conversationId = state.pathParameters['id']!;
        final name = state.uri.queryParameters['name'] ?? 'Conversation';
        final otherUserId = state.uri.queryParameters['otherId'];
        return ChatScreen(
          conversationId: conversationId,
          otherUserName: name,
          otherUserId: otherUserId,
        );
      },
    ),
  ],
);

class FojemApp extends StatefulWidget {
  /// Session injectée (tests, aperçus) ; par défaut, session Firebase.
  final AppProvider Function()? createAppProvider;

  const FojemApp({super.key, this.createAppProvider});

  @override
  State<FojemApp> createState() => _FojemAppState();
}

class _FojemAppState extends State<FojemApp> with WidgetsBindingObserver {
  late final AppProvider _appProvider =
      widget.createAppProvider?.call() ?? AppProvider();
  late final GoRouter _router = _buildRouter(_appProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PushNotificationService().onNotificationTap = (data) {
      final convId = data['conversation_id'] as String?;
      final senderName = (data['sender_name'] as String?) ?? 'Message';
      final senderId = data['sender_id'] as String?;

      if (convId != null && convId.isNotEmpty) {
        _router.push('/chat/$convId?name=${Uri.encodeComponent(senderName)}&otherId=${senderId ?? ''}');
        return;
      }

      final tripId = (data['trip_id'] ?? '').toString();
      final type = (data['type'] ?? '').toString();

      if (type == 'booking_completed' && tripId.isNotEmpty) {
        _router.push('/rate/$tripId');
        return;
      }

      // `/trips` est l'écran de résultats de recherche : une réservation
      // confirmée se consulte dans « Mes trajets ».
      if (type == 'booking_confirmed' ||
          type == 'booking_rejected' ||
          type == 'booking_cancelled' ||
          type == 'trip_cancelled') {
        _router.push('/my-trips');
        return;
      }

      if (tripId.isNotEmpty) {
        _router.push('/trip/$tripId');
        return;
      }

      _router.push('/notifications');
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appProvider.refreshUser();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _appProvider),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
      ],
      child: MaterialApp.router(
        title: 'FOJËM',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _router,
        locale: const Locale('fr', 'FR'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('fr', 'FR'),
          Locale('en', 'US'),
        ],
      ),
    );
  }
}

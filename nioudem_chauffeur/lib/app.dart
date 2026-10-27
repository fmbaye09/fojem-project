import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'core/events/data_refresh.dart';
import 'core/theme/app_theme.dart';
import 'providers/app_provider.dart';
import 'features/onboarding/screens/splash_screen.dart';
import 'features/onboarding/screens/auth_screen.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'features/auth/screens/verification_pending_screen.dart';
import 'features/home/screens/home_screen.dart';
import 'features/trips/screens/my_trips_screen.dart';
import 'features/trips/screens/trip_manage_screen.dart';
import 'features/publish_trip/screens/publish_trip_screen.dart';
import 'features/requests/screens/booking_requests_screen.dart';
import 'features/profile/screens/profile_settings_screen.dart';
import 'features/profile/screens/notifications_screen.dart';
import 'features/profile/screens/support_screen.dart';
import 'features/profile/screens/identity_verification_screen.dart';
import 'features/profile/screens/language_screen.dart';
import 'features/profile/screens/terms_of_service_screen.dart';
import 'features/profile/screens/privacy_policy_screen.dart';
import 'features/chat/screens/conversation_list_screen.dart';
import 'features/chat/screens/chat_screen.dart';
import 'features/vehicle/screens/vehicle_screen.dart';
import 'features/earnings/screens/earnings_screen.dart';
import 'features/passenger_requests/screens/passenger_requests_screen.dart';
import 'features/trips/screens/qr_scanner_screen.dart';
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
const _publicPaths = {'/splash', '/onboarding', '/role-selection'};

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

    final isLoggedIn = appProvider.isLoggedIn;

    if (!isLoggedIn) {
      return _publicPaths.contains(path) ? null : '/role-selection';
    }

    // Le splash termine son animation puis ouvre l'accueil lui-même.
    if (_publicPaths.contains(path) && path != '/splash') {
      return '/home';
    }

    return null;
  },
  routes: [
    GoRoute(
      path: '/splash',
      builder: (_, __) => const SplashScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (_, __) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/role-selection',
      builder: (_, __) => const AuthScreen(),
    ),
    GoRoute(
      path: '/verification-pending',
      builder: (_, __) => const VerificationPendingScreen(),
    ),
    // Onglets de la barre du bas : simple fondu entre eux, comme une barre
    // d'onglets native, plutôt qu'un glissement de page.
    GoRoute(
      path: '/home',
      pageBuilder: (_, state) => _tabPage(state, const HomeScreen()),
    ),
    GoRoute(
      path: '/trips',
      pageBuilder: (_, state) => _tabPage(state, const MyTripsScreen()),
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
      path: '/publish-trip',
      builder: (_, __) => const PublishTripScreen(),
    ),
    GoRoute(
      path: '/trip/:id',
      builder: (_, state) {
        final tripId = state.pathParameters['id']!;
        return TripManageScreen(tripId: tripId);
      },
    ),
    GoRoute(
      path: '/trip/:id/scan',
      builder: (_, state) {
        final tripId = state.pathParameters['id']!;
        return QrScannerScreen(tripId: tripId);
      },
    ),
    GoRoute(
      path: '/trip/:id/requests',
      builder: (_, state) {
        final tripId = state.pathParameters['id']!;
        return BookingRequestsScreen(tripId: tripId);
      },
    ),
    GoRoute(
      path: '/notifications',
      builder: (_, __) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/support',
      builder: (_, __) => const SupportScreen(),
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
      path: '/driver/vehicle',
      builder: (_, __) => const VehicleScreen(),
    ),
    GoRoute(
      path: '/driver/earnings',
      builder: (_, __) => const EarningsScreen(),
    ),
    GoRoute(
      path: '/driver/passenger-requests',
      builder: (_, __) => const PassengerRequestsScreen(),
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
  /// Session injectée (tests, aperçus) ; par défaut, session API Laravel.
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
      final hasBookingId = (data['booking_id'] ?? '').toString().isNotEmpty;
      final title = (data['title'] ?? '').toString().toLowerCase();

      final isBookingRequest = type == 'booking_new' ||
          hasBookingId ||
          title.contains('réservation') ||
          title.contains('reservation');

      if (tripId.isNotEmpty) {
        if (isBookingRequest) {
          _router.push('/trip/$tripId/requests');
        } else {
          _router.push('/trip/$tripId');
        }
        return;
      }

      _router.push('/notifications');
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appProvider.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Retour dans l'app : ce qui a changé entre-temps s'affiche aussitôt.
      DataRefresh.instance.notify();
      _appProvider.refreshUser();
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    // Actualise immédiatement le profil et le statut chauffeur à chaque Hot Reload ('r')
    _appProvider.refreshUser();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _appProvider,
      child: MaterialApp.router(
        title: 'FOJËM Pro',
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

import 'dart:async';
import 'package:flutter/widgets.dart';

/// Signal « les données ont peut-être changé » : émis après chaque action
/// réussie de l'utilisateur, à chaque notification reçue (push ou poller) et
/// au retour dans l'app. Les écrans ouverts se rechargent alors en silence,
/// sans attendre leur prochain rafraîchissement périodique.
class DataRefresh {
  DataRefresh._();
  static final DataRefresh instance = DataRefresh._();

  final _controller = StreamController<void>.broadcast();

  Stream<void> get stream => _controller.stream;

  void notify() => _controller.add(null);
}

/// Recharge l'écran en silence à chaque [DataRefresh] (au plus une fois par
/// rafale de signaux rapprochés).
mixin AutoRefresh<T extends StatefulWidget> on State<T> {
  StreamSubscription<void>? _refreshSub;
  Timer? _refreshDebounce;

  /// Rechargement silencieux : sans spinner ni remise à zéro de l'écran.
  Future<void> onAutoRefresh();

  @override
  void initState() {
    super.initState();
    _refreshSub = DataRefresh.instance.stream.listen((_) {
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(const Duration(milliseconds: 600), () {
        if (mounted) onAutoRefresh();
      });
    });
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
  }
}

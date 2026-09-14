import 'dart:async';

import 'package:injectable/injectable.dart';

/// Broadcasts "server-side files may have changed" so features that mirror
/// server state locally can refresh without polling. Currently only
/// [SyncBloc] (via a completed pull/push) sends, and only [FileBrowserBloc]
/// listens — a `Stream<void>` is enough since there is exactly one thing to
/// say ("something changed, go look"); a richer event type would have no
/// second use.
@lazySingleton
class RemoteFileChangeNotifier {
  final _controller = StreamController<void>.broadcast();

  Stream<void> get changes => _controller.stream;

  void notifyChanged() => _controller.add(null);
}

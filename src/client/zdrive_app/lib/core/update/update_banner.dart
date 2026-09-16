import 'package:flutter/material.dart';
import '../../shared/l10n/app_localizations.dart';
import 'update_controller.dart';

class UpdateBanner extends StatefulWidget {
  const UpdateBanner({
    super.key,
    required this.controller,
    required this.child,
  });
  final UpdateController? controller;
  final Widget child;

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  @override
  void dispose() {
    widget.controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) return widget.child;
    return ListenableBuilder(
      listenable: controller,
      child: widget.child,
      builder: (context, child) {
        final phase = controller.phase;
        final hidden =
            phase == UpdatePhase.idle || phase == UpdatePhase.checking;
        final l10n = AppLocalizations.of(context)!;
        final downloading = phase == UpdatePhase.downloading;
        final restarting = phase == UpdatePhase.restarting;
        final ready = phase == UpdatePhase.ready;
        final total = controller.totalBytes;
        final progress = total == null
            ? null
            : controller.downloadedBytes / total;
        final message = downloading
            ? l10n.updateDownloading(((progress ?? 0) * 100).floor())
            : restarting
            ? l10n.updateRestarting
            : ready
            ? l10n.updateReady(controller.pending!.version)
            : l10n.updateFailed;
        return Column(
          children: [
            if (hidden)
              const SizedBox.shrink()
            else
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.system_update_alt),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                message,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            if (!downloading && !restarting)
                              TextButton(
                                onPressed: () {
                                  if (controller.pending != null) {
                                    controller.apply();
                                  } else {
                                    controller.check();
                                  }
                                },
                                child: Text(
                                  controller.pending != null
                                      ? l10n.updateRestart
                                      : l10n.updateRetry,
                                ),
                              ),
                          ],
                        ),
                        if (downloading || restarting) ...[
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: downloading ? progress : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(child: child!),
          ],
        );
      },
    );
  }
}

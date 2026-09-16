import 'package:flutter/widgets.dart';

class WindowsDownloadButton extends StatelessWidget {
  const WindowsDownloadButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

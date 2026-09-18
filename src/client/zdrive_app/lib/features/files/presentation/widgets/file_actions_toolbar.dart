import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../file_browser_bloc.dart';

/// The file-level action bar shown above the listing.
///
/// These actions used to be a stack of FABs in the lower right corner. They
/// live in a toolbar instead because the bottom of the screen already belongs
/// to the home NavigationBar, and because a toolbar scales to more actions
/// than a FAB stack does (Material 3 steers multi-action surfaces to
/// toolbars). Separate widget so it can be tested without the page's
/// GoRouter and DI setup.
class FileActionsToolbar extends StatelessWidget {
  /// Null while the listing has no loaded state yet — the view-mode toggle is
  /// hidden then, since there is no mode to toggle.
  final FileViewMode? viewMode;
  final VoidCallback onUploadFile;
  final VoidCallback onCreateFolder;

  const FileActionsToolbar({
    super.key,
    required this.viewMode,
    required this.onUploadFile,
    required this.onCreateFolder,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          MenuAnchor(
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.upload_file),
                onPressed: onUploadFile,
                child: Text(l10n.uploadFile),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.create_new_folder),
                onPressed: onCreateFolder,
                child: Text(l10n.newFolder),
              ),
            ],
            builder: (context, controller, _) => FilledButton.icon(
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              icon: const Icon(Icons.add),
              label: Text(l10n.newItem),
            ),
          ),
          const Spacer(),
          // Pull-to-refresh (RefreshIndicator, in the listing) is not
          // discoverable with a mouse — this gives desktop users an equally
          // obvious manual refresh, reusing the same RefreshFiles event.
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refresh,
            onPressed: () =>
                context.read<FileBrowserBloc>().add(const RefreshFiles()),
          ),
          if (viewMode != null)
            IconButton(
              icon: Icon(
                viewMode == FileViewMode.list
                    ? Icons.grid_view
                    : Icons.view_list,
              ),
              tooltip: viewMode == FileViewMode.list
                  ? l10n.gridView
                  : l10n.listView,
              onPressed: () {
                context.read<FileBrowserBloc>().add(const ToggleViewMode());
              },
            ),
        ],
      ),
    );
  }
}

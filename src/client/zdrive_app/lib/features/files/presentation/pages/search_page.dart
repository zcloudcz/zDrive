import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../../../core/di/injection.dart';
import '../../domain/file_item.dart';
import '../../domain/file_repository.dart';
import '../widgets/file_icon.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final FileRepository _repository = getIt<FileRepository>();
  Timer? _debounce;
  List<FileItem>? _results;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search(query.trim());
    });
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final result = await _repository.searchFiles(query);
      if (mounted) {
        setState(() {
          _results = result.items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.search,
            border: InputBorder.none,
            filled: false,
          ),
          onChanged: _onQueryChanged,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                setState(() => _results = null);
              },
            ),
        ],
      ),
      body: _buildBody(context, l10n),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results == null) {
      return Center(
        child: Icon(
          Icons.search,
          size: 64,
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    if (_results!.isEmpty) {
      return Center(
        child: Text(l10n.noFiles, style: Theme.of(context).textTheme.titleMedium),
      );
    }

    return ListView.builder(
      itemCount: _results!.length,
      itemBuilder: (context, index) {
        final file = _results![index];
        return ListTile(
          leading: FileIcon(file: file),
          title: Text(file.name),
          onTap: () {
            if (file.isFolder) {
              context.go('/home/files/folder/${file.id}');
            }
          },
        );
      },
    );
  }
}

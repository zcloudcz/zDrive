import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/error_message.dart';
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
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 0;
  int _generation = 0;
  Object? _error;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _results = null;
      _loading = false;
      _loadingMore = false;
      _hasMore = false;
      _page = 0;
      _error = null;
    });
    if (query.trim().isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search(query.trim(), generation);
    });
  }

  Future<void> _search(
    String query,
    int generation, {
    bool loadMore = false,
  }) async {
    if (!mounted || generation != _generation || _loading || query.isEmpty) {
      return;
    }
    setState(() {
      _loading = true;
      _loadingMore = loadMore;
      _error = null;
    });
    try {
      final result = await _repository.searchFiles(
        query,
        page: loadMore ? _page + 1 : 1,
      );
      if (mounted && generation == _generation) {
        setState(() {
          _results = loadMore ? [...?_results, ...result.items] : result.items;
          _page = result.page;
          _hasMore = result.hasMore;
        });
      }
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
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
              tooltip: l10n.clearSearch,
              onPressed: () {
                _controller.clear();
                _onQueryChanged('');
              },
            ),
        ],
      ),
      body: _buildBody(context, l10n),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_loading && _results == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _results == null) {
      return Center(child: _buildFooter(l10n));
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
        child: Text(
          l10n.noFiles,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }

    return ListView.builder(
      itemCount: _results!.length + 1,
      itemBuilder: (context, index) {
        if (index == _results!.length) return _buildFooter(l10n);
        final file = _results![index];
        return ListTile(
          key: ValueKey(file.id),
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

  Widget _buildFooter(AppLocalizations l10n) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(describeError(_error!, l10n), textAlign: TextAlign.center),
            TextButton(
              onPressed: () => _search(
                _controller.text.trim(),
                _generation,
                loadMore: _loadingMore,
              ),
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    }
    if (_hasMore) {
      return Center(
        child: TextButton(
          onPressed: () =>
              _search(_controller.text.trim(), _generation, loadMore: true),
          child: Text(l10n.loadMore),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

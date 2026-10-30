import 'package:flutter/material.dart';

/// Loads one page at a time so large registers are never fully in memory. Used with ListView.builder.
class PagedLoader<T> extends ChangeNotifier {
  PagedLoader(this._fetch, {this.pageSize = 30});
  final Future<List<T>> Function(int offset, int limit) _fetch;
  final int pageSize;
  final List<T> items = [];
  bool loading = false, hasMore = true, firstLoadDone = false;
  Object? error;
  int _gen = 0;

  Future<void> reset() async {
    _gen++;
    items.clear();
    hasMore = true;
    error = null;
    firstLoadDone = false;
    notifyListeners();
    await loadMore();
  }

  Future<void> loadMore() async {
    if (loading || !hasMore) return;
    loading = true;
    final gen = _gen;
    notifyListeners();
    try {
      final page = await _fetch(items.length, pageSize);
      if (gen != _gen) return;
      items.addAll(page);
      hasMore = page.length == pageSize;
      error = null;
    } catch (e) {
      if (gen != _gen) return;
      error = e;
      hasMore = false;
    } finally {
      if (gen == _gen) {
        loading = false;
        firstLoadDone = true;
        notifyListeners();
      }
    }
  }
}

/// A scrolling page: [leading] controls (search, filters, notes) scroll WITH the list, so on a small phone with large
/// text they can never push the list off the screen (a fixed header + Expanded list overflows there).
Widget pagedScrollView<T>({
  required ScrollController controller,
  required List<Widget> leading,
  required PagedLoader<T> loader,
  required Widget Function(BuildContext, T) itemBuilder,
  required Widget loading,
  required Widget empty,
  required Widget Function() error,
  EdgeInsets padding = const EdgeInsets.fromLTRB(16, 8, 16, 120),
  double itemGap = 12,
}) {
  final Widget body;
  if (!loader.firstLoadDone) {
    body = SliverFillRemaining(hasScrollBody: false, child: loading);
  } else if (loader.error != null && loader.items.isEmpty) {
    body = SliverFillRemaining(hasScrollBody: false, child: error());
  } else if (loader.items.isEmpty) {
    body = SliverFillRemaining(hasScrollBody: false, child: empty);
  } else {
    body = SliverPadding(
      padding: padding,
      sliver: SliverList.builder(
        itemCount: loader.items.length + (loader.hasMore ? 1 : 0),
        itemBuilder: (c, i) => i >= loader.items.length
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            : Padding(
                padding: EdgeInsets.only(bottom: itemGap),
                child: itemBuilder(c, loader.items[i]),
              ),
      ),
    );
  }
  return CustomScrollView(
    controller: controller,
    slivers: [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: leading,
        ),
      ),
      body,
    ],
  );
}

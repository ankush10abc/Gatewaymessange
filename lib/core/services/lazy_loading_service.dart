class LazyLoadingController<T> {
  final List<T> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _page = 1;

  List<T> get items => _items;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

  Future<void> loadMore(Future<List<T>> Function(int page) loader) async {
    if (_isLoading || !_hasMore) return;
    
    _isLoading = true;
    try {
      final newItems = await loader(_page);
      if (newItems.isEmpty) {
        _hasMore = false;
      } else {
        _items.addAll(newItems);
        _page++;
      }
    } finally {
      _isLoading = false;
    }
  }

  void reset() {
    _items.clear();
    _page = 1;
    _hasMore = true;
    _isLoading = false;
  }
}
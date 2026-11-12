library;

List<T> capped<T>(List<T> items, int max) =>
    items.length > max ? items.sublist(items.length - max) : items;

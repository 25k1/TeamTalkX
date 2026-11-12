import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/announcer.dart';
import '../../app/connection/connection_providers.dart';
import '../../app/platform_services.dart';
import '../../app/security/certificate_trust.dart';
import '../../app/servers/public_server_filter.dart';
import '../../app/servers/public_servers_providers.dart';
import '../../app/servers/server_list_providers.dart';
import '../../app/settings/locale_providers.dart';
import '../../app/updates/update_controller.dart';
import '../../diagnostics/log.dart';
import '../../domain/failure.dart';
import '../../domain/server_entry.dart';
import '../../l10n/l10n.dart';
import '../../ui/common/failure_report.dart';
import '../a11y/accessible_menu.dart';
import '../a11y/context_menu_row.dart';
import '../a11y/dialogs.dart';
import '../channels/main_screen.dart';
import '../common/export.dart';
import '../common/ui.dart';
import '../security/certificate_dialog.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_widgets.dart';
import 'server_details_screen.dart';
import 'server_edit_screen.dart';
import 'server_list_banners.dart';
import 'server_list_filters.dart';
import 'server_offer.dart';

extension ServerListingLabels on ServerListingType {
  String marker(AppLocalizations l10n) => switch (this) {
    ServerListingType.local => l10n.serverListingLocal,
    ServerListingType.official => l10n.serverListingOfficial,
    ServerListingType.public => l10n.serverListingPublic,
    ServerListingType.unofficial => l10n.serverListingUnofficial,
  };

  String get iconAsset => switch (this) {
    ServerListingType.local => 'assets/icons/teamtalk_yellow.png',
    ServerListingType.official => 'assets/icons/teamtalk_blue.png',
    ServerListingType.public => 'assets/icons/teamtalk_green.png',
    ServerListingType.unofficial => 'assets/icons/teamtalk_orange.png',
  };
}

@visibleForTesting
bool serverListStartupHandled = false;

@visibleForTesting
bool serverListStartupReported = false;

class ServerListScreen extends ConsumerStatefulWidget {
  const ServerListScreen({super.key});

  @override
  ConsumerState<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends ConsumerState<ServerListScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<String>? _linkSub;
  StreamSubscription<String>? _fileSub;
  final _search = TextEditingController();
  final _publicSearch = TextEditingController();
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));
  String _query = '';
  String _publicQuery = '';

  @override
  void initState() {
    super.initState();
    final deepLinks = ref.read(deepLinksProvider);
    _linkSub = deepLinks.links.listen(_handleLink);
    _fileSub = deepLinks.files.listen(_openFile);
    unawaited(_startup());
    if (!serverListStartupReported) {
      serverListStartupReported = true;
      unawaited(_reportStartupDone());
    }
  }

  Future<void> _reportStartupDone() async {
    await ref.read(serverListProvider.future);
    if (!mounted) return;
    final report = ref.read(reportStartupDoneProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(report()));
  }

  Future<void> _startup() async {
    final deepLinks = ref.read(deepLinksProvider);
    final (link, xml) = await (
      deepLinks.getInitialLink(),
      deepLinks.getInitialFile(),
    ).wait;
    if (link != null) unawaited(_handleLink(link));
    if (xml != null) unawaited(_openFile(xml));
    if (serverListStartupHandled) return;
    serverListStartupHandled = true;
    unawaited(ref.read(updateControllerProvider.notifier).checkAtStartup());
    if (link != null || xml != null) return;
    await ref.read(serverListProvider.future);
    final startup = ref.read(serverListProvider.notifier).startupServer;
    if (startup == null || !mounted) return;
    if (ref.read(connectionProvider) is! Disconnected) return;
    final (entry, index) = startup;
    appLog.i('servers', 'Connecting on startup to ${entry.host}');
    await _connect(entry, index);
  }

  Future<void> _handleLink(String url) async {
    final entry = serverFromTtLink(url);
    if (entry == null || !mounted) return;
    appLog.i('servers', 'Link to ${entry.host}:${entry.tcpPort}');
    await _offer(entry, ServerOfferSource.link);
  }

  Future<void> _openFile(String xml) async {
    if (!mounted) return;
    final entries = serversInTtFile(xml);
    if (entries.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showMessage(context.l10n.serverNoServersInFile);
      return;
    }
    if (entries.length == 1) {
      await _offer(entries.single, ServerOfferSource.file);
      return;
    }
    if (await confirmServerImport(context, entries)) await _importXml(xml);
  }

  Future<void> _offer(ServerEntry entry, ServerOfferSource source) async {
    final session = ref.read(connectionProvider);
    final current = ref.read(connectionProvider.notifier).currentEntry;
    final choice = await confirmServerOffer(
      context,
      entry: entry,
      source: source,
      connectedTo: session is Disconnected ? null : current?.displayName,
    );
    if (!mounted) return;
    switch (choice) {
      case ServerOfferChoice.connect:
        await _connect(entry, null);
      case ServerOfferChoice.save:
        await _addToMyServers(entry);
      case null:
        break;
    }
  }

  Future<void> _onCertificate(CertificateNotTrusted reason) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final failure = reason.failure;
    final trusted = await askToTrustCertificate(
      context,
      serverName: reason.entry.displayName,
      failure: failure,
    );
    if (!trusted || !mounted) return;
    await ref
        .read(certificateTrustProvider)
        .accept(failure.host, failure.port, failure.certificate);
    if (mounted) await _connect(reason.entry, reason.listIndex);
  }

  bool _matches(ServerEntry entry, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return entry.name.toLowerCase().contains(q) ||
        entry.host.toLowerCase().contains(q);
  }

  Future<void> _connect(ServerEntry entry, int? index) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final micGranted = await ref.read(permissionsProvider).requestConnect();
    if (!micGranted) {
      messenger.showMessage(
        ref.read(appLocalizationsProvider).serverMicPermissionDenied,
      );
    }
    try {
      await ref
          .read(connectionProvider.notifier)
          .connect(entry, listIndex: index);
      await navigator.push(
        MaterialPageRoute<void>(builder: (_) => const MainScreen()),
      );
    } on ConnectCancelled catch (_) {
    } on UntrustedCertificate catch (_) {
    } on Object catch (e) {
      reportFailure(ref, messenger, action: (l) => l.actionConnect, error: e);
    }
  }

  Future<void> _addServer() async {
    final entry = await pushScreenForResult<ServerEntry>(
      context,
      const ServerEditScreen(),
    );
    if (entry != null) {
      await ref.read(serverListProvider.notifier).add(entry);
      _announceSaved(entry);
    }
  }

  void _announceSaved(ServerEntry entry) {
    if (!mounted) return;
    final text = context.l10n.serverSaved(entry.displayName);
    ScaffoldMessenger.of(context).showMessage(text);
    ref.read(announcerProvider).announceShown(text);
  }

  Future<void> _editServer(ServerEntry entry, int index) async {
    final edited = await pushScreenForResult<ServerEntry>(
      context,
      ServerEditScreen(entry: entry),
    );
    if (edited != null) {
      await ref.read(serverListProvider.notifier).updateAt(index, edited);
      _announceSaved(edited);
    }
  }

  Future<void> _deleteServer(ServerEntry entry, int index) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(serverListProvider.notifier);
    await notifier.removeAt(index);
    final text = l10n.serverRemoved(entry.displayName);
    messenger.showUndo(
      text,
      undoLabel: l10n.commonUndo,
      onUndo: () => unawaited(notifier.insertAt(index, entry)),
    );
    ref.read(announcerProvider).announceShown(text);
  }

  Future<void> _addToMyServers(ServerEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final added = await ref.read(serverListProvider.notifier).importEntries([
      entry,
    ]);
    messenger.showMessage(
      added > 0
          ? ref
                .read(appLocalizationsProvider)
                .serverAddedToMine(entry.displayName)
          : ref.read(appLocalizationsProvider).serverAlreadyMine,
    );
  }

  Future<void> _exportEntries(List<ServerEntry> entries, String name) async {
    final messenger = ScaffoldMessenger.of(context);
    final passwords = await askExportPasswords(context, entries);
    if (!mounted) return;
    await exportToDownloads(
      ref,
      messenger,
      fileName: name,
      content: exportTtFile(passwords ? entries : withoutPasswords(entries)),
    );
  }

  Future<void> _exportSingle(ServerEntry entry) {
    final stem = (entry.name.isEmpty ? entry.host : entry.name).replaceAll(
      RegExp(r'[^\w\- ]'),
      '_',
    );
    return _exportEntries([entry], '${stem}_server.tt');
  }

  Future<void> _enterJoinCode() async {
    final l10n = context.l10n;
    final code = await promptText(
      context,
      title: l10n.serverEnterJoinCode,
      label: l10n.serverJoinCode,
    );
    if (code == null || code.trim().isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showMessage(l10n.serverLookingUpJoinCode);
    ServerEntry? entry;
    try {
      entry = await lookupJoinCode(code);
    } on Object catch (e, st) {
      appLog.w('servers', 'Join code lookup failed', e, st);
      entry = null;
    }
    if (!mounted) return;
    if (entry == null) {
      messenger.showMessage(l10n.serverJoinCodeNotRecognised);
      return;
    }
    await _connect(entry, null);
  }

  Future<void> _import() async {
    final typeGroup = XTypeGroup(
      label: context.l10n.serverFileTypeLabel,
      extensions: const ['tt'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final xml = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    if (mounted) await _importXml(xml);
  }

  Future<void> _importXml(String xml) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final (found, added) = await ref
        .read(serverListProvider.notifier)
        .importTtFile(xml);
    if (!mounted) return;
    final l10n = context.l10n;
    if (found == 0) {
      messenger.showMessage(l10n.serverNoServersInFile);
      return;
    }
    messenger.showMessage(
      added == 0 ? l10n.serverAllAlreadyExist : l10n.serverImported(added),
    );
  }

  Future<void> _toggleFavorite(ServerEntry entry, int? index) async {
    final notifier = ref.read(serverListProvider.notifier);
    final l10n = context.l10n;
    final announcer = ref.read(announcerProvider);
    if (index == null) {
      final added = await notifier.importEntries([
        entry.copyWith(favorite: true),
      ]);
      announcer.announce(
        added > 0
            ? l10n.serverFavoriteAdded(entry.displayName)
            : l10n.serverAlreadyMine,
      );
      return;
    }
    final favorite = !entry.favorite;
    await notifier.setFavorite(index, favorite: favorite);
    announcer.announce(
      favorite
          ? l10n.serverFavoriteAdded(entry.displayName)
          : l10n.serverFavoriteRemoved(entry.displayName),
    );
  }

  Future<void> _toggleStartup(ServerEntry entry, int index) async {
    final connect = !entry.connectOnStartup;
    await ref
        .read(serverListProvider.notifier)
        .setConnectOnStartup(index, connect: connect);
    if (!mounted) return;
    ref
        .read(announcerProvider)
        .announce(
          connect
              ? context.l10n.serverStartupOn(entry.displayName)
              : context.l10n.serverStartupOff(entry.displayName),
        );
  }

  void _showDetails(ServerEntry entry, int? index) => pushScreen(
    context,
    ServerDetailsScreen(
      entry: entry,
      index: index,
      onConnect: () {
        Navigator.of(context).pop();
        unawaited(_connect(entry, index));
      },
      onEdit: index == null ? null : () => _editServer(entry, index),
      onFavorite: () => unawaited(_toggleFavorite(entry, index)),
    ),
  );

  Future<void> _move(ServerEntry entry, _Group group, int to) async {
    await ref
        .read(serverListProvider.notifier)
        .moveWithin(group.slots, group.position, to);
    if (!mounted) return;
    ref
        .read(announcerProvider)
        .announce(
          context.l10n.serverMoved(
            entry.displayName,
            to + 1,
            group.slots.length,
          ),
        );
  }

  Future<void> _duplicate(ServerEntry entry, int index) async {
    final copyIndex = await ref
        .read(serverListProvider.notifier)
        .duplicate(index, name: context.l10n.serverCopyName(entry.displayName));
    if (copyIndex < 0 || !mounted) return;
    final copy = ref.read(serverListProvider).value![copyIndex];
    await _editServer(copy, copyIndex);
  }

  Widget _row(
    ServerEntry entry,
    int? index,
    bool busy, {
    int users = 0,
    _Group? group,
  }) {
    final l10n = context.l10n;
    final isLocal = index != null;
    final userCount = isLocal ? users : entry.userCount;
    final facts = [
      if (entry.favorite) l10n.serverFavorite,
      if (!isLocal && entry.listingType != ServerListingType.local)
        entry.listingType.marker(l10n),
      if (userCount > 0) l10n.serverUserCount(userCount),
      if (entry.encrypted) l10n.serverEncrypted,
      if (!isLocal && entry.country.isNotEmpty) entry.country,
      if (entry.connectOnStartup) l10n.serverStartupTag,
    ];
    final position = group?.position;
    final count = group?.slots.length ?? 0;
    return ContextMenuRow(
      semanticsLabel: [entry.displayName, ...facts].join(', '),
      menuTitle: entry.displayName,
      onTap: busy ? null : () => _connect(entry, index),
      actions: [
        RowAction(
          l10n.serverDetails,
          () => _showDetails(entry, index),
          icon: Icons.info_outline,
        ),
        RowAction(
          entry.favorite ? l10n.serverUnfavorite : l10n.serverMakeFavorite,
          () => unawaited(_toggleFavorite(entry, index)),
          icon: entry.favorite ? Icons.star : Icons.star_border,
        ),
        if (isLocal) ...[
          RowAction(
            entry.connectOnStartup
                ? l10n.serverStartupStop
                : l10n.serverConnectOnStartup,
            () => unawaited(_toggleStartup(entry, index)),
            icon: Icons.power_settings_new,
          ),
          if (group != null && position! > 0) ...[
            RowAction(
              l10n.serverMoveUp,
              () => unawaited(_move(entry, group, position - 1)),
              icon: Icons.arrow_upward,
            ),
            if (position > 1)
              RowAction(
                l10n.serverMoveTop,
                () => unawaited(_move(entry, group, 0)),
                icon: Icons.vertical_align_top,
              ),
          ],
          if (group != null && position! < count - 1) ...[
            RowAction(
              l10n.serverMoveDown,
              () => unawaited(_move(entry, group, position + 1)),
              icon: Icons.arrow_downward,
            ),
            if (position < count - 2)
              RowAction(
                l10n.serverMoveBottom,
                () => unawaited(_move(entry, group, count - 1)),
                icon: Icons.vertical_align_bottom,
              ),
          ],
          RowAction(
            l10n.commonEdit,
            () => _editServer(entry, index),
            icon: Icons.edit,
          ),
          RowAction(
            l10n.serverDuplicate,
            () => unawaited(_duplicate(entry, index)),
            icon: Icons.copy,
          ),
        ] else
          RowAction(
            l10n.serverAddToMine,
            () => _addToMyServers(entry),
            icon: Icons.bookmark_add,
          ),
        RowAction(
          l10n.serverExport,
          () => _exportSingle(entry),
          icon: Icons.file_upload,
        ),
        if (isLocal)
          RowAction(
            l10n.commonRemove,
            () => _deleteServer(entry, index),
            icon: Icons.delete,
          ),
      ],
      child: ListTile(
        leading: Image.asset(
          entry.listingType.iconAsset,
          width: 32,
          height: 32,
        ),
        title: Text(entry.displayName),
        subtitle: facts.isEmpty ? null : Text(facts.join(' · ')),
        trailing: group == null
            ? null
            : ReorderableDragStartListener(
                index: position!,
                child: const Icon(Icons.drag_handle),
              ),
        enabled: !busy,
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_linkSub?.cancel());
    unawaited(_fileSub?.cancel());
    _search.dispose();
    _publicSearch.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Widget _mineTab(bool busy) {
    final l10n = context.l10n;
    final filter = ref.watch(publicServerFilterProvider);
    final setFilter = ref.read(publicServerFilterProvider.notifier).set;
    final servers = ref.watch(serverListProvider).value ?? const [];
    final publicUsers = <String, int>{
      for (final p
          in ref.watch(publicServersProvider).value ?? const <ServerEntry>[])
        '${p.host.toLowerCase()}:${p.tcpPort}': p.userCount,
    };
    int usersOf(ServerEntry e) =>
        publicUsers['${e.host.toLowerCase()}:${e.tcpPort}'] ?? 0;
    final matching = filter.sortedMine([
      for (final (index, entry) in servers.indexed)
        if (_matches(entry, _query)) (entry, index),
    ]);
    final favorites = [
      for (final m in matching)
        if (m.$1.favorite) m,
    ];
    final others = [
      for (final m in matching)
        if (!m.$1.favorite) m,
    ];
    final movable = filter.mineSort == MineSort.yours && _query.isEmpty;

    Widget section(String? title, List<(ServerEntry, int)> items) {
      final slots = [for (final (_, i) in items) i];
      Widget item(int position) {
        final (entry, index) = items[position];
        return KeyedSubtree(
          key: ValueKey(index),
          child: _row(
            entry,
            index,
            busy,
            users: usersOf(entry),
            group: movable ? _Group(slots, position) : null,
          ),
        );
      }

      return SliverMainAxisGroup(
        slivers: [
          if (title != null) SliverToBoxAdapter(child: SectionHeader(title)),
          if (movable)
            SliverReorderableList(
              itemCount: items.length,
              itemBuilder: (context, position) => item(position),
              onReorderItem: (from, to) =>
                  unawaited(_move(items[from].$1, _Group(slots, from), to)),
            )
          else
            SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, position) => item(position),
            ),
        ],
      );
    }

    if (servers.isEmpty) return _emptyMine();
    return Column(
      children: [
        ServerSearchField(
          controller: _search,
          label: l10n.serverSearchMine,
          onChanged: (v) => setState(() => _query = v),
        ),
        ListTile(
          leading: const Icon(Icons.sort),
          title: Text(l10n.serverSortOrder),
          subtitle: Text(filter.mineSort.label(l10n)),
          onTap: () => pickFromMenu<MineSort>(
            context,
            title: l10n.serverSortOrder,
            options: {for (final s in MineSort.values) s: s.label(l10n)},
            selected: filter.mineSort,
            onPick: (s) => setFilter(filter.copyWith(mineSort: s)),
          ),
        ),
        Expanded(
          child: CustomScrollView(
            slivers: [
              if (matching.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l10n.serverNoneMatch(_query))),
                  ),
                ),
              if (favorites.isNotEmpty)
                section(l10n.serverFavorites, favorites),
              if (others.isNotEmpty)
                section(favorites.isNotEmpty ? l10n.serverMine : null, others),
              const SliverPadding(padding: EdgeInsets.only(bottom: 88)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyMine() {
    final l10n = context.l10n;
    Widget action(IconData icon, String label, VoidCallback onPressed) =>
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            icon: Icon(icon),
            label: Text(label),
            onPressed: onPressed,
          ),
        );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          l10n.serverNoneYetTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(l10n.serverNoneYetBody),
        const SizedBox(height: 8),
        action(Icons.public, l10n.serverBrowsePublic, () => _tabs.animateTo(1)),
        action(Icons.vpn_key, l10n.serverEnterJoinCode, _enterJoinCode),
        action(Icons.file_download, l10n.serverImportFile, _import),
        action(Icons.add, l10n.serverAdd, _addServer),
      ],
    );
  }

  Widget _publicTab(bool busy) {
    final l10n = context.l10n;
    final public = ref.watch(publicServersProvider);
    final filter = ref.watch(publicServerFilterProvider);
    final setFilter = ref.read(publicServerFilterProvider.notifier).set;
    final all = public.value ?? const <ServerEntry>[];
    final searched = [
      for (final e in all)
        if (_matches(e, _publicQuery)) e,
    ];
    final shown = filter.sorted(searched.where(filter.allows));
    final hidden = searched.length - shown.length;
    final countries = countriesOf(all);
    return Column(
      children: [
        ServerSearchField(
          controller: _publicSearch,
          label: l10n.serverSearchPublic,
          onChanged: (v) => setState(() => _publicQuery = v),
        ),
        ListTile(
          leading: const Icon(Icons.filter_list),
          title: Text(l10n.serverFilterAndSort),
          subtitle: Text(
            [
              if (filter.country.isEmpty)
                l10n.serverFilterAnyCountry
              else
                filter.country,
              if (filter.minUsers == 0)
                l10n.serverFilterAnyUsers
              else
                l10n.serverFilterAtLeastUsers(filter.minUsers),
              filter.sort.label(l10n),
            ].join(', '),
          ),
          onTap: () => showPublicFilterMenu(
            context,
            filter: filter,
            countries: countries,
            onChanged: setFilter,
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final entry in shown) _row(entry, null, busy),
              if (hidden > 0)
                ListTile(
                  leading: const Icon(Icons.filter_alt_off),
                  title: Text(l10n.serverHiddenByFilters(hidden)),
                  subtitle: Text(l10n.serverClearFilters),
                  onTap: () =>
                      setFilter(filter.copyWith(country: '', minUsers: 0)),
                ),
              if (public.isLoading)
                ListTile(
                  leading: const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text(l10n.serverLoadingPublic),
                ),
              if (public.hasError)
                ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(l10n.serverPublicLoadFailed),
                  subtitle: Text(l10n.serverDoubleTapToRetry),
                  onTap: () => ref.invalidate(publicServersProvider),
                ),
              if (!public.isLoading && !public.hasError && all.isEmpty)
                ListTile(title: Text(l10n.serverPublicNone)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final connection = ref.watch(connectionProvider);
    ref.listen(connectionProvider, (_, next) {
      if (next case Disconnected(reason: final CertificateNotTrusted reason)) {
        unawaited(_onCertificate(reason));
      }
    });
    final busy = connection is Connecting || connection is LoggingIn;
    final banner = connectionBanner(context, ref, connection);
    final update = updateBanner(context, ref, connection);
    final onMine = _tabs.index == 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.serverListTitle),
        actions: [
          if (!onMine)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.serverRefreshList,
              onPressed: () => ref.invalidate(publicServersProvider),
            ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: l10n.commonMoreOptions,
            onPressed: _moreMenu,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: l10n.serverTabMine),
            Tab(text: l10n.serverTabPublic),
          ],
        ),
      ),
      floatingActionButton: onMine
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: Text(l10n.serverAdd),
              onPressed: _addServer,
            )
          : null,
      body: Column(
        children: [
          ?banner,
          ?update,
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_mineTab(busy), _publicTab(busy)],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _moreMenu() async {
    final l10n = context.l10n;
    final action = await showAccessibleMenu<String>(
      context,
      title: l10n.commonMoreOptions,
      items: [
        MenuItemSpec('joincode', l10n.serverEnterJoinCode, icon: Icons.vpn_key),
        MenuItemSpec(
          'import',
          l10n.serverImportFile,
          icon: Icons.file_download,
        ),
        MenuItemSpec('export', l10n.serverExportAll, icon: Icons.file_upload),
        MenuItemSpec('settings', l10n.commonSettings, icon: Icons.settings),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'joincode':
        await _enterJoinCode();
      case 'import':
        await _import();
      case 'export':
        await _exportEntries(
          ref.read(serverListProvider).value ?? const [],
          'tt5servers.tt',
        );
      case 'settings':
        pushScreen(context, const SettingsScreen());
    }
  }
}

String lastConnectedText(BuildContext context, DateTime when) {
  final l10n = context.l10n;
  final local = when.toLocal();
  final time = TimeOfDay.fromDateTime(local).format(context);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  return switch (days) {
    0 => l10n.serverWhenToday(time),
    1 => l10n.serverWhenYesterday(time),
    _ => MaterialLocalizations.of(context).formatMediumDate(local),
  };
}

extension on MineSort {
  String label(AppLocalizations l10n) => switch (this) {
    MineSort.yours => l10n.serverSortYours,
    MineSort.name => l10n.serverSortName,
    MineSort.recent => l10n.serverSortRecent,
  };
}

class _Group {
  const _Group(this.slots, this.position);
  final List<int> slots;
  final int position;
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plant_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/location_provider.dart';
import '../models/app_settings.dart';
import '../models/log_entry.dart';
import '../models/plant.dart';
import '../utils/date_utils.dart';
import '../widgets/plant_image_widget.dart';
import 'add_plant_screen.dart';
import 'bulk_add_plants_screen.dart';
import 'location_list_screen.dart';
import 'plant_detail_screen.dart';
import 'settings_screen.dart';

/// 「未設定」（置き場所なし）フィルタを表す特別な値（Issue #180）
const String _unassignedLocationFilter = '__unassigned__';

class PlantListScreen extends StatefulWidget {
  const PlantListScreen({super.key});

  @override
  State<PlantListScreen> createState() => _PlantListScreenState();
}

class _PlantListScreenState extends State<PlantListScreen> {
  /// true = グリッド表示、false = リスト表示
  bool _isGridView = false;

  /// 選択中の置き場所フィルタ。null = すべて表示（Issue #180）
  String? _selectedLocationId;

  /// 名前検索の入力中かどうか（Issue #327）。
  ///
  /// 鉢数が少ないうちは検索欄が場所を取るだけなので、AppBar のアイコンから
  /// 開く方式にして、普段はリストの領域を削らない。
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 名前・品種名・置き場所名で植物を絞り込む（Issue #327）。
  List<Plant> _applySearchFilter(BuildContext context, List<Plant> plants) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return plants;

    final locations = context.read<LocationProvider>().locations;
    String locationName(String? id) {
      if (id == null) return '';
      return locations.where((l) => l.id == id).firstOrNull?.name ?? '';
    }

    return plants.where((plant) {
      final haystack = [
        plant.name,
        plant.nameReading ?? '',
        plant.variety ?? '',
        locationName(plant.locationId),
      ].join('\n').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      context.read<PlantProvider>().loadPlants();
      context.read<LocationProvider>().loadLocations();
    });
  }

  /// 置き場所フィルタのチップ行（Issue #294）。
  ///
  /// 以前は AppBar のメニュー＋適用中バナーだったが、いま何で絞り込めるのか・
  /// 何件あるのかが開くまで分からなかったため、一覧の直上に常設する。
  /// 置き場所が未登録のときは行ごと出さないので、リストの位置は変わらない。
  Widget _buildLocationFilterChips() {
    return Consumer2<LocationProvider, PlantProvider>(
      builder: (context, locationProvider, plantProvider, _) {
        final locations = locationProvider.locations;
        if (locations.isEmpty) return const SizedBox.shrink();

        // 名前検索中は検索結果に対する件数を出す（Issue #346）。
        // リストが4件に絞られているのに「すべて 12」と出ていると、
        // 絞り込みが効いているのか判断できないため。
        final allPlants = plantProvider.plants;
        final plants = _applySearchFilter(context, allPlants);
        // チップの並び自体は検索で変えない（入力のたびに未設定チップが
        // 出入りすると押したい位置がずれるため）。件数だけを検索結果に合わせる。
        final unassignedCount = plants
            .where((p) => p.locationId == null)
            .length;
        final hasUnassigned = allPlants.any((p) => p.locationId == null);

        Widget chip(String label, int count, String? value) {
          final selected = _selectedLocationId == value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text('$label $count'),
              selected: selected,
              onSelected: (_) => setState(() => _selectedLocationId = value),
            ),
          );
        }

        return SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              chip('すべて', plants.length, null),
              for (final location in locations)
                chip(
                  location.name,
                  plants.where((p) => p.locationId == location.id).length,
                  location.id,
                ),
              if (hasUnassigned)
                chip('未設定', unassignedCount, _unassignedLocationFilter),
              // 置き場所の管理画面は設定の奥にあるため、ここからも開けるようにする
              // （Issue #248 の導線をチップ行へ引き継ぐ）
              IconButton(
                icon: const Icon(Icons.home_outlined),
                tooltip: '置き場所を編集',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LocationListScreen()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// カスタム並び替え中に、置き場所フィルタが使えない理由を示す行（Issue #308）。
  ///
  /// チップ行と同じ高さにして、並び順を切り替えてもリストの位置がずれないようにする。
  Widget _buildCustomSortNotice() {
    return Consumer<LocationProvider>(
      builder: (context, locationProvider, _) {
        // 置き場所が未登録ならそもそもフィルタの話をしない
        if (locationProvider.locations.isEmpty) return const SizedBox.shrink();

        final scheme = Theme.of(context).colorScheme;
        return SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'カスタム並び替え中は置き場所で絞り込めません',
                    maxLines: 2,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 選択中の置き場所フィルタに従って植物リストを絞り込む。
  List<Plant> _applyLocationFilter(List<Plant> plants) {
    if (_selectedLocationId == null) return plants;
    if (_selectedLocationId == _unassignedLocationFilter) {
      return plants.where((p) => p.locationId == null).toList();
    }
    return plants.where((p) => p.locationId == _selectedLocationId).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '植物名・品種・置き場所で検索',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : const Text('植物一覧'),
        actions: [
          // 置き場所での絞り込みは AppBar のメニューから一覧上のチップ行へ移した
          // （Issue #294。従来の判断は Issue #251）

          // 名前検索。常設のバーにするとリスト領域を常に削るため、
          // 必要なときだけ開く方式にする（Issue #327）
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: _isSearching ? '検索を閉じる' : '植物を検索',
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
          // グリッド/リスト表示切り替えボタン
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            tooltip: _isGridView ? 'リスト表示' : 'グリッド表示',
            onPressed: () {
              setState(() {
                _isGridView = !_isGridView;
              });
            },
          ),
          // Sort order menu
          Consumer<SettingsProvider>(
            builder: (context, settingsForMenu, _) {
              return PopupMenuButton<PlantSortOrder>(
                icon: const Icon(Icons.sort),
                tooltip: '並び順',
                onSelected: (order) {
                  context.read<SettingsProvider>().setPlantSortOrder(order);
                },
                itemBuilder: (context) {
                  final currentOrder = settingsForMenu.plantSortOrder;

                  return PlantSortOrder.values.map((order) {
                    return PopupMenuItem<PlantSortOrder>(
                      value: order,
                      child: Row(
                        children: [
                          Icon(
                            _getSortOrderIcon(order),
                            size: 20,
                            color: currentOrder == order
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _getSortOrderName(order),
                              style: currentOrder == order
                                  ? TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    )
                                  : null,
                            ),
                          ),
                          if (currentOrder == order)
                            Icon(
                              Icons.check,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                        ],
                      ),
                    );
                  }).toList();
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          final isCustomSort = settings.plantSortOrder == PlantSortOrder.custom;

          return Column(
            children: [
              // 置き場所フィルタはカスタム並び替え（ドラッグ）と併用すると並び順が
              // 破損するため、カスタムソート中は適用しない。
              // ただし黙って消すと機能が無くなったように見えるため、
              // 理由を示す行に差し替える（Issue #308）
              if (isCustomSort)
                _buildCustomSortNotice()
              else
                _buildLocationFilterChips(),
              Expanded(
                child: Consumer<PlantProvider>(
                  builder: (context, plantProvider, _) {
                    if (plantProvider.isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (plantProvider.plants.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.eco_outlined,
                              size: 64,
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '植物が登録されていません',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '右下のボタンから植物を追加しましょう',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                            ),
                          ],
                        ),
                      );
                    }

                    final sortedPlants = plantProvider.getSortedPlants(
                      settings.plantSortOrder,
                      settings.customSortOrder,
                    );

                    // カスタムソート中は全体順序を保つためフィルタを適用しない
                    final displayedPlants = isCustomSort
                        ? sortedPlants
                        : _applyLocationFilter(sortedPlants);
                    // 名前検索はカスタム並び替え中も使えるようにする（Issue #327）。
                    // 検索結果の並びは元の順序をそのまま保つため、絞り込みだけを行う。
                    final searchedPlants = _applySearchFilter(
                      context,
                      displayedPlants,
                    );

                    if (_searchQuery.trim().isNotEmpty &&
                        searchedPlants.isEmpty) {
                      return Center(
                        child: Text(
                          '「$_searchQuery」に一致する植物はありません',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      );
                    }

                    // グリッド表示（カスタムソート時はリスト優先）
                    if (_isGridView && !isCustomSort) {
                      return _buildGridView(searchedPlants);
                    }

                    // 検索中は並び替えのドラッグを無効にする。絞り込まれた並びで
                    // 入れ替えると、非表示の株との相対順序が壊れるため。
                    final canReorder =
                        isCustomSort && _searchQuery.trim().isEmpty;
                    return canReorder
                        ? _buildReorderableListView(
                            context,
                            sortedPlants,
                            settings,
                          )
                        : _buildListView(searchedPlants);
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 複数の植物をまとめて登録する導線（Issue #66）
          FloatingActionButton.small(
            heroTag: 'bulkAddPlants',
            tooltip: '植物をまとめて登録',
            onPressed: () async {
              final added = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (context) => const BulkAddPlantsScreen(),
                ),
              );
              if (added == true && context.mounted) {
                await context.read<PlantProvider>().loadPlants();
              }
            },
            child: const Icon(Icons.playlist_add),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'addPlant',
            tooltip: '植物を追加',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const AddPlantScreen()),
              );
            },
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  /// 「植物を追加」FAB に最後の項目が隠れないよう確保する下部余白（Issue #262）。
  /// 一括登録FAB（small）が上に増えた分も含めている（Issue #66）。
  static const double _fabBottomInset = 140;

  Widget _buildListView(List<Plant> plants) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, _fabBottomInset),
      itemCount: plants.length,
      itemBuilder: (context, index) {
        return _PlantListTile(plant: plants[index]);
      },
    );
  }

  /// グリッド（カード）表示ビューを構築する
  Widget _buildGridView(List<Plant> plants) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, _fabBottomInset),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: plants.length,
      itemBuilder: (context, index) {
        return _PlantGridCard(plant: plants[index]);
      },
    );
  }

  Widget _buildReorderableListView(
    BuildContext context,
    List<Plant> plants,
    SettingsProvider settings,
  ) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, _fabBottomInset),
      itemCount: plants.length,
      onReorder: (oldIndex, newIndex) {
        _onReorder(context, plants, oldIndex, newIndex, settings);
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              child: child,
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final plant = plants[index];
        return Container(
          key: ValueKey(plant.id),
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: _buildReorderableListTile(plant),
        );
      },
    );
  }

  Widget _buildReorderableListTile(Plant plant) {
    return Card(
      child: ListTile(
        leading: PlantImageWidget(plant: plant),
        title: Text(plant.name),
        subtitle: _buildListSubtitle(plant),
        trailing: const Icon(Icons.drag_handle),
        onTap: () => _navigateToDetail(plant),
      ),
    );
  }

  /// 一覧行の subtitle（品種名＋水やり状態）を組み立てる（Issue #233）。
  ///
  /// 品種名・水やり状態のどちらも無い場合は null を返す。
  Widget? _buildListSubtitle(Plant plant) {
    final rows = <Widget>[
      if (plant.variety != null) Text(plant.variety!),
      _WateringStatusText(plant: plant),
      // 「置き場所ごとに並べたい」のがカスタム並び替えの主な動機なので、
      // 並び替え中も置き場所が見えるようにする（Issue #334）
      _LocationBadge(locationId: plant.locationId),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }

  void _onReorder(
    BuildContext context,
    List<Plant> plants,
    int oldIndex,
    int newIndex,
    SettingsProvider settings,
  ) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final List<String> newOrder = plants.map((p) => p.id).toList();
    final plantId = newOrder.removeAt(oldIndex);
    newOrder.insert(newIndex, plantId);

    settings.setCustomSortOrder(newOrder);
  }

  void _navigateToDetail(Plant plant) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => PlantDetailScreen(plant: plant)),
    );
  }

  String _getSortOrderName(PlantSortOrder order) {
    switch (order) {
      case PlantSortOrder.nameAsc:
        return '名前（あ→ん）';
      case PlantSortOrder.nameDesc:
        return '名前（ん→あ）';
      case PlantSortOrder.purchaseDateDesc:
        return '購入日が新しい順';
      case PlantSortOrder.purchaseDateAsc:
        return '購入日が古い順';
      case PlantSortOrder.createdAtAsc:
        return '登録日が古い順';
      case PlantSortOrder.createdAtDesc:
        return '登録日が新しい順';
      case PlantSortOrder.custom:
        return 'カスタム（ドラッグで並び替え）';
      case PlantSortOrder.varietyAsc:
        return '品種名（あ→ん）';
      case PlantSortOrder.varietyDesc:
        return '品種名（ん→あ）';
      case PlantSortOrder.nextWateringAsc:
        return '水やり予定が近い順';
    }
  }

  IconData _getSortOrderIcon(PlantSortOrder order) {
    switch (order) {
      case PlantSortOrder.nameAsc:
      case PlantSortOrder.nameDesc:
        return Icons.sort_by_alpha;
      case PlantSortOrder.purchaseDateDesc:
      case PlantSortOrder.purchaseDateAsc:
        return Icons.calendar_today;
      case PlantSortOrder.createdAtAsc:
      case PlantSortOrder.createdAtDesc:
        return Icons.access_time;
      case PlantSortOrder.custom:
        return Icons.reorder;
      case PlantSortOrder.varietyAsc:
      case PlantSortOrder.varietyDesc:
        return Icons.local_florist;
      case PlantSortOrder.nextWateringAsc:
        return Icons.water_drop;
    }
  }
}

class _PlantListTile extends StatelessWidget {
  final Plant plant;

  const _PlantListTile({required this.plant});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: PlantImageWidget(plant: plant),
        title: Text(plant.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (plant.variety != null) Text(plant.variety!),
            _WateringStatusText(plant: plant),
            // 鉢数と置き場所が増えると一覧では所在が分からなくなるため、
            // 置き場所を設定している植物にはバッジを出す（Issue #258）
            _LocationBadge(locationId: plant.locationId),
          ],
        ),
        onTap: () => _navigateToDetail(context, plant),
      ),
    );
  }

  void _navigateToDetail(BuildContext context, Plant plant) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => PlantDetailScreen(plant: plant)),
    );
  }
}

/// グリッド表示用カードウィジェット
class _PlantGridCard extends StatelessWidget {
  final Plant plant;

  const _PlantGridCard({required this.plant});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PlantDetailScreen(plant: plant),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 植物画像（カード上部 3/5 を占める）
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) => PlantImageWidget(
                      plant: plant,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  // 遅れは画像の上に出して、一覧をスクロールするだけで拾えるようにする
                  // （Issue #294）
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _OverdueBadge(plant: plant),
                  ),
                ],
              ),
            ),
            // 植物名・品種（カード下部 2/5）
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      plant.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (plant.variety != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        plant.variety!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 2),
                    _WateringStatusText(plant: plant),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 植物の次回水やり状態を表す小さなテキスト（Issue #233）。
///
/// 水やり間隔が未設定などで予定日を算出できない植物では何も表示しない。
/// 予定超過（今日以前）の場合は error 色で強調する。
/// 植物カードに置き場所を表示するバッジ（Issue #258）。
///
/// 置き場所が未設定、または参照先が削除済みの場合は何も表示しない。
class _LocationBadge extends StatelessWidget {
  final String? locationId;

  const _LocationBadge({required this.locationId});

  @override
  Widget build(BuildContext context) {
    final id = locationId;
    if (id == null) return const SizedBox.shrink();

    final locations = context.watch<LocationProvider>().locations;
    final name = locations.where((l) => l.id == id).firstOrNull?.name;
    if (name == null) return const SizedBox.shrink();

    final color = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.home_outlined, size: 13, color: color),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              name,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 予定を過ぎているケアがある植物にだけ出す遅れバッジ（Issue #294）。
///
/// 水やりだけでなく肥料・活力剤の超過も対象にする（Issue #322）。
/// 遅れているケアが1つも無い場合は何も表示しない。
class _OverdueBadge extends StatelessWidget {
  final Plant plant;

  const _OverdueBadge({required this.plant});

  @override
  Widget build(BuildContext context) {
    final overdueTypes = context.read<PlantProvider>().overdueCareTypes(
      plant.id,
    );
    if (overdueTypes.isEmpty) return const SizedBox.shrink();

    // 遅れの日数は下部の _WateringStatusText が出すため、バッジは
    // 「遅れている」ことだけを示す小さな印にとどめる（Issue #300）。
    // 文言を持たないぶん、色が判別しにくいテーマでも形で気づける（Issue #303）。
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
      child: Icon(Icons.priority_high, size: 18, color: scheme.onError),
    );
  }
}

/// 一覧行に出すケア状態の行。
///
/// 主役は次回水やり日だが、肥料・活力剤が予定日を過ぎたままの場合は
/// その種別のアイコンも並べる。以前は水やりしか見ていなかったため、
/// 肥料だけが3ヶ月遅れている株が一覧では無印になり気づけなかった
/// （Issue #322）。
class _WateringStatusText extends StatelessWidget {
  final Plant plant;

  const _WateringStatusText({required this.plant});

  static const Map<LogType, IconData> _overdueIcons = {
    LogType.fertilizer: Icons.grass,
    LogType.vitalizer: Icons.favorite,
  };

  @override
  Widget build(BuildContext context) {
    // 次回予定日は loadPlants() 完了後にキャッシュ済みのため read で十分。
    final provider = context.read<PlantProvider>();
    final next = provider.cachedNextWateringDate(plant.id);
    final overdueTypes = provider.overdueCareTypes(plant.id);
    // 水やり以外で遅れている種別（水やりの遅れは日数表示の色で分かる）
    final otherOverdue = overdueTypes
        .where((t) => t != LogType.watering)
        .toList();

    if (next == null && otherOverdue.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final today = AppDateUtils.getDateOnly(DateTime.now());
    final isOverdue =
        next != null && !AppDateUtils.getDateOnly(next).isAfter(today);
    final color = isOverdue ? scheme.error : scheme.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (next != null) ...[
          Icon(Icons.water_drop, size: 13, color: color),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              AppDateUtils.formatDateDifference(next),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        // 水やり以外の遅れは、日数を並べると行が長くなるためアイコンだけで示す
        for (final type in otherOverdue) ...[
          const SizedBox(width: 6),
          Icon(_overdueIcons[type], size: 13, color: scheme.error),
        ],
      ],
    );
  }
}

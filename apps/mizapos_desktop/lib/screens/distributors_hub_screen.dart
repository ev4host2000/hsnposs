import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mizapos_desktop/config/remote_signup_config.dart';
import 'package:mizapos_desktop/l10n/app_localizations.dart';
import 'package:mizapos_desktop/screens/distributor_reports_screens.dart';
import 'package:mizapos_desktop/screens/distributor_truck_load_screen.dart';
import 'package:mizapos_desktop/screens/distributor_truck_unload_screen.dart';
import 'package:mizapos_desktop/screens/distributor_truck_movements_screen.dart';
import 'package:mizapos_desktop/screens/field_expenses_screen.dart';
import 'package:mizapos_desktop/screens/field_orders_screen.dart';
import 'package:mizapos_desktop/screens/field_returns_screen.dart';
import 'package:mizapos_desktop/services/accounting_service.dart';
import 'package:mizapos_desktop/services/field_expenses_api.dart';
import 'package:mizapos_desktop/services/field_orders_api.dart';
import 'package:mizapos_desktop/services/field_orders_approval_service.dart';
import 'package:mizapos_desktop/services/field_returns_api.dart';
import 'package:mizapos_desktop/services/field_truck_stock_sync_service.dart';
import 'package:mizapos_desktop/services/store_settings_ui_prefs.dart';
import 'package:mizapos_desktop/screens/shared/ui_style_tokens.dart';
import 'package:mizapos_desktop/widgets/distributors_hub_ui.dart';

class DistributorsHubScreen extends StatefulWidget {
  const DistributorsHubScreen({
    super.key,
    required this.accountingService,
    required this.taxPercent,
    required this.currencyCode,
    required this.currencyParts,
    required this.canReviewFieldOrders,
    this.initialPendingOrdersCount = 0,
    this.onPendingOrdersMayHaveChanged,
    this.buildInvoicePdfBytesForPreview,
  });

  final AccountingService accountingService;
  final double taxPercent;
  final String currencyCode;
  final int currencyParts;
  final bool canReviewFieldOrders;
  final int initialPendingOrdersCount;
  final VoidCallback? onPendingOrdersMayHaveChanged;
  final Future<Uint8List?> Function({
    required String invoiceId,
    required bool isSale,
    required BuildContext previewContext,
  })? buildInvoicePdfBytesForPreview;

  @override
  State<DistributorsHubScreen> createState() => _DistributorsHubScreenState();
}

class _DistributorsHubScreenState extends State<DistributorsHubScreen> {
  late int _pendingCount;
  late int _pendingExpensesCount;
  late int _pendingReturnsCount;
  bool _statsLoading = true;
  int _distributorCount = 0;
  int _movementCount = 0;

  @override
  void initState() {
    super.initState();
    _pendingCount = widget.initialPendingOrdersCount;
    _pendingExpensesCount = 0;
    _pendingReturnsCount = 0;
    _loadStats();
  }

  bool get _serverEnabled => RemoteSignupConfig.activationServerEnabled;

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final users = await widget.accountingService.listUsers();
      final distributors = users.where(
        (u) => (u['role'] ?? '').toString().toLowerCase() == 'distributor',
      );
      final truck = FieldTruckStockSyncService(
        accountingService: widget.accountingService,
      );
      final movements = await truck.listMovements(limit: 500);
      if (!mounted) return;
      setState(() {
        _distributorCount = distributors.length;
        _movementCount = movements.length;
        _statsLoading = false;
      });
      await _refreshPendingCount();
      await _refreshPendingExpensesCount();
      await _refreshPendingReturnsCount();
    } on Object {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  Future<void> _refreshPendingCount() async {
    if (!_serverEnabled || !widget.canReviewFieldOrders) return;
    try {
      final approval = FieldOrdersApprovalService(
        accountingService: widget.accountingService,
      );
      final api = FieldOrdersApi.tryConfigured();
      final creds = await approval.remoteCredentials();
      if (api == null || creds == null || !mounted) return;
      final items = await api.fetchPending(
        organizationId: creds.organizationId,
        email: creds.email,
      );
      if (!mounted) return;
      setState(() => _pendingCount = items.length);
    } on Object {
      /* optional */
    }
  }

  Future<void> _refreshPendingExpensesCount() async {
    if (!_serverEnabled || !widget.canReviewFieldOrders) return;
    try {
      final approval = FieldOrdersApprovalService(
        accountingService: widget.accountingService,
      );
      final api = FieldExpensesApi.tryConfigured();
      final creds = await approval.remoteCredentials();
      if (api == null || creds == null || !mounted) return;
      final items = await api.fetchPending(
        organizationId: creds.organizationId,
        email: creds.email,
      );
      if (!mounted) return;
      setState(() => _pendingExpensesCount = items.length);
    } on Object {
      /* optional */
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  bool _guardAccess(AppLocalizations loc) {
    if (!_serverEnabled) {
      _snack(loc.fieldOrdersUnavailable, isError: true);
      return false;
    }
    if (!widget.canReviewFieldOrders) {
      _snack(loc.fieldOrdersReviewerLoginRequired, isError: true);
      return false;
    }
    return true;
  }

  Future<void> _openFieldOrders() async {
    if (!_guardAccess(AppLocalizations.of(context))) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FieldOrdersScreen(
          accountingService: widget.accountingService,
          taxPercent: widget.taxPercent,
          currencyCode: widget.currencyCode,
          currencyParts: widget.currencyParts,
          buildInvoicePdfBytesForPreview:
              widget.buildInvoicePdfBytesForPreview,
        ),
      ),
    );
    widget.onPendingOrdersMayHaveChanged?.call();
    await _loadStats();
  }

  Future<void> _openTruckMovements() async {
    if (!_guardAccess(AppLocalizations.of(context))) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DistributorTruckMovementsScreen(
          accountingService: widget.accountingService,
        ),
      ),
    );
    await _loadStats();
  }

  Future<void> _openTruckUnload() async {
    if (!_guardAccess(AppLocalizations.of(context))) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DistributorTruckUnloadScreen(
          accountingService: widget.accountingService,
          currencyCode: widget.currencyCode,
          currencyParts: widget.currencyParts,
        ),
      ),
    );
    await _loadStats();
  }

  Future<void> _openTruckLoad() async {
    if (!_guardAccess(AppLocalizations.of(context))) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DistributorTruckLoadScreen(
          accountingService: widget.accountingService,
          currencyCode: widget.currencyCode,
          currencyParts: widget.currencyParts,
          taxPercent: widget.taxPercent,
          buildInvoicePdfBytesForPreview:
              widget.buildInvoicePdfBytesForPreview,
        ),
      ),
    );
    await _loadStats();
  }

  Future<void> _openMovementsReport() async {
    if (!_guardAccess(AppLocalizations.of(context))) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DistributorMovementsReportScreen(
          accountingService: widget.accountingService,
        ),
      ),
    );
  }

  Future<void> _openSummaryReport() async {
    if (!_guardAccess(AppLocalizations.of(context))) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DistributorSummaryReportScreen(
          accountingService: widget.accountingService,
        ),
      ),
    );
  }

  Future<void> _openTruckStockReport() async {
    if (!_guardAccess(AppLocalizations.of(context))) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DistributorTruckStockReportScreen(
          accountingService: widget.accountingService,
        ),
      ),
    );
  }

  Future<void> _openVarianceReport() async {
    if (!_guardAccess(AppLocalizations.of(context))) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DistributorTruckVarianceReportScreen(
          accountingService: widget.accountingService,
        ),
      ),
    );
  }

  Future<void> _openFieldExpensesReport() async {
    if (!_guardAccess(AppLocalizations.of(context))) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DistributorFieldExpensesReportScreen(
          accountingService: widget.accountingService,
          currencyCode: widget.currencyCode,
          currencyParts: widget.currencyParts,
        ),
      ),
    );
  }

  Future<void> _openFieldReturnsReport() async {
    if (!_guardAccess(AppLocalizations.of(context))) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DistributorFieldReturnsReportScreen(
          accountingService: widget.accountingService,
          currencyCode: widget.currencyCode,
          currencyParts: widget.currencyParts,
        ),
      ),
    );
  }

  Future<void> _refreshPendingReturnsCount() async {
    if (!_serverEnabled || !widget.canReviewFieldOrders) return;
    try {
      final approval = FieldOrdersApprovalService(
        accountingService: widget.accountingService,
      );
      final api = FieldReturnsApi.tryConfigured();
      final creds = await approval.remoteCredentials();
      if (api == null || creds == null || !mounted) return;
      final items = await api.fetchPending(
        organizationId: creds.organizationId,
        email: creds.email,
      );
      if (!mounted) return;
      setState(() => _pendingReturnsCount = items.length);
    } on Object {
      /* optional */
    }
  }

  Future<void> _openFieldReturns() async {
    if (!_guardAccess(AppLocalizations.of(context))) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FieldReturnsScreen(
          accountingService: widget.accountingService,
          currencyCode: widget.currencyCode,
          currencyParts: widget.currencyParts,
        ),
      ),
    );
    await _loadStats();
  }

  Future<void> _openReturnsHub() async {
    if (!_guardAccess(AppLocalizations.of(context))) return;
    final loc = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                loc.distributorReturns,
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFEE2E2),
                child: Icon(Icons.assignment_return_rounded,
                    color: Color(0xFFDC2626)),
              ),
              title: Text(loc.menuFieldReturns),
              subtitle: Text(loc.distributorsHubReturnsCustomerDesc),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_openFieldReturns());
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFEE2E2),
                child: Icon(Icons.local_shipping_outlined,
                    color: Color(0xFFDC2626)),
              ),
              title: Text(loc.distributorTruckEmptyAction),
              subtitle: Text(loc.distributorsHubReturnsEmptyTruckDesc),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_openTruckUnload());
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openFieldExpenses() async {
    if (!_guardAccess(AppLocalizations.of(context))) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FieldExpensesScreen(
          accountingService: widget.accountingService,
          currencyCode: widget.currencyCode,
          currencyParts: widget.currencyParts,
        ),
      ),
    );
    await _loadStats();
  }

  Future<void> _openHubNotes() async {
    final loc = AppLocalizations.of(context);
    final prefs = await loadStoreUiPreferences();
    if (!mounted) return;
    final ctrl = TextEditingController(text: prefs.quickScratchpadNotes);
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final scheme = Theme.of(dialogContext).colorScheme;
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.edit_note_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(loc.distributorsHubNotesTitle)),
              ],
            ),
            content: SizedBox(
              width: 460,
              height: 300,
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.multiline,
                maxLines: null,
                expands: true,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  alignLabelWithHint: true,
                  hintText: loc.homeQuickNotesHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(loc.cancel),
              ),
              FilledButton(
                onPressed: () async {
                  var t = ctrl.text;
                  if (t.length > 12000) t = t.substring(0, 12000);
                  await patchStoreUiPreferences(
                    (cur) => cur.copyWith(quickScratchpadNotes: t),
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  if (!mounted) return;
                  _snack(loc.homeQuickNotesSaved);
                },
                child: Text(loc.save),
              ),
            ],
          );
        },
      );
    } finally {
      ctrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final statValue = _statsLoading ? '…' : null;

    return Scaffold(
      backgroundColor: ModuleScreenChrome.neutralBody,
      appBar: DistributorsGradientAppBar(
        title: loc.menuDistributors,
        subtitle: loc.distributorsHubSubtitle,
        actions: [
          IconButton(
            tooltip: loc.fieldOrdersRefresh,
            onPressed: _statsLoading ? null : _loadStats,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentW = math.min(constraints.maxWidth - 32, 1140.0);
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: contentW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: DistributorsHeroBanner(
                      badgeLabel: loc.distributorsHubHeroBadge,
                      title: loc.distributorsHubHeroTitle,
                      body: loc.distributorsHubHeroBody,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      runAlignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        DistributorsStatCard(
                          icon: Icons.groups_rounded,
                          label: loc.distributorsHubStatDistributors,
                          value: statValue ?? '$_distributorCount',
                          accentColor: DistributorsHubPalette.statIndigo,
                          onTap: _statsLoading ? null : _openTruckLoad,
                        ),
                        DistributorsStatCard(
                          icon: Icons.pending_actions_rounded,
                          label: loc.distributorsHubStatPending,
                          value: statValue ?? '$_pendingCount',
                          accentColor: DistributorsHubPalette.statAmber,
                          onTap: _statsLoading ? null : _openFieldOrders,
                        ),
                        DistributorsStatCard(
                          icon: Icons.swap_horiz_rounded,
                          label: loc.distributorsHubStatMovements,
                          value: statValue ?? '$_movementCount',
                          accentColor: DistributorsHubPalette.statEmerald,
                          onTap: _statsLoading ? null : _openTruckMovements,
                        ),
                        DistributorsReportsDropdownCard(
                          title: loc.distributorsHubSectionReports,
                          hint: loc.distributorsHubReportsDropdownHint,
                          accentColor: DistributorsHubPalette.statViolet,
                          items: [
                            (
                              value: 'movements',
                              label: loc.distributorsHubReportMovementsTitle,
                              onSelect: _openMovementsReport,
                            ),
                            (
                              value: 'summary',
                              label: loc.distributorsHubReportSummaryTitle,
                              onSelect: _openSummaryReport,
                            ),
                            (
                              value: 'truck_stock',
                              label: loc.distributorsHubReportTruckStockTitle,
                              onSelect: _openTruckStockReport,
                            ),
                            (
                              value: 'variance',
                              label: loc.distributorsHubReportVarianceTitle,
                              onSelect: _openVarianceReport,
                            ),
                            (
                              value: 'field_expenses',
                              label: loc.distributorsHubReportFieldExpensesTitle,
                              onSelect: _openFieldExpensesReport,
                            ),
                            (
                              value: 'field_returns',
                              label: loc.distributorsHubReportFieldReturnsTitle,
                              onSelect: _openFieldReturnsReport,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: DistributorsSectionHeader(
                      title: loc.distributorsHubSectionOperations,
                      subtitle: loc.distributorsHubSectionOperationsSub,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, inner) {
                        final cols = inner.maxWidth >= 920
                            ? 3
                            : (inner.maxWidth >= 620 ? 2 : 1);
                        const gap = 14.0;
                        const boxH = 196.0;
                        final boxW = cols == 1
                            ? inner.maxWidth - 32
                            : (inner.maxWidth - 32 - gap * (cols - 1)) / cols;

                        Widget opBox({
                          required List<Color> gradient,
                          required IconData icon,
                          required String title,
                          required String subtitle,
                          required VoidCallback? onTap,
                          int? badge,
                          bool busy = false,
                        }) {
                          return SizedBox(
                            width: boxW,
                            height: boxH,
                            child: DistributorsOperationBox(
                              gradient: gradient,
                              icon: icon,
                              title: title,
                              subtitle: subtitle,
                              onTap: onTap,
                              badge: badge,
                              busy: busy,
                            ),
                          );
                        }

                        final grid = Wrap(
                          alignment: WrapAlignment.start,
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            opBox(
                              gradient: DistributorsHubPalette.loadTruck,
                              icon: Icons.inventory_2_rounded,
                              title: loc.menuLoadDistributorTruck,
                              subtitle: loc.distributorsHubLoadDesc,
                              onTap: _openTruckLoad,
                            ),
                            opBox(
                              gradient: DistributorsHubPalette.fieldOrders,
                              icon: Icons.fact_check_rounded,
                              title: loc.menuFieldOrders,
                              subtitle: loc.distributorsHubFieldOrdersDesc,
                              badge: _pendingCount > 0 ? _pendingCount : null,
                              onTap: _openFieldOrders,
                            ),
                            opBox(
                              gradient: DistributorsHubPalette.movements,
                              icon: Icons.local_shipping_rounded,
                              title: loc.menuDistributorTruckMovements,
                              subtitle: loc.distributorsHubMovementsDesc,
                              onTap: _openTruckMovements,
                            ),
                            opBox(
                              gradient: DistributorsHubPalette.expenses,
                              icon: Icons.payments_rounded,
                              title: loc.menuFieldExpenses,
                              subtitle: loc.distributorsHubFieldExpensesDesc,
                              badge: _pendingExpensesCount > 0
                                  ? _pendingExpensesCount
                                  : null,
                              onTap: _openFieldExpenses,
                            ),
                            opBox(
                              gradient: DistributorsHubPalette.returns,
                              icon: Icons.assignment_return_rounded,
                              title: loc.distributorReturns,
                              subtitle: loc.distributorsHubReturnsDesc,
                              badge: _pendingReturnsCount > 0
                                  ? _pendingReturnsCount
                                  : null,
                              onTap: _openReturnsHub,
                            ),
                            opBox(
                              gradient: DistributorsHubPalette.notes,
                              icon: Icons.edit_note_rounded,
                              title: loc.distributorsHubNotesTitle,
                              subtitle: loc.distributorsHubNotesDesc,
                              onTap: _openHubNotes,
                            ),
                          ],
                        );

                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: grid,
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: DistributorsInternetNotice(
                      title: loc.distributorsHubInternetNoticeTitle,
                      body: loc.distributorsHubInternetNoticeBody,
                      desktopLabel: loc.distributorsHubSyncDesktop,
                      serverLabel: loc.distributorsHubSyncServer,
                      mobileLabel: loc.distributorsHubSyncMobile,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

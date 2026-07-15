import 'package:mizapos_desktop/services/cloud/sync/cash_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/expense_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/partners_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_sync_constants.dart';

/// Master sync entity identifiers — catalog, partners, cash, expense, transactions.
class MasterSyncConstants {
  MasterSyncConstants._();

  static List<String> get allSyncEntityTypes => [
        ...PartnersSyncConstants.catalogEntityTypes,
        ...PartnersSyncConstants.partnerEntityTypes,
        CashSyncConstants.entityType,
        ExpenseSyncConstants.entityType,
        ...TransactionSyncConstants.transactionEntityTypes,
      ];
}

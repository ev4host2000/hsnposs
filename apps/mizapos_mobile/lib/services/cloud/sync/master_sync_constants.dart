import 'package:mizapos_mobile/services/cloud/sync/partners_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_sync_constants.dart';

/// Master sync entity identifiers — catalog, partners, transactions (when registered).
class MasterSyncConstants {
  MasterSyncConstants._();

  static List<String> get allSyncEntityTypes => [
        ...PartnersSyncConstants.catalogEntityTypes,
        ...PartnersSyncConstants.partnerEntityTypes,
        ...TransactionSyncConstants.transactionEntityTypes,
      ];
}

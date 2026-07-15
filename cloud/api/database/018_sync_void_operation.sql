ALTER TABLE sync_changelog DROP CONSTRAINT IF EXISTS chk_sync_changelog_operation;
ALTER TABLE sync_changelog ADD CONSTRAINT chk_sync_changelog_operation CHECK (operation IN ('create', 'update', 'delete', 'cancel', 'post', 'resolved', 'void'));
ALTER TABLE sync_queue DROP CONSTRAINT IF EXISTS chk_sync_queue_operation;
ALTER TABLE sync_queue ADD CONSTRAINT chk_sync_queue_operation CHECK (operation IN ('create', 'update', 'delete', 'cancel', 'post', 'void'));

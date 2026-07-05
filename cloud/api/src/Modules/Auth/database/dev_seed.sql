-- Miza Cloud Auth — dev/test seed (run after main database migrations)
-- Password for owner@store.com: MizaTest123!

BEGIN;

INSERT INTO companies (id, name, status, default_currency_code, default_locale)
VALUES (
    '550e8400-e29b-41d4-a716-446655440000',
    'Demo Store',
    'active',
    'SAR',
    'ar'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO branches (id, company_id, code, name, is_default, status)
VALUES (
    '660e8400-e29b-41d4-a716-446655440001',
    '550e8400-e29b-41d4-a716-446655440000',
    'MAIN',
    'Main Branch',
    true,
    'active'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO users (
    id, company_id, default_branch_id, username, email, full_name,
    password_hash, role, account_status
)
VALUES (
    '990e8400-e29b-41d4-a716-446655440004',
    '550e8400-e29b-41d4-a716-446655440000',
    '660e8400-e29b-41d4-a716-446655440001',
    'owner@store.com',
    'owner@store.com',
    'أحمد محمد',
    '$2y$10$GMtL.BL8pQlZnNgloC/RIehY/xINxYBEVAGLWjSpo44j6n/BJ3mxa',
    'owner',
    'active'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO user_branch_access (user_id, branch_id, company_id)
VALUES (
    '990e8400-e29b-41d4-a716-446655440004',
    '660e8400-e29b-41d4-a716-446655440001',
    '550e8400-e29b-41d4-a716-446655440000'
)
ON CONFLICT (user_id, branch_id) DO NOTHING;

INSERT INTO devices (
    id, company_id, installation_id, device_fingerprint, platform,
    device_name, os_name, status
)
VALUES (
    '770e8400-e29b-41d4-a716-446655440002',
    '550e8400-e29b-41d4-a716-446655440000',
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    'sha256:test-fingerprint',
    'android',
    'Samsung A54',
    'Android 14',
    'active'
)
ON CONFLICT (id) DO NOTHING;

COMMIT;

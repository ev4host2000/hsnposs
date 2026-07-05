-- =============================================================================
-- Miza Cloud — 004_seed_data.sql
-- Reference / bootstrap data — subscription plans only (no tenant data)
-- Safe to re-run: uses ON CONFLICT DO NOTHING
-- =============================================================================

BEGIN;

INSERT INTO subscription_plans (id, code, name, max_devices, max_branches, features_json, is_active)
VALUES
    (
        'a0000001-0000-4000-8000-000000000001',
        'trial',
        'Trial — 14 days',
        2,
        1,
        '{"sync": true, "max_users": 3, "trial_days": 14}'::jsonb,
        true
    ),
    (
        'a0000001-0000-4000-8000-000000000002',
        'starter',
        'Starter',
        3,
        1,
        '{"sync": true, "max_users": 5, "reports": "basic"}'::jsonb,
        true
    ),
    (
        'a0000001-0000-4000-8000-000000000003',
        'business',
        'Business',
        10,
        5,
        '{"sync": true, "max_users": 25, "reports": "full", "multi_branch": true}'::jsonb,
        true
    ),
    (
        'a0000001-0000-4000-8000-000000000004',
        'enterprise',
        'Enterprise',
        50,
        NULL,
        '{"sync": true, "max_users": null, "reports": "full", "multi_branch": true, "priority_support": true}'::jsonb,
        true
    ),
    (
        'a0000001-0000-4000-8000-000000000005',
        'distributor_cloud',
        'Distributor Cloud',
        100,
        NULL,
        '{"sync": true, "distributor_mode": true, "max_distributor_seats": 50}'::jsonb,
        true
    )
ON CONFLICT (code) DO NOTHING;

COMMIT;

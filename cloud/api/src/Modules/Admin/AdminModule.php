<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Admin;

use MizaCloud\Core\Config\Config;
use MizaCloud\Core\Container\Container;
use MizaCloud\Core\Database\Connection;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Core\Mail\SmtpMailer;
use MizaCloud\Core\Modules\ModuleInterface;
use MizaCloud\Core\Router\Router;
use MizaCloud\Modules\Admin\Controllers\AdminController;
use MizaCloud\Modules\Admin\Repositories\AdminBetaRepository;
use MizaCloud\Modules\Admin\Repositories\AdminMonitoringRepository;
use MizaCloud\Modules\Admin\Repositories\AdminObservabilityRepository;
use MizaCloud\Modules\Admin\Repositories\AdminRepository;
use MizaCloud\Modules\Admin\Repositories\AdminSyncRepository;
use MizaCloud\Modules\Admin\Repositories\OpsAuditRepository;
use MizaCloud\Modules\Admin\Services\AdminService;
use MizaCloud\Modules\Admin\Services\OpsAuditService;
use MizaCloud\Modules\Admin\Services\OpsAuditWriter;
use MizaCloud\Modules\Admin\Support\BetaApprovalEmailBuilder;
use MizaCloud\Modules\Admin\Support\PlatformAdminBearer;
use MizaCloud\Modules\Admin\Support\WelcomeCardBuilder;
use MizaCloud\Modules\Admin\Validators\CreateTenantValidator;
use MizaCloud\Modules\Auth\Repositories\AuthRepository;
use MizaCloud\Modules\Auth\Services\JwtService;

final class AdminModule implements ModuleInterface
{
    public function name(): string
    {
        return 'admin';
    }

    public function register(Container $container): void
    {
        $container->singleton(PlatformAdminBearer::class, static fn ($c) => new PlatformAdminBearer(
            $c->get(JwtService::class),
            $c->get(AuthRepository::class),
        ));

        $container->singleton(AdminRepository::class, static fn ($c) => new AdminRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(AdminSyncRepository::class, static fn ($c) => new AdminSyncRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(AdminObservabilityRepository::class, static fn ($c) => new AdminObservabilityRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(AdminMonitoringRepository::class, static fn ($c) => new AdminMonitoringRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(OpsAuditRepository::class, static fn ($c) => new OpsAuditRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(OpsAuditWriter::class, static function ($c) {
            $writer = new OpsAuditWriter(
                $c->get(OpsAuditRepository::class),
                $c->get(Config::class),
            );
            OpsAuditWriter::setInstance($writer);

            return $writer;
        });

        $container->singleton(OpsAuditService::class, static fn ($c) => new OpsAuditService(
            $c->get(OpsAuditRepository::class),
            $c->get(PlatformAdminBearer::class),
            $c->get(Config::class),
            $c->get(OpsAuditWriter::class),
        ));

        $container->singleton(AdminBetaRepository::class, static fn ($c) => new AdminBetaRepository(
            $c->get(Connection::class),
        ));

        $container->singleton(CreateTenantValidator::class, static fn () => new CreateTenantValidator());

        $container->singleton(WelcomeCardBuilder::class, static fn () => new WelcomeCardBuilder());

        $container->singleton(BetaApprovalEmailBuilder::class, static fn () => new BetaApprovalEmailBuilder());

        $container->singleton(SmtpMailer::class, static fn ($c) => new SmtpMailer(
            $c->get(Config::class),
        ));

        $container->singleton(AdminService::class, static fn ($c) => new AdminService(
            repository: $c->get(AdminRepository::class),
            syncRepository: $c->get(AdminSyncRepository::class),
            observabilityRepository: $c->get(AdminObservabilityRepository::class),
            monitoringRepository: $c->get(AdminMonitoringRepository::class),
            betaRepository: $c->get(AdminBetaRepository::class),
            bearer: $c->get(PlatformAdminBearer::class),
            jwt: $c->get(JwtService::class),
            createTenantValidator: $c->get(CreateTenantValidator::class),
            welcomeCard: $c->get(WelcomeCardBuilder::class),
            approvalEmail: $c->get(BetaApprovalEmailBuilder::class),
            mailer: $c->get(SmtpMailer::class),
            config: $c->get(Config::class),
            authRepository: $c->get(AuthRepository::class),
            auditWriter: $c->get(OpsAuditWriter::class),
        ));

        $container->singleton(AdminController::class, static fn ($c) => new AdminController(
            $c->get(ResponseBuilder::class),
            $c->get(AdminService::class),
            $c->get(OpsAuditService::class),
        ));
    }

    public function routes(Router $router): void
    {
        $controller = AdminController::class;

        foreach ($this->prefixes() as $prefix) {
            $router->post("{$prefix}/auth/login", [$controller, 'login']);
            $router->post("{$prefix}/auth/logout", [$controller, 'logout']);
            $router->get("{$prefix}/me", [$controller, 'me']);
            $router->get("{$prefix}/dashboard", [$controller, 'dashboardOverview']);
            $router->get("{$prefix}/plans", [$controller, 'listPlans']);
            $router->get("{$prefix}/companies", [$controller, 'listCompanies']);
            $router->post("{$prefix}/companies", [$controller, 'createTenant']);
            $router->get("{$prefix}/companies/{id}", [$controller, 'getCompany']);
            $router->get("{$prefix}/companies/{id}/welcome-card", [$controller, 'welcomeCard']);
            $router->patch("{$prefix}/companies/{id}/status", [$controller, 'updateCompanyStatus']);
            $router->delete("{$prefix}/companies/{id}", [$controller, 'deleteCompany']);
            $router->patch("{$prefix}/companies/{id}/subscription", [$controller, 'updateCompanySubscription']);
            $router->patch("{$prefix}/companies/{id}/subscription/extend", [$controller, 'extendCompanySubscription']);
            $router->post("{$prefix}/companies/{id}/reset-password", [$controller, 'resetOwnerPassword']);
            $router->get("{$prefix}/signup-requests", [$controller, 'listSignupRequests']);
            $router->post("{$prefix}/signup-requests/{id}/approve", [$controller, 'approveSignupRequest']);
            $router->post("{$prefix}/signup-requests/{id}/reject", [$controller, 'rejectSignupRequest']);
            $router->get("{$prefix}/vouchers", [$controller, 'listVouchers']);
            $router->post("{$prefix}/vouchers", [$controller, 'createVoucher']);
            $router->get("{$prefix}/companies/{id}/devices", [$controller, 'listDevices']);
            $router->get("{$prefix}/companies/{id}/sync-health", [$controller, 'companySyncHealth']);
            $router->get("{$prefix}/sync/overview", [$controller, 'syncOverview']);
            $router->get("{$prefix}/sync/failures", [$controller, 'listSyncFailures']);
            $router->get("{$prefix}/sync/conflicts", [$controller, 'listSyncConflicts']);
            $router->get("{$prefix}/observability/overview", [$controller, 'observabilityOverview']);
            $router->get("{$prefix}/monitoring/overview", [$controller, 'monitoringOverview']);
            $router->get("{$prefix}/audit-logs", [$controller, 'listAuditLogs']);
            $router->get("{$prefix}/audit-events", [$controller, 'listAuditEvents']);
            $router->get("{$prefix}/audit-events/export", [$controller, 'exportAuditEvents']);
            $router->get("{$prefix}/audit-events/alerts", [$controller, 'auditAlerts']);
            $router->get("{$prefix}/audit-events/retention", [$controller, 'getAuditRetention']);
            $router->patch("{$prefix}/audit-events/retention", [$controller, 'updateAuditRetention']);
            $router->post("{$prefix}/audit-events/retention/run", [$controller, 'runAuditRetention']);
            $router->get("{$prefix}/audit-events/{id}", [$controller, 'getAuditEvent']);
            $router->patch("{$prefix}/audit-events/{id}", [$controller, 'mutateAuditEventBlocked']);
            $router->delete("{$prefix}/audit-events/{id}", [$controller, 'mutateAuditEventBlocked']);
            $router->post("{$prefix}/devices/{id}/revoke", [$controller, 'revokeDevice']);
        }
    }

    /** @return list<string> */
    private function prefixes(): array
    {
        return ['/v1/admin', '/admin'];
    }
}

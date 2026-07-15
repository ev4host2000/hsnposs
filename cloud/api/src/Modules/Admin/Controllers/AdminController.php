<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Admin\Controllers;

use MizaCloud\Core\Exceptions\HttpException;
use MizaCloud\Core\Http\Controller;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Modules\Admin\Services\AdminService;
use MizaCloud\Modules\Admin\Services\OpsAuditService;

final class AdminController extends Controller
{
    public function __construct(
        ResponseBuilder $responses,
        private readonly AdminService $service,
        private readonly OpsAuditService $auditService,
    ) {
        parent::__construct($responses);
    }

    public function login(Request $request): Response
    {
        $data = $this->service->login($this->jsonBody($request), $request);

        return $this->responses->success($data);
    }

    public function logout(Request $request): Response
    {
        $data = $this->service->logout($request);

        return $this->responses->success($data);
    }

    public function me(Request $request): Response
    {
        $data = $this->service->me($request);

        return $this->responses->success($data);
    }

    public function dashboardOverview(Request $request): Response
    {
        $data = $this->service->dashboardOverview($request);

        return $this->responses->success($data);
    }

    public function listCompanies(Request $request): Response
    {
        $data = $this->service->listCompanies($request);

        return $this->responses->success($data);
    }

    public function getCompany(Request $request): Response
    {
        $companyId = (string) $request->attribute('id', '');
        $data = $this->service->getCompany($request, $companyId);

        return $this->responses->success($data);
    }

    public function listDevices(Request $request): Response
    {
        $companyId = (string) $request->attribute('id', '');
        $data = $this->service->listDevices($request, $companyId);

        return $this->responses->success($data);
    }

    public function listPlans(Request $request): Response
    {
        $data = $this->service->listPlans($request);

        return $this->responses->success($data);
    }

    public function createTenant(Request $request): Response
    {
        $data = $this->service->createTenant($request, $this->jsonBody($request));

        return $this->responses->success($data, status: 201);
    }

    public function welcomeCard(Request $request): Response
    {
        $companyId = (string) $request->attribute('id', '');
        $data = $this->service->welcomeCard($request, $companyId);

        return $this->responses->success($data);
    }

    public function updateCompanyStatus(Request $request): Response
    {
        $companyId = (string) $request->attribute('id', '');
        $data = $this->service->updateCompanyStatus($request, $companyId, $this->jsonBody($request));

        return $this->responses->success($data);
    }

    public function deleteCompany(Request $request): Response
    {
        $companyId = (string) $request->attribute('id', '');
        $data = $this->service->deleteCompany($request, $companyId, $this->jsonBody($request));

        return $this->responses->success($data);
    }

    public function updateCompanySubscription(Request $request): Response
    {
        $companyId = (string) $request->attribute('id', '');
        $data = $this->service->updateCompanySubscription($request, $companyId, $this->jsonBody($request));

        return $this->responses->success($data);
    }

    public function resetOwnerPassword(Request $request): Response
    {
        $companyId = (string) $request->attribute('id', '');
        $data = $this->service->resetOwnerPassword($request, $companyId, $this->jsonBody($request));

        return $this->responses->success($data);
    }

    public function syncOverview(Request $request): Response
    {
        $data = $this->service->syncOverview($request);

        return $this->responses->success($data);
    }

    public function companySyncHealth(Request $request): Response
    {
        $companyId = (string) $request->attribute('id', '');
        $data = $this->service->companySyncHealth($request, $companyId);

        return $this->responses->success($data);
    }

    public function listSyncFailures(Request $request): Response
    {
        $data = $this->service->listSyncFailures($request);

        return $this->responses->success($data);
    }

    public function listSyncConflicts(Request $request): Response
    {
        $data = $this->service->listSyncConflicts($request);

        return $this->responses->success($data);
    }

    public function observabilityOverview(Request $request): Response
    {
        $data = $this->service->observabilityOverview($request);

        return $this->responses->success($data);
    }

    public function monitoringOverview(Request $request): Response
    {
        $data = $this->service->monitoringOverview($request);

        return $this->responses->success($data);
    }

    public function listAuditLogs(Request $request): Response
    {
        $data = $this->service->listAuditLogs($request);

        return $this->responses->success($data);
    }

    public function listSignupRequests(Request $request): Response
    {
        $data = $this->service->listSignupRequests($request);

        return $this->responses->success($data);
    }

    public function approveSignupRequest(Request $request): Response
    {
        $requestId = (string) $request->attribute('id', '');
        $data = $this->service->approveSignupRequest($request, $requestId, $this->jsonBody($request));

        return $this->responses->success($data);
    }

    public function rejectSignupRequest(Request $request): Response
    {
        $requestId = (string) $request->attribute('id', '');
        $data = $this->service->rejectSignupRequest($request, $requestId, $this->jsonBody($request));

        return $this->responses->success($data);
    }

    public function listVouchers(Request $request): Response
    {
        $data = $this->service->listVouchers($request);

        return $this->responses->success($data);
    }

    public function createVoucher(Request $request): Response
    {
        $data = $this->service->createVoucher($request, $this->jsonBody($request));

        return $this->responses->success($data, status: 201);
    }

    public function extendCompanySubscription(Request $request): Response
    {
        $companyId = (string) $request->attribute('id', '');
        $data = $this->service->extendCompanySubscription($request, $companyId, $this->jsonBody($request));

        return $this->responses->success($data);
    }

    public function revokeDevice(Request $request): Response
    {
        $deviceId = (string) $request->attribute('id', '');
        $data = $this->service->revokeDevice($request, $deviceId);

        return $this->responses->success($data);
    }

    public function listAuditEvents(Request $request): Response
    {
        return $this->responses->success($this->auditService->listEvents($request));
    }

    public function getAuditEvent(Request $request): Response
    {
        $id = (string) $request->attribute('id', '');

        return $this->responses->success($this->auditService->getEvent($request, $id));
    }

    public function exportAuditEvents(Request $request): Response
    {
        return $this->auditService->export($request);
    }

    public function auditAlerts(Request $request): Response
    {
        return $this->responses->success($this->auditService->alerts($request));
    }

    public function getAuditRetention(Request $request): Response
    {
        return $this->responses->success($this->auditService->getRetention($request));
    }

    public function updateAuditRetention(Request $request): Response
    {
        return $this->responses->success(
            $this->auditService->updateRetention($request, $this->jsonBody($request)),
        );
    }

    public function runAuditRetention(Request $request): Response
    {
        return $this->responses->success($this->auditService->runRetention($request));
    }

    public function mutateAuditEventBlocked(Request $request): Response
    {
        $this->auditService->rejectMutation($request, strtoupper($request->method) . ' ' . $request->path);

        return $this->responses->error('forbidden', 'Audit events are immutable', 403);
    }

    /** @return array<string, mixed> */
    private function jsonBody(Request $request): array
    {
        if ($request->body === null || trim($request->body) === '') {
            return [];
        }

        $decoded = json_decode($request->body, true);
        if (!is_array($decoded)) {
            throw new HttpException('validation_error', 'Invalid JSON body', 400);
        }

        return $decoded;
    }
}

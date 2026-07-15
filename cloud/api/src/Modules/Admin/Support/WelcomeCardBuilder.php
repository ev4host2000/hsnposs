<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Admin\Support;

final class WelcomeCardBuilder
{
    public function build(
        string $storeName,
        string $email,
        string $companyId,
        string $branchId,
        string $planCode,
        string $apiUrl = 'https://api.mizapos.com',
    ): string {
        return implode("\n", [
            '═══════════════════════════════════════',
            '  MizaPos Cloud — بطاقة ترحيب Beta',
            '═══════════════════════════════════════',
            "المتجر:     {$storeName}",
            "البريد:     {$email}",
            'كلمة المرور: *(أُرسلت بقناة آمنة)*',
            "الخطة:      {$planCode}",
            "API:        {$apiUrl}",
            'لوحة المالك: ' . rtrim($apiUrl, '/') . '/owner/',
            'الدعم:      info@mizapos.com',
            '═══════════════════════════════════════',
        ]);
    }
}

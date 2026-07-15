<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Admin\Support;

final class BetaApprovalEmailBuilder
{
    /**
     * @return array{subject: string, text: string, html: string}
     */
    public function buildApproval(
        string $storeName,
        string $email,
        string $password,
        string $planCode,
        string $apiUrl,
    ): array {
        $ownerUrl = rtrim($apiUrl, '/') . '/owner/';
        $subject = 'تم تفعيل حسابكم على MizaPos Cloud — Beta';

        $text = implode("\n", [
            'مرحباً بكم في MizaPos Cloud Beta',
            '',
            "تمت الموافقة على طلب تسجيل متجر «{$storeName}».",
            '',
            'بيانات الدخول:',
            "  البريد: {$email}",
            "  كلمة المرور: {$password}",
            "  الخطة: {$planCode}",
            '',
            'الخطوات التالية:',
            '1. حمّلوا تطبيق MizaPos على الجهاز (Android).',
            '2. اختاروا «السحابة» وسجّلوا الدخول بالبريد وكلمة المرور أعلاه.',
            '3. يمكنكم متابعة الاشتراك من لوحة المالك:',
            "   {$ownerUrl}",
            '',
            "API: {$apiUrl}",
            'الدعم: info@mizapos.com',
            '',
            '— فريق MizaPos',
        ]);

        $html = '<!DOCTYPE html><html lang="ar" dir="rtl"><head><meta charset="UTF-8"></head><body style="font-family:Tahoma,Arial,sans-serif;line-height:1.6;color:#1a2332;">'
            . '<h2 style="color:#2563eb;">مرحباً بكم في MizaPos Cloud Beta</h2>'
            . '<p>تمت الموافقة على طلب تسجيل متجر <strong>' . $this->e($storeName) . '</strong>.</p>'
            . '<table style="background:#f3f6fb;border-radius:8px;padding:12px 16px;margin:16px 0;">'
            . '<tr><td style="padding:4px 8px;">البريد</td><td><strong>' . $this->e($email) . '</strong></td></tr>'
            . '<tr><td style="padding:4px 8px;">كلمة المرور</td><td><strong>' . $this->e($password) . '</strong></td></tr>'
            . '<tr><td style="padding:4px 8px;">الخطة</td><td>' . $this->e($planCode) . '</td></tr>'
            . '</table>'
            . '<p><strong>الخطوات التالية:</strong></p>'
            . '<ol>'
            . '<li>حمّلوا تطبيق MizaPos على الجهاز (Android).</li>'
            . '<li>اختاروا «السحابة» وسجّلوا الدخول بالبريد وكلمة المرور.</li>'
            . '<li>لوحة المالك: <a href="' . $this->e($ownerUrl) . '">' . $this->e($ownerUrl) . '</a></li>'
            . '</ol>'
            . '<p style="color:#64748b;font-size:14px;">الدعم: <a href="mailto:info@mizapos.com">info@mizapos.com</a></p>'
            . '</body></html>';

        return ['subject' => $subject, 'text' => $text, 'html' => $html];
    }

    /**
     * @return array{subject: string, text: string, html: string}
     */
    public function buildRejection(
        string $storeName,
        string $email,
        string $reason,
    ): array {
        $subject = 'بخصوص طلبكم للانضمام إلى MizaPos Cloud Beta';

        $text = implode("\n", [
            'مرحباً،',
            '',
            "شكراً لاهتمامكم بالانضمام إلى MizaPos Cloud Beta لمتجر «{$storeName}».",
            '',
            'للأسف لم نتمكن من قبول طلبكم في الوقت الحالي.',
            $reason !== '' ? "السبب: {$reason}" : '',
            '',
            'للاستفسار: info@mizapos.com',
            '',
            '— فريق MizaPos',
        ]);

        $reasonBlock = $reason !== ''
            ? '<p>السبب: ' . $this->e($reason) . '</p>'
            : '';

        $html = '<!DOCTYPE html><html lang="ar" dir="rtl"><head><meta charset="UTF-8"></head><body style="font-family:Tahoma,Arial,sans-serif;line-height:1.6;color:#1a2332;">'
            . '<p>مرحباً،</p>'
            . '<p>شكراً لاهتمامكم بالانضمام إلى MizaPos Cloud Beta لمتجر <strong>' . $this->e($storeName) . '</strong>.</p>'
            . '<p>للأسف لم نتمكن من قبول طلبكم في الوقت الحالي.</p>'
            . $reasonBlock
            . '<p style="color:#64748b;font-size:14px;">للاستفسار: <a href="mailto:info@mizapos.com">info@mizapos.com</a></p>'
            . '</body></html>';

        return ['subject' => $subject, 'text' => $text, 'html' => $html];
    }

    private function e(string $value): string
    {
        return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }
}

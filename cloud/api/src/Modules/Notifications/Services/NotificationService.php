<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Notifications\Services;

use MizaCloud\Modules\Notifications\Repositories\NotificationRepository;

final class NotificationService
{
    public function __construct(private readonly NotificationRepository $repository) {}
}

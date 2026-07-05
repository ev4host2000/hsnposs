<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Notifications\Models;

final class NotificationModel
{
    public function __construct(public readonly string $id = '') {}
}

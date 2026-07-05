<?php

declare(strict_types=1);

use MizaCloud\Core\Bootstrap\Application;

/**
 * تهيئة التطبيق — Container، Config، Router، Middleware pipeline.
 */

$basePath = dirname(__DIR__);

return Application::create($basePath);

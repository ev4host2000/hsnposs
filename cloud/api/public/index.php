<?php

declare(strict_types=1);

/**
 * Front controller — نقطة الدخول الوحيدة للـ HTTP.
 * لا منطق أعمال هنا؛ يُحمَّل Bootstrap فقط.
 */

$basePath = dirname(__DIR__);

require $basePath . '/vendor/autoload.php';

$app = require $basePath . '/bootstrap/app.php';

$app->run();

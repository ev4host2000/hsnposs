<?php

declare(strict_types=1);

namespace MizaCloud\Modules\Media\Controllers;

use MizaCloud\Core\Http\Controller;
use MizaCloud\Core\Http\Request;
use MizaCloud\Core\Http\Response;
use MizaCloud\Core\Http\ResponseBuilder;
use MizaCloud\Modules\Media\Services\ProductMediaService;

final class ProductMediaController extends Controller
{
    public function __construct(
        ResponseBuilder $responses,
        private readonly ProductMediaService $service,
    ) {
        parent::__construct($responses);
    }

    public function uploadProductImage(Request $request): Response
    {
        $data = $this->service->uploadProductImage($request);

        return $this->responses->success($data, status: 201);
    }
}

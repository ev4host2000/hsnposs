# Miza Cloud API Architecture

This document is a lightweight map for current backend skeleton in `cloud/api`.
الهدف هنا: تنظيم واضح للـ Modules مع فصل المسؤوليات قبل إضافة business logic.

## Layers (طبقات النظام)

- `Core/`: infrastructure shared across modules (Container, Router, HTTP, DB, helpers).
- `Modules/`: business domains organized as isolated modules.
- `storage/`: runtime artifacts مثل logs والكاش المؤقت.

## Module Structure (نمط موحد)

Each module follows this shape:

- `{Module}Module.php`: module entrypoint implementing `ModuleInterface`.
- `Controllers/`: HTTP controllers extending `Controller`.
- `Services/`: application orchestration services.
- `Repositories/`: data access classes extending `Repository`.
- `Models/`: minimal readonly DTO-style models.
- `Validators/`: payload validators extending `Validator`.

## Registration Flow

Inside each `{Module}Module`:

1. Bind Repository as singleton.
2. Bind Service as singleton.
3. Bind Controller as singleton.
4. Keep `routes(Router $router)` empty until API contract is finalized.

هذا الترتيب يعطي DI واضح وقابل للتوسعة بدون تكرار.

## Current Phase

- No endpoints registered yet.
- No SQL or business rules inside module skeletons.
- Scaffolding is ready for incremental implementation per module.

## Next Suggested Steps

- Define request/response contracts per module.
- Add route groups تدريجياً بعد اعتماد API spec.
- Add unit tests for validators/services before full feature rollout.

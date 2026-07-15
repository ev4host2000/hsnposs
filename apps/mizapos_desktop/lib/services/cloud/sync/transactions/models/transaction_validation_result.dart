/// Outcome of framework-level validation (no business rules).
class TransactionValidationResult {
  const TransactionValidationResult.valid()
      : ok = true,
        code = null,
        message = null;

  const TransactionValidationResult.invalid(this.code, [this.message])
      : ok = false;

  final bool ok;
  final String? code;
  final String? message;
}
